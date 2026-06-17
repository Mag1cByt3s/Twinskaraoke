import AVFoundation
import Compression
import Foundation

nonisolated enum AudioCacheStore {
  struct SongFiles {
    let directory: URL
    let main: URL
    let mainPartial: URL
    let mainSource: URL
    let vocals: URL
    let instruments: URL
    let offset: URL
  }

  private static let fm = FileManager.default
  private static let compressionExtension = "nkz"
  private static let compressionAlgorithm: Algorithm = .lzfse
  private static let chunkSize = 64 * 1024
  private static let maximumPlayableFileSize: Int64 = 256 * 1024 * 1024
  private static let cacheDirectory: URL = {
    let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
      .appendingPathComponent("AudioCache", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }()

  static func files(for songID: String) -> SongFiles {
    let directory = ensureSongDirectory(for: songID)
    return SongFiles(
      directory: directory,
      main: directory.appendingPathComponent("main.mp3"),
      mainPartial: directory.appendingPathComponent("main.mp3.partial"),
      mainSource: directory.appendingPathComponent("main.source"),
      vocals: directory.appendingPathComponent("vocals.wav"),
      instruments: directory.appendingPathComponent("instruments.wav"),
      offset: directory.appendingPathComponent("offset")
    )
  }

  static func ensureSongDirectory(for songID: String) -> URL {
    let directory = cacheDirectory.appendingPathComponent(songID, isDirectory: true)
    try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  static func playableMainURL(for songID: String, expectedRemoteURL: URL? = nil, expectedDuration: TimeInterval? = nil) -> URL? {
    guard validateMainAudio(for: songID, expectedRemoteURL: expectedRemoteURL, expectedDuration: expectedDuration) else { return nil }
    return playableURL(for: files(for: songID).main)
  }

  static func playableStems(
    for songID: String,
    startOffset: TimeInterval,
    expectedDuration: TimeInterval? = nil
  ) -> CachedStems? {
    let songFiles = files(for: songID)
    guard let vocals = playableURL(for: songFiles.vocals),
      let instruments = playableURL(for: songFiles.instruments)
    else {
      return nil
    }
    guard validateStemPair(
      vocals: vocals,
      instruments: instruments,
      startOffset: startOffset,
      expectedDuration: expectedDuration)
    else {
      DebugLogger.log("Removing invalid stem cache for \(songID)", category: .cache)
      removeStemCache(for: songID)
      return nil
    }
    return CachedStems(vocals: vocals, instruments: instruments, startOffset: startOffset)
  }

  static func hasCachedMainAudio(for songID: String, expectedRemoteURL: URL? = nil, expectedDuration: TimeInterval? = nil) -> Bool {
    validateMainAudio(for: songID, expectedRemoteURL: expectedRemoteURL, expectedDuration: expectedDuration)
  }

  static func hasCachedStems(for songID: String) -> Bool {
    playableStems(for: songID, startOffset: readStartOffset(for: songID)) != nil
  }

  static func compressedURL(for playableURL: URL) -> URL {
    playableURL.appendingPathExtension(compressionExtension)
  }

  static func cachedSongDirectories() -> [URL] {
    guard
      let entries = try? fm.contentsOfDirectory(
        at: cacheDirectory,
        includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
        options: [.skipsHiddenFiles])
    else {
      return []
    }
    return entries.filter {
      (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
  }

  static func removeSongCache(for songID: String) {
    try? fm.removeItem(at: files(for: songID).directory)
  }

  static func removeStemCache(for songID: String) {
    let songFiles = files(for: songID)
    let urls = [
      songFiles.vocals,
      songFiles.instruments,
      compressedURL(for: songFiles.vocals),
      compressedURL(for: songFiles.instruments),
      songFiles.offset,
    ]
    for url in urls {
      try? fm.removeItem(at: url)
    }
  }

  static func clearMainOffset(for songID: String) {
    try? fm.removeItem(at: files(for: songID).offset)
  }

  static func writeMainSourceURL(_ remoteURL: URL?, for songID: String) {
    let sourceURL = files(for: songID).mainSource
    guard let remoteURL else {
      try? fm.removeItem(at: sourceURL)
      return
    }
    let data = remoteURL.absoluteString.data(using: .utf8)
    try? fm.removeItem(at: sourceURL)
    fm.createFile(atPath: sourceURL.path, contents: data)
  }

  static func writeStartOffset(_ offset: TimeInterval, for songID: String) {
    let data = "\(offset)".data(using: .utf8)
    fm.createFile(atPath: files(for: songID).offset.path, contents: data)
  }

  static func readStartOffset(for songID: String) -> TimeInterval {
    guard let data = try? Data(contentsOf: files(for: songID).offset),
      let str = String(data: data, encoding: .utf8),
      let value = Double(str.trimmingCharacters(in: .whitespacesAndNewlines))
    else {
      return 0
    }
    return value
  }

  static func cleanupLegacyArtifacts() {
    cleanupPartialFiles()
    guard
      let entries = try? fm.contentsOfDirectory(
        at: cacheDirectory,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles])
    else {
      return
    }
    for entry in entries {
      let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
      if !isDirectory {
        try? fm.removeItem(at: entry)
      }
    }
  }

  static func cleanupPartialFiles() {
    guard
      let enumerator = fm.enumerator(
        at: cacheDirectory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles])
    else {
      return
    }
    for case let fileURL as URL in enumerator {
      guard
        (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
      else {
        continue
      }
      if fileURL.lastPathComponent.hasSuffix(".partial") {
        try? fm.removeItem(at: fileURL)
      }
    }
  }

  static func compressIdleAssets(excluding songIDs: Set<String>) {
    for directory in cachedSongDirectories() where !songIDs.contains(directory.lastPathComponent) {
      if Task.isCancelled { break }
      let songID = directory.lastPathComponent
      compressAssets(for: songID)
    }
  }

  static func compressAssets(for songID: String) {
    let songFiles = files(for: songID)
    compressPlayableFileIfNeeded(at: songFiles.main)
    compressPlayableFileIfNeeded(at: songFiles.vocals)
    compressPlayableFileIfNeeded(at: songFiles.instruments)
  }

  static func touch(_ url: URL) {
    let now = Date()
    try? fm.setAttributes([.modificationDate: now], ofItemAtPath: url.path)

    let rootPath = cacheDirectory.path
    let songDirectory = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
    if songDirectory.path.hasPrefix(rootPath), songDirectory.path != rootPath {
      try? fm.setAttributes([.modificationDate: now], ofItemAtPath: songDirectory.path)
    }
  }

  private static func hasCachedPlayableFile(at url: URL) -> Bool {
    fm.fileExists(atPath: url.path) || fm.fileExists(atPath: compressedURL(for: url).path)
  }

  private static func validateMainAudio(for songID: String, expectedRemoteURL: URL?, expectedDuration: TimeInterval?) -> Bool {
    let songFiles = files(for: songID)
    guard hasCachedPlayableFile(at: songFiles.main) else { return false }
    guard let expectedRemoteURL else { return true }
    guard let cachedSource = readMainSourceURL(for: songID) else {
      DebugLogger.log(
        "Discarding legacy audio cache without source metadata for \(songID)",
        category: .cache)
      removeSongCache(for: songID)
      return false
    }
    guard cachedSource == expectedRemoteURL.absoluteString else {
      DebugLogger.log(
        "Discarding stale audio cache for \(songID) due to source mismatch",
        category: .cache)
      removeSongCache(for: songID)
      return false
    }
    if let expectedDuration, expectedDuration > 0 {
      guard let actualURL = playableURL(for: songFiles.main) else { return false }
      let actualDuration = getAudioDuration(at: actualURL)
      let tolerance: TimeInterval = 2.0
      if actualDuration > 0, abs(actualDuration - expectedDuration) > tolerance {
        DebugLogger.log(
          "Discarding audio cache for \(songID) due to duration mismatch: expected \(expectedDuration)s, got \(actualDuration)s",
          category: .cache)
        removeSongCache(for: songID)
        return false
      }
    }
    return true
  }

  private static func readMainSourceURL(for songID: String) -> String? {
    let sourceURL = files(for: songID).mainSource
    guard let data = try? Data(contentsOf: sourceURL),
      let rawValue = String(data: data, encoding: .utf8)
    else { return nil }
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }

  private static let minimumPlayableFileSize = 4096

  private static func playableURL(for url: URL) -> URL? {
    if fm.fileExists(atPath: url.path) {
      if !isValidAudioFile(at: url) {
        DebugLogger.log("Removing broken cache file: \(url.lastPathComponent)", category: .cache)
        try? fm.removeItem(at: url)
        try? fm.removeItem(at: compressedURL(for: url))
        return nil
      }
      touch(url)
      return url
    }
    let compressed = compressedURL(for: url)
    guard fm.fileExists(atPath: compressed.path) else { return nil }
    do {
      try decompressFileIfNeeded(from: compressed, to: url)
      if !isValidAudioFile(at: url) {
        DebugLogger.log("Removing broken compressed cache: \(url.lastPathComponent)", category: .cache)
        try? fm.removeItem(at: url)
        try? fm.removeItem(at: compressed)
        return nil
      }
      touch(url)
      return url
    } catch {
      DebugLogger.log("Audio cache decompress failed for \(url.lastPathComponent): \(error)", category: .cache)
      try? fm.removeItem(at: url)
      try? fm.removeItem(at: compressed)
      return nil
    }
  }

  private static func isValidAudioFile(at url: URL) -> Bool {
    guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
          size >= minimumPlayableFileSize else { return false }
    return AVEnginePlayback.hasValidAudioHeader(at: url)
  }

  static func audioDuration(at url: URL) -> TimeInterval {
    if let file = try? AVAudioFile(forReading: url) {
      let sampleRate = file.fileFormat.sampleRate
      if sampleRate > 0 {
        let duration = Double(file.length) / sampleRate
        if duration.isFinite, duration > 0 { return duration }
      }
    }
    return 0
  }

  static func acceptsAudioResponse(_ response: URLResponse?) -> Bool {
    guard let http = response as? HTTPURLResponse else { return true }
    guard (200...299).contains(http.statusCode) else { return false }
    if http.expectedContentLength > maximumPlayableFileSize {
      return false
    }
    guard let mimeType = http.mimeType?.lowercased(), !mimeType.isEmpty else { return true }
    return !mimeType.hasPrefix("text/")
      && mimeType != "application/json"
      && !mimeType.hasSuffix("+json")
  }

  static func isPlayableAudioFile(at url: URL) -> Bool {
    isValidAudioFile(at: url)
  }

  private static func getAudioDuration(at url: URL) -> TimeInterval {
    audioDuration(at: url)
  }

  private static func validateStemPair(
    vocals: URL,
    instruments: URL,
    startOffset: TimeInterval,
    expectedDuration: TimeInterval?
  ) -> Bool {
    guard startOffset.isFinite, startOffset >= 0 else { return false }
    let vocalsDuration = audioDuration(at: vocals)
    let instrumentsDuration = audioDuration(at: instruments)
    guard vocalsDuration.isFinite, instrumentsDuration.isFinite,
      vocalsDuration > 1.0, instrumentsDuration > 1.0
    else {
      return false
    }
    let pairTolerance = max(2.0, min(vocalsDuration, instrumentsDuration) * 0.02)
    guard abs(vocalsDuration - instrumentsDuration) <= pairTolerance else {
      return false
    }
    guard let expectedDuration, expectedDuration.isFinite, expectedDuration > 1.0 else {
      return true
    }
    let expectedStemDuration = max(0, expectedDuration - startOffset)
    guard expectedStemDuration > 1.0 else { return true }
    let expectedTolerance = max(4.0, expectedDuration * 0.05)
    return vocalsDuration + expectedTolerance >= expectedStemDuration
      && instrumentsDuration + expectedTolerance >= expectedStemDuration
  }

  private static func compressPlayableFileIfNeeded(at url: URL) {
    guard fm.fileExists(atPath: url.path) else { return }
    let compressed = compressedURL(for: url)

    if compressedIsCurrent(for: url, compressedURL: compressed) {
      if canDecompressFile(compressed) {
        try? fm.removeItem(at: url)
      } else {
        DebugLogger.log("Removing invalid compressed cache: \(compressed.lastPathComponent)", category: .cache)
        try? fm.removeItem(at: compressed)
      }
      return
    }

    do {
      try compressFile(from: url, to: compressed)
      if canDecompressFile(compressed) {
        try? fm.removeItem(at: url)
      } else {
        DebugLogger.log("Compression produced invalid file: \(compressed.lastPathComponent)", category: .cache)
        try? fm.removeItem(at: compressed)
      }
    } catch {
      DebugLogger.log("Audio cache compress failed for \(url.lastPathComponent): \(error)", category: .cache)
      try? fm.removeItem(at: compressed)
    }
  }

  private static func compressedIsCurrent(for sourceURL: URL, compressedURL: URL) -> Bool {
    guard fm.fileExists(atPath: compressedURL.path) else { return false }
    guard let sourceDate = modificationDate(for: sourceURL),
      let compressedDate = modificationDate(for: compressedURL)
    else {
      return true
    }
    return compressedDate >= sourceDate
  }

  private static func modificationDate(for url: URL) -> Date? {
    try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
  }

  private static func compressFile(from sourceURL: URL, to destinationURL: URL) throws {
    let tempURL = destinationURL.appendingPathExtension("tmp")
    try? fm.removeItem(at: tempURL)
    fm.createFile(atPath: tempURL.path, contents: nil)

    do {
      let reader = try FileHandle(forReadingFrom: sourceURL)
      let writer = try FileHandle(forWritingTo: tempURL)
      defer {
        try? reader.close()
        try? writer.close()
      }

      let filter = try OutputFilter(.compress, using: compressionAlgorithm) { data in
        guard let data else { return }
        try writer.write(contentsOf: data)
      }

      while true {
        let chunk = try reader.read(upToCount: chunkSize) ?? Data()
        if chunk.isEmpty { break }
        try filter.write(chunk)
      }
      try filter.finalize()

      try? fm.removeItem(at: destinationURL)
      try fm.moveItem(at: tempURL, to: destinationURL)
    } catch {
      try? fm.removeItem(at: tempURL)
      throw error
    }
  }

  private static func decompressFileIfNeeded(from sourceURL: URL, to destinationURL: URL) throws {
    let tempURL = destinationURL.appendingPathExtension("tmp")
    try? fm.removeItem(at: tempURL)
    fm.createFile(atPath: tempURL.path, contents: nil)

    do {
      let reader = try FileHandle(forReadingFrom: sourceURL)
      let writer = try FileHandle(forWritingTo: tempURL)
      defer {
        try? reader.close()
        try? writer.close()
      }

      let filter = try InputFilter<Data>(.decompress, using: compressionAlgorithm) { requestedCount in
        try reader.read(upToCount: requestedCount)
      }

      while let chunk = try filter.readData(ofLength: chunkSize), !chunk.isEmpty {
        try writer.write(contentsOf: chunk)
      }

      try? fm.removeItem(at: destinationURL)
      try fm.moveItem(at: tempURL, to: destinationURL)
    } catch {
      try? fm.removeItem(at: tempURL)
      throw error
    }
  }

  private static func canDecompressFile(_ compressedURL: URL) -> Bool {
    guard fm.fileExists(atPath: compressedURL.path) else { return false }
    do {
      let reader = try FileHandle(forReadingFrom: compressedURL)
      defer { try? reader.close() }
      let filter = try InputFilter<Data>(.decompress, using: compressionAlgorithm) { requestedCount in
        try reader.read(upToCount: requestedCount)
      }
      _ = try filter.readData(ofLength: chunkSize)
      return true
    } catch {
      return false
    }
  }
}
