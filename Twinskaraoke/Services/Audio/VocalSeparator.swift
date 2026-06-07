import AVFoundation
import Combine
import CoreML
import Foundation
import Spleeter

extension Notification.Name {
  static let vocalSeparatorDidCacheStems = Notification.Name("VocalSeparatorDidCacheStems")
}

enum DeviceCapability {
  static var supportsKaraoke: Bool {
    if #available(iOS 18.0, *) {
      return VocalSeparator.shared.isAvailable
    } else {
      return false
    }
  }
}

enum VocalSeparatorError: Error {
  case unavailable
  case cancelled
  case modelMissing
  case trimFailed
  case readFailed
}

nonisolated struct CachedStems {
  let vocals: URL
  let instruments: URL
  let startOffset: TimeInterval
  let isTemporary: Bool

  init(vocals: URL, instruments: URL, startOffset: TimeInterval, isTemporary: Bool = false) {
    self.vocals = vocals
    self.instruments = instruments
    self.startOffset = startOffset
    self.isTemporary = isTemporary
  }
}

@MainActor
final class VocalSeparator: ObservableObject {
  static let shared = VocalSeparator()

  private enum SeparationTaskKind {
    case foreground
    case background
  }

  @Published private(set) var processingSongID: String?
  @Published private(set) var progressFraction: Float = 0
  @Published private(set) var isBackgroundAnalyzing: Bool = false

  let isAvailable: Bool
  private let modelURL: URL?
  private var activeTask: Task<URL, Error>?
  private var activeTaskKind: SeparationTaskKind?
  private var backgroundAnalysisTask: Task<Void, Never>?

  private static var realtimeTempDir: URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("RealtimeStems", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private init() {
    let url = Bundle.main.url(forResource: "Spleeter2Model", withExtension: "mlmodelc")
    self.modelURL = url
    if #available(iOS 18.0, *) {
      self.isAvailable = (url != nil)
    } else {
      self.isAvailable = false
    }
    DebugLogger.log(
      "VocalSeparator init — available: \(self.isAvailable), model: \(url?.lastPathComponent ?? "nil")",
      category: .separation)
  }

  private func validCachedURL(_ url: URL) -> URL? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
      let size = attrs[.size] as? UInt64, size > 44
    else { return nil }
    return url
  }

  func cachedVocalsURL(forSongID songID: String) -> URL? {
    let url = AudioCacheStore.files(for: songID).vocals
    return validCachedURL(url) ?? validCachedURL(AudioCacheStore.compressedURL(for: url))
  }

  func cachedInstrumentsURL(forSongID songID: String) -> URL? {
    let url = AudioCacheStore.files(for: songID).instruments
    return validCachedURL(url) ?? validCachedURL(AudioCacheStore.compressedURL(for: url))
  }

  private func removeCachedStems(forSongID songID: String) {
    AudioCacheStore.removeStemCache(for: songID)
  }

  func cachedStems(
    forSongID songID: String,
    expectedDuration: TimeInterval? = nil
  ) -> CachedStems? {
    let offset = AudioCacheStore.readStartOffset(for: songID)
    guard offset <= 1.0 else {
      DebugLogger.log(
        "Discarding legacy partial stem cache for \(songID) (offset=\(offset))",
        category: .separation)
      removeCachedStems(forSongID: songID)
      return nil
    }
    guard
      let stems = AudioCacheStore.playableStems(
        for: songID,
        startOffset: offset,
        expectedDuration: expectedDuration)
    else {
      return nil
    }
    DebugLogger.log("Cache hit for stems: \(songID)", category: .separation)
    CacheManager.shared.recordAccess(for: stems.vocals)
    CacheManager.shared.recordAccess(for: stems.instruments)
    return stems
  }

  func cachedStartOffset(forSongID songID: String) -> TimeInterval {
    AudioCacheStore.readStartOffset(for: songID)
  }

  func separate(
    forSongID songID: String, sourceURL: URL, initiatedByBackground: Bool = false
  ) async throws -> CachedStems {
    let expectedDuration = Self.expectedDuration(for: sourceURL)
    if let cached = cachedStems(forSongID: songID, expectedDuration: expectedDuration) {
      return cached
    }
    guard isAvailable, let modelURL else { throw VocalSeparatorError.unavailable }
    if processingSongID == songID, let active = activeTask {
      DebugLogger.log("Waiting for in-progress separation: \(songID)", category: .separation)
      _ = try await active.value
      if let cached = cachedStems(forSongID: songID, expectedDuration: expectedDuration) {
        return cached
      }
      throw VocalSeparatorError.unavailable
    }
    if let old = activeTask {
      old.cancel()
      activeTask = nil
      activeTaskKind = nil
      processingSongID = nil
      progressFraction = 0
    }
    try Task.checkCancellation()
    guard #available(iOS 18.0, *) else { throw VocalSeparatorError.unavailable }
    DebugLogger.log("Starting full separation for \(songID)", category: .separation)
    processingSongID = songID
    activeTaskKind = initiatedByBackground ? .background : .foreground
    let songFiles = AudioCacheStore.files(for: songID)
    let vocalsURL = songFiles.vocals
    let instrumentsURL = songFiles.instruments
    let modelRef = modelURL
    let task = Task<URL, Error>.detached(priority: .utility) {
      do {
        try await Self.runSeparation2(
          modelURL: modelRef,
          songID: songID,
          sourceURL: sourceURL,
          vocalsOutputURL: vocalsURL,
          instrumentsOutputURL: instrumentsURL
        ) { fraction in
          await VocalSeparator.shared.updateProgress(songID: songID, fraction: fraction)
        }
        AudioCacheStore.clearMainOffset(for: songID)
        await VocalSeparator.shared.finishJob(songID: songID)
        await MainActor.run {
          NotificationCenter.default.post(
            name: .vocalSeparatorDidCacheStems,
            object: songID)
        }
        return vocalsURL
      } catch {
        await VocalSeparator.shared.finishJob(songID: songID)
        throw error
      }
    }
    activeTask = task
    _ = try await task.value
    CacheManager.shared.enforceMusicCacheLimits()
    guard let stems = cachedStems(forSongID: songID, expectedDuration: expectedDuration) else {
      throw VocalSeparatorError.unavailable
    }
    DebugLogger.log("Full separation complete for \(songID)", category: .separation)
    return stems
  }

  func separateRealTime(
    forSongID songID: String, sourceURL: URL, fromTime: TimeInterval
  ) async throws -> CachedStems {
    guard isAvailable, let modelURL else { throw VocalSeparatorError.unavailable }

    if let old = activeTask {
      old.cancel()
      activeTask = nil
      activeTaskKind = nil
      processingSongID = nil
      progressFraction = 0
    }

    try Task.checkCancellation()
    guard #available(iOS 18.0, *) else { throw VocalSeparatorError.unavailable }

    let normalizedStart = max(0, fromTime)
    DebugLogger.log(
      "Starting real-time separation for \(songID) from \(normalizedStart)s (no persistent cache)",
      category: .separation)

    processingSongID = songID
    activeTaskKind = .foreground
    let vocalsURL = Self.realtimeTempDir.appendingPathComponent("\(songID).vocals.wav")
    let instrumentsURL = Self.realtimeTempDir.appendingPathComponent("\(songID).instruments.wav")
    let modelRef = modelURL

    let task = Task<URL, Error>.detached(priority: .utility) {
      do {
        let trimmedSource: URL
        let trimmedTemp: URL?
        if normalizedStart > 1.0 {
          let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(songID).rt.trim.m4a")
          try await Self.trim(source: sourceURL, from: normalizedStart, to: tmp)
          trimmedSource = tmp
          trimmedTemp = tmp
        } else {
          trimmedSource = sourceURL
          trimmedTemp = nil
        }
        defer {
          if let trimmedTemp {
            try? FileManager.default.removeItem(at: trimmedTemp)
          }
        }
        try await Self.runSeparation2(
          modelURL: modelRef,
          songID: songID,
          sourceURL: trimmedSource,
          vocalsOutputURL: vocalsURL,
          instrumentsOutputURL: instrumentsURL
        ) { fraction in
          await VocalSeparator.shared.updateProgress(songID: songID, fraction: fraction)
        }
        await VocalSeparator.shared.finishJob(songID: songID)
        return vocalsURL
      } catch {
        await VocalSeparator.shared.finishJob(songID: songID)
        throw error
      }
    }
    activeTask = task
    _ = try await task.value

    guard FileManager.default.fileExists(atPath: vocalsURL.path),
      FileManager.default.fileExists(atPath: instrumentsURL.path)
    else {
      throw VocalSeparatorError.unavailable
    }

    DebugLogger.log(
      "Real-time separation complete for \(songID), offset=\(normalizedStart)",
      category: .separation)
    let offset = normalizedStart > 1.0 ? normalizedStart : 0
    return CachedStems(
      vocals: vocalsURL,
      instruments: instrumentsURL,
      startOffset: offset,
      isTemporary: true)
  }

  func analyzeInBackground(songID: String, sourceURL: URL) {
    guard isAvailable else { return }
    guard cachedStems(forSongID: songID) == nil else {
      DebugLogger.log(
        "Background analysis skipped — stems already cached for \(songID)",
        category: .ai)
      return
    }
    guard processingSongID != songID else { return }

    DebugLogger.log("Starting background analysis for \(songID)", category: .ai)
    isBackgroundAnalyzing = true

    backgroundAnalysisTask?.cancel()
    backgroundAnalysisTask = Task { @MainActor [weak self] in
      do {
        _ = try await self?.separate(
          forSongID: songID,
          sourceURL: sourceURL,
          initiatedByBackground: true)
        DebugLogger.log("Background analysis succeeded for \(songID)", category: .ai)
      } catch is CancellationError {
        DebugLogger.log("Background analysis cancelled for \(songID)", category: .ai)
      } catch VocalSeparatorError.cancelled {
        DebugLogger.log("Background analysis cancelled for \(songID)", category: .ai)
      } catch {
        DebugLogger.log("Background analysis failed for \(songID): \(error)", category: .ai)
      }
      self?.isBackgroundAnalyzing = false
    }
  }

  func cancelBackgroundAnalysis() {
    backgroundAnalysisTask?.cancel()
    backgroundAnalysisTask = nil
    if activeTaskKind == .background {
      let old = activeTask
      activeTask = nil
      activeTaskKind = nil
      processingSongID = nil
      progressFraction = 0
      old?.cancel()
    }
    isBackgroundAnalyzing = false
    DebugLogger.log("Background analysis cancelled", category: .ai)
  }

  func cancel() {
    let old = activeTask
    activeTask = nil
    activeTaskKind = nil
    processingSongID = nil
    progressFraction = 0
    old?.cancel()
    DebugLogger.log("Separation cancelled", category: .separation)
  }

  func clearCache() {
    for directory in AudioCacheStore.cachedSongDirectories() {
      let songID = directory.lastPathComponent
      removeCachedStems(forSongID: songID)
    }
    DebugLogger.log("Stems cache cleared", category: .cache)
  }

  func cleanupRealtimeTemp() {
    let dir = Self.realtimeTempDir
    if let entries = try? FileManager.default.contentsOfDirectory(
      at: dir, includingPropertiesForKeys: nil)
    {
      for entry in entries {
        try? FileManager.default.removeItem(at: entry)
      }
    }
    DebugLogger.log("Real-time temp files cleaned up", category: .separation)
  }

  private nonisolated static func expectedDuration(for sourceURL: URL) -> TimeInterval? {
    let duration = AudioCacheStore.audioDuration(at: sourceURL)
    guard duration.isFinite, duration > 1.0 else { return nil }
    return duration
  }

  private func updateProgress(songID: String, fraction: Float) {
    if processingSongID == songID { progressFraction = fraction }
  }

  fileprivate func finishJob(songID: String) {
    if processingSongID == songID {
      processingSongID = nil
      progressFraction = 0
      activeTask = nil
      activeTaskKind = nil
    }
  }

  private static func trim(source: URL, from startSeconds: TimeInterval, to output: URL)
    async throws
  {
    try? FileManager.default.removeItem(at: output)
    let asset = AVURLAsset(url: source)
    guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
    else { throw VocalSeparatorError.trimFailed }
    let start = CMTime(seconds: startSeconds, preferredTimescale: 600)
    let duration = try await asset.load(.duration)
    let safeStartSeconds = min(startSeconds, max(0, duration.seconds - 0.5))
    let safeStart = safeStartSeconds < startSeconds
      ? CMTime(seconds: safeStartSeconds, preferredTimescale: 600) : start
    export.timeRange = CMTimeRange(start: safeStart, end: duration)
    export.outputURL = output
    export.outputFileType = .m4a
    if #available(iOS 18.0, *) {
      try await export.export(to: output, as: .m4a)
    } else {
      await export.export()
      guard export.status == .completed else {
        throw export.error ?? VocalSeparatorError.trimFailed
      }
    }
  }

  @available(iOS 18.0, *)
  private static func runSeparation2(
    modelURL: URL,
    songID: String,
    sourceURL: URL,
    vocalsOutputURL: URL,
    instrumentsOutputURL: URL,
    onProgress: @Sendable @escaping (Float) async -> Void
  ) async throws {
    let separator = try AudioSeparator2(modelURL: modelURL)
    let tmpDir = FileManager.default.temporaryDirectory
    let tmpVocals = tmpDir.appendingPathComponent("\(songID).vocals.wav")
    let tmpInstruments = tmpDir.appendingPathComponent("\(songID).instruments.wav")
    try? FileManager.default.removeItem(at: tmpVocals)
    try? FileManager.default.removeItem(at: tmpInstruments)
    let stems = Stems2(vocals: tmpVocals, accompaniment: tmpInstruments)
    do {
      for try await prog in separator.separate(from: sourceURL, to: stems) {
        try Task.checkCancellation()
        await onProgress(prog.fraction)
      }
    } catch is CancellationError {
      cleanupTmpFiles([tmpVocals, tmpInstruments])
      throw VocalSeparatorError.cancelled
    } catch {
      cleanupTmpFiles([tmpVocals, tmpInstruments])
      throw error
    }
    let moves: [(URL, URL)] = [
      (tmpVocals, vocalsOutputURL),
      (tmpInstruments, instrumentsOutputURL),
    ]
    for (src, dst) in moves {
      try? FileManager.default.removeItem(at: dst)
      do {
        try FileManager.default.moveItem(at: src, to: dst)
      } catch {
        try? FileManager.default.removeItem(at: src)
        cleanupTmpFiles([tmpVocals, tmpInstruments])
        cleanupTmpFiles(moves.map { $0.1 })
        throw error
      }
    }
  }

  private static func cleanupTmpFiles(_ urls: [URL]) {
    for url in urls {
      try? FileManager.default.removeItem(at: url)
    }
  }
}
