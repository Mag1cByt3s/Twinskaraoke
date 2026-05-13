import Combine
import Foundation
import SwiftUI

@MainActor
final class DownloadManager: ObservableObject {
  static let shared = DownloadManager()
  @Published private(set) var downloadedIDs: Set<String> = []
  @Published private(set) var inProgress: Set<String> = []
  @Published private(set) var progress: [String: Double] = [:]
  private let cacheDir: URL
  private var tasks: [String: URLSessionDownloadTask] = [:]
  private init() {
    cacheDir = FileManager.default
      .urls(for: .documentDirectory, in: .userDomainMask).first!
      .appendingPathComponent("Downloads")
    try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    refreshExistingDownloads()
    DebugLogger.log(
      "DownloadManager init — \(downloadedIDs.count) existing downloads",
      category: .network)
  }
  func localURL(for songID: String) -> URL {
    cacheDir.appendingPathComponent("\(songID).mp3")
  }
  func isDownloaded(_ songID: String) -> Bool {
    downloadedIDs.contains(songID)
  }
  func isDownloading(_ songID: String) -> Bool {
    inProgress.contains(songID)
  }
  func download(song: Song) {
    guard !isDownloaded(song.id), !isDownloading(song.id) else { return }
    guard let remote = song.audioURL else { return }
    DebugLogger.log("Starting download: \(song.id)", category: .network)
    inProgress.insert(song.id)
    progress[song.id] = 0
    let dest = localURL(for: song.id)
    let songID = song.id
    let task = URLSession.shared.downloadTask(with: remote) { [weak self] tempURL, _, error in
      var moved = false
      if let tempURL, error == nil {
        try? FileManager.default.removeItem(at: dest)
        do {
          try FileManager.default.moveItem(at: tempURL, to: dest)
          moved = true
        } catch {}
      }
      Task { @MainActor in
        guard let self else { return }
        self.tasks.removeValue(forKey: songID)
        self.inProgress.remove(songID)
        self.progress.removeValue(forKey: songID)
        if moved {
          self.downloadedIDs.insert(songID)
          DebugLogger.log("Download completed: \(songID)", category: .network)
        } else {
          DebugLogger.log("Download failed: \(songID)", category: .network)
        }
      }
    }
    tasks[song.id] = task
    task.resume()
  }
  func cancel(songID: String) {
    tasks[songID]?.cancel()
    tasks.removeValue(forKey: songID)
    inProgress.remove(songID)
    progress.removeValue(forKey: songID)
  }
  func remove(songID: String) {
    let url = localURL(for: songID)
    try? FileManager.default.removeItem(at: url)
    downloadedIDs.remove(songID)
    DebugLogger.log("Download removed: \(songID)", category: .network)
  }
  func removeAll() {
    let fm = FileManager.default
    if let files = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) {
      for f in files { try? fm.removeItem(at: f) }
    }
    downloadedIDs = []
    DebugLogger.log("All downloads removed", category: .network)
  }
  private func refreshExistingDownloads() {
    let fm = FileManager.default
    guard let files = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)
    else { return }
    let ids = files.map { $0.deletingPathExtension().lastPathComponent }
    downloadedIDs = Set(ids)
  }
}
