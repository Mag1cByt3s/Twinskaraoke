import Combine
import Foundation

final class LyricsViewModel: ObservableObject {
  @Published private(set) var lyrics: [LyricLine] = []
  @Published private(set) var isLoading = false
  @Published private(set) var didFail = false
  @Published private(set) var hasNoLyrics = false
  private(set) var loadedSongID: String?
  private var inFlightSongID: String?
  private var currentTask: URLSessionDataTask?
  func adopt(songID: String, lyrics: [LyricLine]) {
    cancelInFlight()
    inFlightSongID = nil
    loadedSongID = songID
    self.lyrics = lyrics
    isLoading = false
    didFail = false
    hasNoLyrics = lyrics.isEmpty
  }
  func fetch(songID: String) {
    if songID == loadedSongID, !lyrics.isEmpty { return }
    if songID == loadedSongID, hasNoLyrics { return }
    if songID == inFlightSongID, isLoading { return }
    cancelInFlight()
    inFlightSongID = songID
    if loadedSongID != songID {
      lyrics = []
      loadedSongID = nil
      hasNoLyrics = false
    }
    isLoading = true
    didFail = false
    let encoded =
      songID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? songID
    guard let url = URL(string: "\(StorageHost.api)/api/songs/\(encoded)/lyrics") else {
      finish(songID: songID, result: .failure)
      return
    }
    var request = URLRequest(url: url)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.timeoutInterval = 15
    GuestIdentity.applyIfNeeded(to: &request)
    let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      DispatchQueue.main.async {
        guard let self else { return }
        if let nsError = error as NSError?, nsError.code == NSURLErrorCancelled { return }
        guard self.inFlightSongID == songID else { return }
        if error != nil {
          self.finish(songID: songID, result: .failure)
          return
        }
        guard let http = response as? HTTPURLResponse else {
          self.finish(songID: songID, result: .failure)
          return
        }
        if http.statusCode == 404 {
          self.finish(songID: songID, result: .empty)
          return
        }
        guard (200..<300).contains(http.statusCode), let data else {
          self.finish(songID: songID, result: .failure)
          return
        }
        guard let raw = try? JSONDecoder().decode([RawLyricLine].self, from: data) else {
          self.finish(songID: songID, result: .failure)
          return
        }
        let parsed = raw.compactMap { line -> LyricLine? in
          guard let time = TimeSpanParser.parse(line.time) else { return nil }
          return LyricLine(time: time, text: line.text)
        }
        self.finish(songID: songID, result: parsed.isEmpty ? .empty : .success(parsed))
      }
    }
    currentTask = task
    task.resume()
  }
  func retry() {
    guard let id = inFlightSongID ?? loadedSongID else { return }
    loadedSongID = nil
    didFail = false
    hasNoLyrics = false
    lyrics = []
    fetch(songID: id)
  }

  private enum FetchResult {
    case success([LyricLine])
    case empty
    case failure
  }
  private func finish(songID: String, result: FetchResult) {
    inFlightSongID = nil
    currentTask = nil
    isLoading = false
    switch result {
    case .success(let parsed):
      loadedSongID = songID
      lyrics = parsed
      didFail = false
      hasNoLyrics = false
    case .empty:
      loadedSongID = songID
      lyrics = []
      didFail = false
      hasNoLyrics = true
    case .failure:
      lyrics = []
      didFail = true
      hasNoLyrics = false
    }
  }
  private func cancelInFlight() {
    currentTask?.cancel()
    currentTask = nil
  }
}
