import Combine
import Foundation

enum LyricsTranslationState: Equatable {
  case idle
  case translating
  case ready
  case unavailable
  case failed
}

final class LyricsViewModel: ObservableObject {
  @Published private(set) var lyrics: [LyricLine] = []
  @Published private(set) var isLoading = false
  @Published private(set) var didFail = false
  @Published private(set) var hasNoLyrics = false
  @Published private(set) var translationState: LyricsTranslationState = .idle

  private(set) var loadedSongID: String?
  private var inFlightSongID: String?
  private var currentTask: URLSessionDataTask?
  private var translationTask: Task<Void, Never>?

  var hasTranslatedLyrics: Bool {
    lyrics.contains { ($0.translatedText?.isEmpty == false) && $0.translatedText != $0.text }
  }

  func adopt(songID: String, lyrics: [LyricLine]) {
    cancelInFlight()
    inFlightSongID = nil
    loadedSongID = songID
    self.lyrics = lyrics
    isLoading = false
    didFail = false
    hasNoLyrics = lyrics.isEmpty
    refreshTranslationState(for: lyrics)
  }

  func fetch(songID: String) {
    if songID == loadedSongID, !lyrics.isEmpty { return }
    if songID == loadedSongID, hasNoLyrics { return }
    if songID == inFlightSongID, isLoading { return }

    cancelInFlight()
    inFlightSongID = songID

    if let cachedTranslated = LyricsCacheStore.load(songID: songID, variant: .translated) {
      loadedSongID = songID
      lyrics = cachedTranslated
      isLoading = false
      didFail = false
      hasNoLyrics = cachedTranslated.isEmpty
      translationState = cachedTranslated.isEmpty ? .idle : .ready
      return
    }

    if let cachedOriginal = LyricsCacheStore.load(songID: songID, variant: .original) {
      loadedSongID = songID
      lyrics = cachedOriginal
      isLoading = false
      didFail = false
      hasNoLyrics = cachedOriginal.isEmpty
      refreshTranslationState(for: cachedOriginal)
      return
    }

    if loadedSongID != songID {
      lyrics = []
      loadedSongID = nil
      hasNoLyrics = false
      translationState = .idle
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
    translationState = .idle
    fetch(songID: id)
  }

  func requestTranslation() {
    guard let songID = loadedSongID, !lyrics.isEmpty, !hasNoLyrics else { return }
    if hasTranslatedLyrics {
      translationState = .ready
      return
    }
    if let cached = LyricsCacheStore.load(songID: songID, variant: .translated) {
      lyrics = mergeTranslations(from: cached, into: lyrics)
      translationState = .ready
      return
    }
    guard LyricsTranslationService.shared.isConfigured else {
      translationState = .unavailable
      return
    }

    translationTask?.cancel()
    translationState = .translating
    let sourceLyrics = lyrics
    translationTask = Task { [weak self] in
      do {
        let translated = try await LyricsTranslationService.shared.translate(
          songID: songID,
          lyrics: sourceLyrics
        )
        await MainActor.run {
          guard let self, self.loadedSongID == songID else { return }
          self.lyrics = translated
          self.translationState = .ready
          LyricsCacheStore.save(translated, songID: songID, variant: .translated)
        }
      } catch is CancellationError {
        return
      } catch LyricsTranslationError.unavailable {
        await MainActor.run {
          guard let self, self.loadedSongID == songID else { return }
          self.translationState = .unavailable
        }
      } catch {
        await MainActor.run {
          guard let self, self.loadedSongID == songID else { return }
          self.translationState = .failed
        }
      }
    }
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
      refreshTranslationState(for: parsed)
      LyricsCacheStore.save(parsed, songID: songID, variant: .original)
    case .empty:
      loadedSongID = songID
      lyrics = []
      didFail = false
      hasNoLyrics = true
      translationState = .idle
      LyricsCacheStore.save([], songID: songID, variant: .original)
    case .failure:
      lyrics = []
      didFail = true
      hasNoLyrics = false
      translationState = .idle
    }
  }

  private func refreshTranslationState(for lyrics: [LyricLine]) {
    let hasTranslations = lyrics.contains {
      ($0.translatedText?.isEmpty == false) && $0.translatedText != $0.text
    }
    if hasTranslations {
      translationState = .ready
    } else {
      translationState = LyricsTranslationService.shared.isConfigured ? .idle : .unavailable
    }
  }

  private func mergeTranslations(from translated: [LyricLine], into original: [LyricLine]) -> [LyricLine] {
    guard translated.count == original.count else { return original }
    return zip(original, translated).map { source, translatedLine in
      source.withTranslation(translatedLine.translatedText ?? translatedLine.text)
    }
  }

  private func cancelInFlight() {
    currentTask?.cancel()
    currentTask = nil
    translationTask?.cancel()
    translationTask = nil
  }
}
