import Compression
import Foundation

enum AudioCacheStore {
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
    let directory = AudioPlayerManager.audioCacheDir
      .appendingPathComponent(songID, isDirectory: true)
    try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  static func playableMainURL(for songID: String, expectedRemoteURL: URL? = nil) -> URL? {
    guard validateMainAudio(for: songID, expectedRemoteURL: expectedRemoteURL) else { return nil }
    return playableURL(for: files(for: songID).main)
  }

  static func playableStems(for songID: String, startOffset: TimeInterval) -> CachedStems? {
    let songFiles = files(for: songID)
    guard let vocals = playableURL(for: songFiles.vocals),
      let instruments = playableURL(for: songFiles.instruments)
    else {
      return nil
    }
    return CachedStems(vocals: vocals, instruments: instruments, startOffset: startOffset)
  }

  static func hasCachedMainAudio(for songID: String, expectedRemoteURL: URL? = nil) -> Bool {
    validateMainAudio(for: songID, expectedRemoteURL: expectedRemoteURL)
  }

  static func hasCachedStems(for songID: String) -> Bool {
    let songFiles = files(for: songID)
    return hasCachedPlayableFile(at: songFiles.vocals) && hasCachedPlayableFile(at: songFiles.instruments)
  }

  static func compressedURL(for playableURL: URL) -> URL {
    playableURL.appendingPathExtension(compressionExtension)
  }

  static func cachedSongDirectories() -> [URL] {
    guard
      let entries = try? fm.contentsOfDirectory(
        at: AudioPlayerManager.audioCacheDir,
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
        at: AudioPlayerManager.audioCacheDir,
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
        at: AudioPlayerManager.audioCacheDir,
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

    let rootPath = AudioPlayerManager.audioCacheDir.path
    let songDirectory = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
    if songDirectory.path.hasPrefix(rootPath), songDirectory.path != rootPath {
      try? fm.setAttributes([.modificationDate: now], ofItemAtPath: songDirectory.path)
    }
  }

  private static func hasCachedPlayableFile(at url: URL) -> Bool {
    fm.fileExists(atPath: url.path) || fm.fileExists(atPath: compressedURL(for: url).path)
  }

  private static func validateMainAudio(for songID: String, expectedRemoteURL: URL?) -> Bool {
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

  private static func playableURL(for url: URL) -> URL? {
    if fm.fileExists(atPath: url.path) {
      touch(url)
      return url
    }
    let compressed = compressedURL(for: url)
    guard fm.fileExists(atPath: compressed.path) else { return nil }
    do {
      try decompressFileIfNeeded(from: compressed, to: url)
      touch(url)
      return url
    } catch {
      DebugLogger.log("Audio cache decompress failed for \(url.lastPathComponent): \(error)", category: .cache)
      try? fm.removeItem(at: url)
      return nil
    }
  }

  private static func compressPlayableFileIfNeeded(at url: URL) {
    guard fm.fileExists(atPath: url.path) else { return }
    let compressed = compressedURL(for: url)

    if compressedIsCurrent(for: url, compressedURL: compressed) {
      try? fm.removeItem(at: url)
      return
    }

    do {
      try compressFile(from: url, to: compressed)
      try? fm.removeItem(at: url)
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
  }

  private static func decompressFileIfNeeded(from sourceURL: URL, to destinationURL: URL) throws {
    let tempURL = destinationURL.appendingPathExtension("tmp")
    try? fm.removeItem(at: tempURL)
    fm.createFile(atPath: tempURL.path, contents: nil)

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
  }
}
