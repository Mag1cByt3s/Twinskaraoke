import AVFoundation
import Combine
import CoreML
import Foundation
import Spleeter

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

struct CachedStems {
  let vocals: URL
  let instruments: URL
  let startOffset: TimeInterval
  /// Whether these stems are temporary (real-time mode, should not persist)
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

  @Published private(set) var processingSongID: String?
  @Published private(set) var progressFraction: Float = 0
  @Published private(set) var isBackgroundAnalyzing: Bool = false

  let isAvailable: Bool
  private let modelURL: URL?
  private var activeTask: Task<URL, Error>?
  private var backgroundAnalysisTask: Task<Void, Never>?

  private static var stemsCacheDir: URL {
    let dir = AudioPlayerManager.audioCacheDir
      .appendingPathComponent("Stems", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

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
    validCachedURL(Self.stemsCacheDir.appendingPathComponent("\(songID).vocals.wav"))
  }

  func cachedInstrumentsURL(forSongID songID: String) -> URL? {
    validCachedURL(Self.stemsCacheDir.appendingPathComponent("\(songID).instruments.wav"))
  }

  func cachedStems(forSongID songID: String) -> CachedStems? {
    guard let v = cachedVocalsURL(forSongID: songID),
      let inst = cachedInstrumentsURL(forSongID: songID)
    else { return nil }
    let offset = cachedStartOffset(forSongID: songID)
    DebugLogger.log("Cache hit for stems: \(songID)", category: .separation)
    // Touch files for LRU tracking
    CacheManager.shared.recordAccess(for: v)
    CacheManager.shared.recordAccess(for: inst)
    return CachedStems(vocals: v, instruments: inst, startOffset: offset)
  }

  func cachedStartOffset(forSongID songID: String) -> TimeInterval {
    let offsetURL = Self.stemsCacheDir.appendingPathComponent("\(songID).offset")
    guard let data = try? Data(contentsOf: offsetURL),
      let str = String(data: data, encoding: .utf8),
      let val = Double(str.trimmingCharacters(in: .whitespacesAndNewlines))
    else { return 0 }
    return val
  }

  // MARK: - Full Separation (cached, for auto-analyze mode)

  func separate(
    forSongID songID: String, sourceURL: URL, startTime: TimeInterval = 0
  ) async throws -> CachedStems {
    if let cached = cachedStems(forSongID: songID) { return cached }
    guard isAvailable, let modelURL else { throw VocalSeparatorError.unavailable }
    if processingSongID == songID, let active = activeTask {
      DebugLogger.log("Waiting for in-progress separation: \(songID)", category: .separation)
      _ = try await active.value
      if let cached = cachedStems(forSongID: songID) { return cached }
      throw VocalSeparatorError.unavailable
    }
    if let old = activeTask {
      old.cancel()
      activeTask = nil
      processingSongID = nil
      progressFraction = 0
    }
    try Task.checkCancellation()
    guard #available(iOS 18.0, *) else { throw VocalSeparatorError.unavailable }
    DebugLogger.log(
      "Starting full separation for \(songID), startTime=\(startTime)",
      category: .separation)
    processingSongID = songID
    let vocalsURL = Self.stemsCacheDir.appendingPathComponent("\(songID).vocals.wav")
    let instrumentsURL = Self.stemsCacheDir.appendingPathComponent("\(songID).instruments.wav")
    let offsetURL = Self.stemsCacheDir.appendingPathComponent("\(songID).offset")
    let modelRef = modelURL
    let normalizedStart = max(0, startTime)
    let task = Task<URL, Error>.detached {
      do {
        let trimmedSource: URL
        let trimmedTemp: URL?
        if normalizedStart > 1.0 {
          let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(songID).aitrim.m4a")
          try await Self.trim(source: sourceURL, from: normalizedStart, to: tmp)
          trimmedSource = tmp
          trimmedTemp = tmp
        } else {
          trimmedSource = sourceURL
          trimmedTemp = nil
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
        if let trimmedTemp { try? FileManager.default.removeItem(at: trimmedTemp) }
        try? FileManager.default.removeItem(at: offsetURL)
        if normalizedStart > 1.0 {
          try? "\(normalizedStart)".data(using: .utf8)?.write(to: offsetURL)
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
    // Enforce cache limits after new stems are written
    CacheManager.shared.enforceMusicCacheLimits()
    guard let stems = cachedStems(forSongID: songID) else {
      throw VocalSeparatorError.unavailable
    }
    DebugLogger.log("Full separation complete for \(songID)", category: .separation)
    return stems
  }

  // MARK: - Real-Time Partial Separation (no persistent cache)

  /// Processes only from `fromTime` forward. Writes to temporary directory, not persistent cache.
  func separateRealTime(
    forSongID songID: String, sourceURL: URL, fromTime: TimeInterval
  ) async throws -> CachedStems {
    guard isAvailable, let modelURL else { throw VocalSeparatorError.unavailable }

    if let old = activeTask {
      old.cancel()
      activeTask = nil
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
    let vocalsURL = Self.realtimeTempDir.appendingPathComponent("\(songID).vocals.wav")
    let instrumentsURL = Self.realtimeTempDir.appendingPathComponent("\(songID).instruments.wav")
    let modelRef = modelURL

    let task = Task<URL, Error>.detached {
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
        try await Self.runSeparation2(
          modelURL: modelRef,
          songID: songID,
          sourceURL: trimmedSource,
          vocalsOutputURL: vocalsURL,
          instrumentsOutputURL: instrumentsURL
        ) { fraction in
          await VocalSeparator.shared.updateProgress(songID: songID, fraction: fraction)
        }
        if let trimmedTemp { try? FileManager.default.removeItem(at: trimmedTemp) }
        await VocalSeparator.shared.finishJob(songID: songID)
        return vocalsURL
      } catch {
        await VocalSeparator.shared.finishJob(songID: songID)
        throw error
      }
    }
    activeTask = task
    _ = try await task.value

    // Verify output files exist
    guard FileManager.default.fileExists(atPath: vocalsURL.path),
      FileManager.default.fileExists(atPath: instrumentsURL.path)
    else {
      throw VocalSeparatorError.unavailable
    }

    DebugLogger.log(
      "Real-time separation complete for \(songID), offset=\(normalizedStart)",
      category: .separation)
    return CachedStems(
      vocals: vocalsURL,
      instruments: instrumentsURL,
      startOffset: normalizedStart,
      isTemporary: true)
  }

  // MARK: - Background Analysis (auto-analyze mode)

  /// Starts background separation without blocking playback. Results go to persistent cache.
  func analyzeInBackground(songID: String, sourceURL: URL) {
    guard isAvailable else { return }
    guard cachedStems(forSongID: songID) == nil else {
      DebugLogger.log(
        "Background analysis skipped — stems already cached for \(songID)",
        category: .ai)
      return
    }
    // Don't start if already processing this song
    guard processingSongID != songID else { return }

    DebugLogger.log("Starting background analysis for \(songID)", category: .ai)
    isBackgroundAnalyzing = true

    backgroundAnalysisTask?.cancel()
    backgroundAnalysisTask = Task { @MainActor [weak self] in
      do {
        _ = try await self?.separate(forSongID: songID, sourceURL: sourceURL, startTime: 0)
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
    isBackgroundAnalyzing = false
    DebugLogger.log("Background analysis cancelled", category: .ai)
  }

  // MARK: - Cleanup

  func cancel() {
    let old = activeTask
    activeTask = nil
    processingSongID = nil
    progressFraction = 0
    old?.cancel()
    DebugLogger.log("Separation cancelled", category: .separation)
  }

  func clearCache() {
    try? FileManager.default.removeItem(at: Self.stemsCacheDir)
    DebugLogger.log("Stems cache cleared", category: .cache)
  }

  /// Cleans up temporary real-time stems
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

  // MARK: - Internal

  private func updateProgress(songID: String, fraction: Float) {
    if processingSongID == songID { progressFraction = fraction }
  }

  fileprivate func finishJob(songID: String) {
    if processingSongID == songID {
      processingSongID = nil
      progressFraction = 0
      activeTask = nil
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
    let duration: CMTime
    if #available(iOS 16.0, *) {
      duration = try await asset.load(.duration)
    } else {
      duration = asset.duration
    }
    export.timeRange = CMTimeRange(start: start, end: duration)
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
      }
    }
  }

  private static func cleanupTmpFiles(_ urls: [URL]) {
    for url in urls {
      try? FileManager.default.removeItem(at: url)
    }
  }
}
