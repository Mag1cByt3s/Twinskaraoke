import Combine
import Foundation
import SDWebImageSwiftUI

@MainActor
final class CacheManager: ObservableObject {
  static let shared = CacheManager()

  /// Image cache limit: 2 GB
  static let imageCacheLimit: UInt64 = 2 * 1024 * 1024 * 1024
  /// Music cache limit (original audio + AI stems): 4 GB
  static let musicCacheLimit: UInt64 = 4 * 1024 * 1024 * 1024
  /// Maximum cache age: 6 months
  static let maxCacheAge: TimeInterval = 6 * 30 * 24 * 3600

  @Published private(set) var imageCacheSize: UInt64 = 0
  @Published private(set) var musicCacheSize: UInt64 = 0

  private let fm = FileManager.default

  private init() {
    refreshSizes()
    pruneExpiredEntries()
    enforceAllLimits()
    DebugLogger.log("CacheManager initialized", category: .cache)
  }

  // MARK: - Public API

  func enforceAllLimits() {
    enforceImageCacheLimits()
    enforceMusicCacheLimits()
  }

  func refreshSizes() {
    imageCacheSize = computeImageCacheSize()
    musicCacheSize = computeMusicCacheSize()
    DebugLogger.log(
      "Cache sizes — images: \(formatBytes(imageCacheSize)), music: \(formatBytes(musicCacheSize))",
      category: .cache)
  }

  func enforceImageCacheLimits() {
    let sdCache = SDImageCache.shared
    let diskSize = UInt64(sdCache.totalDiskSize())

    if diskSize > Self.imageCacheLimit {
      DebugLogger.log(
        "Image cache \(formatBytes(diskSize)) exceeds limit \(formatBytes(Self.imageCacheLimit)), clearing oldest",
        category: .cache)
      sdCache.deleteOldFiles(completionBlock: nil)
    }

    // Also check custom image cache directories if any
    let imageCacheDir = Self.imageCacheDirectory
    evictOldestFiles(in: imageCacheDir, limit: Self.imageCacheLimit, label: "image")

    imageCacheSize = computeImageCacheSize()
  }

  func enforceMusicCacheLimits() {
    let musicDir = AudioPlayerManager.audioCacheDir
    evictOldestFiles(in: musicDir, limit: Self.musicCacheLimit, label: "music")
    musicCacheSize = computeMusicCacheSize()
  }

  func pruneExpiredEntries() {
    let cutoff = Date().addingTimeInterval(-Self.maxCacheAge)
    DebugLogger.log("Pruning cache entries older than \(cutoff)", category: .cache)

    var prunedCount = 0

    // Prune music cache
    let musicDir = AudioPlayerManager.audioCacheDir
    prunedCount += pruneOldFiles(in: musicDir, olderThan: cutoff)

    // Prune SDWebImage cache (it has its own expiry, but we enforce 6-month hard limit)
    SDImageCache.shared.deleteOldFiles(completionBlock: nil)

    DebugLogger.log("Pruned \(prunedCount) expired cache entries", category: .cache)
    refreshSizes()
  }

  func recordAccess(for url: URL) {
    // Touch the file's access date so LRU eviction works correctly
    try? fm.setAttributes(
      [.modificationDate: Date()],
      ofItemAtPath: url.path)
  }

  func totalImageCacheSize() -> UInt64 { imageCacheSize }
  func totalMusicCacheSize() -> UInt64 { musicCacheSize }

  func clearImageCache() {
    SDImageCache.shared.clearMemory()
    SDImageCache.shared.clearDisk(onCompletion: nil)
    let dir = Self.imageCacheDirectory
    removeAllFiles(in: dir)
    imageCacheSize = 0
    DebugLogger.log("Image cache cleared", category: .cache)
  }

  func clearMusicCache() {
    let dir = AudioPlayerManager.audioCacheDir
    removeAllFiles(in: dir)
    musicCacheSize = 0
    DebugLogger.log("Music cache cleared", category: .cache)
  }

  // MARK: - Size Formatting

  func formattedImageCacheSize() -> String { formatBytes(imageCacheSize) }
  func formattedMusicCacheSize() -> String { formatBytes(musicCacheSize) }

  // MARK: - Private

  private static var imageCacheDirectory: URL {
    let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
      .appendingPathComponent("com.hackemist.SDImageCache/default", isDirectory: true)
    return dir
  }

  private func computeImageCacheSize() -> UInt64 {
    let sdSize = UInt64(SDImageCache.shared.totalDiskSize())
    return sdSize
  }

  private func computeMusicCacheSize() -> UInt64 {
    directorySize(at: AudioPlayerManager.audioCacheDir)
  }

  private func directorySize(at url: URL) -> UInt64 {
    guard let enumerator = fm.enumerator(
      at: url,
      includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
      options: [.skipsHiddenFiles])
    else { return 0 }

    var total: UInt64 = 0
    for case let fileURL as URL in enumerator {
      guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
        values.isRegularFile == true,
        let size = values.fileSize
      else { continue }
      total += UInt64(size)
    }
    return total
  }

  private func evictOldestFiles(in directory: URL, limit: UInt64, label: String) {
    guard fm.fileExists(atPath: directory.path) else { return }

    var currentSize = directorySize(at: directory)
    guard currentSize > limit else { return }

    DebugLogger.log(
      "\(label) cache \(formatBytes(currentSize)) > limit \(formatBytes(limit)), evicting oldest",
      category: .cache)

    // Collect files sorted by modification date (oldest first)
    let sortedFiles = filesOrderedByDate(in: directory)

    var evicted = 0
    for file in sortedFiles {
      guard currentSize > limit else { break }
      let size = fileSize(at: file)
      try? fm.removeItem(at: file)
      currentSize -= size
      evicted += 1
      DebugLogger.log("Evicted: \(file.lastPathComponent) (\(formatBytes(size)))", category: .cache)
    }

    DebugLogger.log(
      "\(label) cache eviction complete: removed \(evicted) files, new size \(formatBytes(currentSize))",
      category: .cache)
  }

  private func pruneOldFiles(in directory: URL, olderThan cutoff: Date) -> Int {
    guard fm.fileExists(atPath: directory.path) else { return 0 }
    guard let enumerator = fm.enumerator(
      at: directory,
      includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
      options: [.skipsHiddenFiles])
    else { return 0 }

    var count = 0
    for case let fileURL as URL in enumerator {
      guard let values = try? fileURL.resourceValues(
        forKeys: [.contentModificationDateKey, .isRegularFileKey]),
        values.isRegularFile == true,
        let modified = values.contentModificationDate,
        modified < cutoff
      else { continue }
      try? fm.removeItem(at: fileURL)
      count += 1
    }
    return count
  }

  private func filesOrderedByDate(in directory: URL) -> [URL] {
    guard let enumerator = fm.enumerator(
      at: directory,
      includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
      options: [.skipsHiddenFiles])
    else { return [] }

    var files: [(url: URL, date: Date)] = []
    for case let fileURL as URL in enumerator {
      guard let values = try? fileURL.resourceValues(
        forKeys: [.contentModificationDateKey, .isRegularFileKey]),
        values.isRegularFile == true,
        let modified = values.contentModificationDate
      else { continue }
      files.append((url: fileURL, date: modified))
    }
    return files.sorted { $0.date < $1.date }.map(\.url)
  }

  private func fileSize(at url: URL) -> UInt64 {
    guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
      let size = values.fileSize
    else { return 0 }
    return UInt64(size)
  }

  private func removeAllFiles(in directory: URL) {
    guard let entries = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    else { return }
    for entry in entries {
      try? fm.removeItem(at: entry)
    }
  }

  private func formatBytes(_ bytes: UInt64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useMB, .useGB]
    formatter.countStyle = .binary
    return formatter.string(fromByteCount: Int64(bytes))
  }
}
