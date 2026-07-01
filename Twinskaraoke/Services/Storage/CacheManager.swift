import Combine
import Foundation
import SDWebImageSwiftUI

@MainActor
final class CacheManager: ObservableObject {
    static let shared = CacheManager()

    nonisolated static let imageCacheLimit: UInt64 = 2 * 1024 * 1024 * 1024
    nonisolated static let musicCacheLimit: UInt64 = 4 * 1024 * 1024 * 1024
    nonisolated static let lyricsCacheLimit: UInt64 = 2 * 1024 * 1024 * 1024
    nonisolated static let maxCacheAge: TimeInterval = 6 * 30 * 24 * 3600

    @Published private(set) var imageCacheSize: UInt64 = 0
    @Published private(set) var musicCacheSize: UInt64 = 0
    @Published private(set) var lyricsCacheSize: UInt64 = 0

    private let fm = FileManager.default

    // Maintenance walks entire cache directories (music cache can hold
    // gigabytes across hundreds of folders). That file I/O must stay off the
    // main thread; the serial queue also keeps passes from overlapping.
    private nonisolated static let maintenanceQueue = DispatchQueue(
        label: "nk.cacheMaintenance", qos: .utility
    )

    private init() {
        let directories = Self.directories
        Self.maintenanceQueue.async { [weak self] in
            guard let self else { return }
            let pruned = pruneExpiredEntriesBlocking(directories: directories)
            DebugLogger.log("Pruned \(pruned) expired cache entries", category: .cache)
            _ = enforceImageCacheLimitsBlocking(imageDirectory: directories.image)
            _ = enforceMusicCacheLimitsBlocking(musicDirectory: directories.music, excluding: [])
            _ = enforceLyricsCacheLimitsBlocking(lyricsDirectory: directories.lyrics)
            publishSizes(computeSizesBlocking(directories: directories))
            DebugLogger.log("CacheManager initialized", category: .cache)
        }
    }

    private static var directories: (image: URL, music: URL, lyrics: URL) {
        (imageCacheDirectory, AudioPlayerManager.audioCacheDir, LyricsCacheStore.cacheDirectory)
    }

    func enforceAllLimits() {
        let directories = Self.directories
        Self.maintenanceQueue.async { [weak self] in
            guard let self else { return }
            let image = enforceImageCacheLimitsBlocking(imageDirectory: directories.image)
            let music = enforceMusicCacheLimitsBlocking(musicDirectory: directories.music, excluding: [])
            let lyrics = enforceLyricsCacheLimitsBlocking(lyricsDirectory: directories.lyrics)
            publishSizes((image: image, music: music, lyrics: lyrics))
        }
    }

    func refreshSizes() {
        let directories = Self.directories
        Self.maintenanceQueue.async { [weak self] in
            guard let self else { return }
            publishSizes(computeSizesBlocking(directories: directories))
        }
    }

    func enforceImageCacheLimits() {
        let imageDirectory = Self.imageCacheDirectory
        Self.maintenanceQueue.async { [weak self] in
            guard let self else { return }
            let size = enforceImageCacheLimitsBlocking(imageDirectory: imageDirectory)
            publishSizes((image: size, music: nil, lyrics: nil))
        }
    }

    func enforceMusicCacheLimits(excluding songIDs: Set<String> = []) {
        let musicDirectory = AudioPlayerManager.audioCacheDir
        Self.maintenanceQueue.async { [weak self] in
            guard let self else { return }
            let size = enforceMusicCacheLimitsBlocking(musicDirectory: musicDirectory, excluding: songIDs)
            publishSizes((image: nil, music: size, lyrics: nil))
        }
    }

    func enforceLyricsCacheLimits() {
        let lyricsDirectory = LyricsCacheStore.cacheDirectory
        Self.maintenanceQueue.async { [weak self] in
            guard let self else { return }
            let size = enforceLyricsCacheLimitsBlocking(lyricsDirectory: lyricsDirectory)
            publishSizes((image: nil, music: nil, lyrics: size))
        }
    }

    func pruneExpiredEntries() {
        let directories = Self.directories
        Self.maintenanceQueue.async { [weak self] in
            guard let self else { return }
            let pruned = pruneExpiredEntriesBlocking(directories: directories)
            DebugLogger.log("Pruned \(pruned) expired cache entries", category: .cache)
            publishSizes(computeSizesBlocking(directories: directories))
        }
    }

    func recordAccess(for url: URL) {
        AudioCacheStore.touch(url)
    }

    func totalImageCacheSize() -> UInt64 {
        imageCacheSize
    }

    func totalMusicCacheSize() -> UInt64 {
        musicCacheSize
    }

    func totalLyricsCacheSize() -> UInt64 {
        lyricsCacheSize
    }

    func clearImageCache() {
        SDImageCache.shared.clearMemory()
        SDImageCache.shared.clearDisk(onCompletion: nil)
        let dir = Self.imageCacheDirectory
        removeAllFiles(in: dir)
        FallbackArtProvider.shared.resetBindings()
        imageCacheSize = 0
        DebugLogger.log("Image cache cleared", category: .cache)
    }

    func clearMusicCache() {
        let dir = AudioPlayerManager.audioCacheDir
        removeAllFiles(in: dir)
        musicCacheSize = 0
        DebugLogger.log("Music cache cleared", category: .cache)
    }

    func clearLyricsCache() {
        LyricsCacheStore.clear()
        lyricsCacheSize = 0
        DebugLogger.log("Lyrics cache cleared", category: .cache)
    }

    func formattedImageCacheSize() -> String {
        formatBytes(imageCacheSize)
    }

    func formattedMusicCacheSize() -> String {
        formatBytes(musicCacheSize)
    }

    func formattedLyricsCacheSize() -> String {
        formatBytes(lyricsCacheSize)
    }

    private static var imageCacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.hackemist.SDImageCache/default", isDirectory: true)
    }

    // MARK: - Maintenance cores (run on maintenanceQueue, never the main actor)

    private nonisolated func publishSizes(
        _ sizes: (image: UInt64?, music: UInt64?, lyrics: UInt64?)
    ) {
        if let image = sizes.image, let music = sizes.music, let lyrics = sizes.lyrics {
            DebugLogger.log(
                "Cache sizes — images: \(formatBytes(image)), music: \(formatBytes(music)), lyrics: \(formatBytes(lyrics))",
                category: .cache
            )
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let image = sizes.image { imageCacheSize = image }
            if let music = sizes.music { musicCacheSize = music }
            if let lyrics = sizes.lyrics { lyricsCacheSize = lyrics }
        }
    }

    private nonisolated func computeSizesBlocking(
        directories: (image: URL, music: URL, lyrics: URL)
    ) -> (image: UInt64?, music: UInt64?, lyrics: UInt64?) {
        (
            image: UInt64(SDImageCache.shared.totalDiskSize()),
            music: directorySize(at: directories.music),
            lyrics: directorySize(at: directories.lyrics)
        )
    }

    private nonisolated func enforceImageCacheLimitsBlocking(imageDirectory: URL) -> UInt64 {
        let sdCache = SDImageCache.shared
        let diskSize = UInt64(sdCache.totalDiskSize())

        if diskSize > Self.imageCacheLimit {
            DebugLogger.log(
                "Image cache \(formatBytes(diskSize)) exceeds limit \(formatBytes(Self.imageCacheLimit)), clearing oldest",
                category: .cache
            )
            sdCache.deleteOldFiles(completionBlock: nil)
        }

        evictOldestFiles(in: imageDirectory, limit: Self.imageCacheLimit, label: "image")
        return UInt64(sdCache.totalDiskSize())
    }

    private nonisolated func enforceMusicCacheLimitsBlocking(
        musicDirectory: URL,
        excluding protectedIDs: Set<String>
    ) -> UInt64 {
        evictOldestSongDirectories(in: musicDirectory, limit: Self.musicCacheLimit, excluding: protectedIDs)
        return directorySize(at: musicDirectory)
    }

    private nonisolated func enforceLyricsCacheLimitsBlocking(lyricsDirectory: URL) -> UInt64 {
        evictOldestFiles(in: lyricsDirectory, limit: Self.lyricsCacheLimit, label: "lyrics")
        return directorySize(at: lyricsDirectory)
    }

    private nonisolated func pruneExpiredEntriesBlocking(
        directories: (image: URL, music: URL, lyrics: URL)
    ) -> Int {
        let cutoff = Date().addingTimeInterval(-Self.maxCacheAge)
        DebugLogger.log("Pruning cache entries older than \(cutoff)", category: .cache)

        var prunedCount = 0
        prunedCount += pruneOldSongDirectories(in: directories.music, olderThan: cutoff)
        prunedCount += pruneOldFiles(in: directories.lyrics, olderThan: cutoff)
        SDImageCache.shared.deleteOldFiles(completionBlock: nil)
        return prunedCount
    }

    // MARK: - File helpers

    private nonisolated func directorySize(at url: URL) -> UInt64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
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

    private nonisolated func evictOldestFiles(in directory: URL, limit: UInt64, label: String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return }

        var currentSize = directorySize(at: directory)
        guard currentSize > limit else { return }

        DebugLogger.log(
            "\(label) cache \(formatBytes(currentSize)) > limit \(formatBytes(limit)), evicting oldest",
            category: .cache
        )

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
            category: .cache
        )
    }

    private nonisolated func evictOldestSongDirectories(
        in directory: URL,
        limit: UInt64,
        excluding protectedIDs: Set<String> = []
    ) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return }

        var currentSize = directorySize(at: directory)
        guard currentSize > limit else { return }

        DebugLogger.log(
            "music cache \(formatBytes(currentSize)) > limit \(formatBytes(limit)), evicting oldest song folders",
            category: .cache
        )

        for folder in songDirectoriesOrderedByDate(in: directory) {
            guard currentSize > limit else { break }
            if protectedIDs.contains(folder.lastPathComponent) { continue }
            let size = directorySize(at: folder)
            try? fm.removeItem(at: folder)
            currentSize = currentSize > size ? currentSize - size : 0
            DebugLogger.log("Evicted song cache: \(folder.lastPathComponent) (\(formatBytes(size)))", category: .cache)
        }
    }

    private nonisolated func pruneOldFiles(in directory: URL, olderThan cutoff: Date) -> Int {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return 0 }
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        else { return 0 }

        var count = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(
                forKeys: [.contentModificationDateKey, .isRegularFileKey]
            ),
                values.isRegularFile == true,
                let modified = values.contentModificationDate,
                modified < cutoff
            else { continue }
            try? fm.removeItem(at: fileURL)
            count += 1
        }
        return count
    }

    private nonisolated func pruneOldSongDirectories(
        in directory: URL,
        olderThan cutoff: Date,
        excluding protectedIDs: Set<String> = []
    ) -> Int {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return 0 }
        guard
            let entries = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return 0
        }

        var count = 0
        for folder in entries {
            if protectedIDs.contains(folder.lastPathComponent) { continue }
            guard let values = try? folder.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey]),
                  values.isDirectory == true,
                  let modified = values.contentModificationDate,
                  modified < cutoff
            else {
                continue
            }
            try? fm.removeItem(at: folder)
            count += 1
        }
        return count
    }

    private nonisolated func filesOrderedByDate(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        else { return [] }

        var files: [(url: URL, date: Date)] = []
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(
                forKeys: [.contentModificationDateKey, .isRegularFileKey]
            ),
                values.isRegularFile == true,
                let modified = values.contentModificationDate
            else { continue }
            files.append((url: fileURL, date: modified))
        }
        return files.sorted { $0.date < $1.date }.map(\.url)
    }

    private nonisolated func fileSize(at url: URL) -> UInt64 {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize
        else { return 0 }
        return UInt64(size)
    }

    private nonisolated func songDirectoriesOrderedByDate(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard
            let entries = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        return entries
            .compactMap { url -> (URL, Date)? in
                guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey]),
                      values.isDirectory == true,
                      let modified = values.contentModificationDate
                else {
                    return nil
                }
                return (url, modified)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    private func removeAllFiles(in directory: URL) {
        guard let entries = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return }
        for entry in entries {
            try? fm.removeItem(at: entry)
        }
    }

    private nonisolated func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
