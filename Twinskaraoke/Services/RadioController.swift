import Combine
import Foundation

@MainActor
final class RadioController: ObservableObject {
  static let shared = RadioController()
  static let metadataURL = URL(
    string: "https://radio.twinskaraoke.com/api/nowplaying_static/neuro_21.json")!
  static let stationID = "neuro_21"
  @Published var nowPlaying: RadioNowPlaying?
  @Published var isRefreshing = false
  @Published var refreshErrorMessage: String?
  @Published var lastUpdated: Date?
  private var pollTimer: Timer?
  private var refreshTask: Task<Void, Never>?
  private var lastMetadataSignature: String?
  private init() {}
  func start() {
    if AppRuntime.isUITestMode {
      pollTimer?.invalidate()
      pollTimer = nil
      refreshTask?.cancel()
      refreshTask = nil
      applyUITestFixture()
      return
    }

    scheduleRefresh()
    pollTimer?.invalidate()
    let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.scheduleRefresh()
      }
    }
    pollTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }
  func stop() {
    pollTimer?.invalidate()
    pollTimer = nil
    refreshTask?.cancel()
    refreshTask = nil
  }
  func playLiveStream(retry: Int = 0) {
    guard let np = nowPlaying else {
      guard retry < 1 else { return }
      Task {
        await refresh()
        await MainActor.run { self.playLiveStream(retry: retry + 1) }
      }
      return
    }
    guard let streamURL = URL(string: np.station.listenUrl) else { return }
    let info = np.nowPlaying?.song
    let song =
      (info
      ?? RadioNowPlaying.SongInfo(
        id: Self.stationID, art: nil, text: np.station.name,
        artist: np.station.description, title: np.station.name,
        customFields: nil
      )).toSong(stationID: Self.stationID)
    let artURL = info?.art.flatMap { URL(string: $0) }
    AudioPlayerManager.shared.playRadio(streamURL: streamURL, song: song, artworkURL: artURL)
  }
  private func scheduleRefresh() {
    guard refreshTask == nil else { return }
    refreshTask = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.refresh()
      self.refreshTask = nil
    }
  }
  func refresh() async {
    if AppRuntime.isUITestMode {
      applyUITestFixture()
      return
    }

    guard !isRefreshing else { return }
    isRefreshing = true
    defer { isRefreshing = false }

    let maxRetries = 3
    var lastError: Error?

    for attempt in 0..<maxRetries {
      do {
        let (data, _) = try await URLSession.shared.data(from: Self.metadataURL)
        let np = try JSONDecoder().decode(RadioNowPlaying.self, from: data)
        nowPlaying = np
        refreshErrorMessage = nil
        lastUpdated = Date()
        if AudioPlayerManager.shared.isRadioMode, let info = np.nowPlaying?.song {
          let signature = metadataSignature(for: info)
          if signature != lastMetadataSignature {
            lastMetadataSignature = signature
            let song = info.toSong(stationID: Self.stationID)
            let art = info.art.flatMap { URL(string: $0) }
            AudioPlayerManager.shared.updateRadioMetadata(song: song, artworkURL: art)
          }
        }
        return
      } catch {
        guard !Task.isCancelled else { return }
        lastError = error
        if attempt < maxRetries - 1 {
          let delay = Double(1 << attempt)
          try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
      }
    }

    refreshErrorMessage =
      nowPlaying == nil
      ? "Radio metadata is temporarily unavailable."
      : "Couldn't refresh radio metadata."
  }

  private func metadataSignature(for info: RadioNowPlaying.SongInfo) -> String {
    [
      info.resolvedSongID ?? info.id,
      info.title ?? info.text ?? "",
      info.artist ?? "",
      info.art ?? ""
    ].joined(separator: "|")
  }

  private func applyUITestFixture() {
    nowPlaying = Self.uiTestNowPlaying
    refreshErrorMessage = nil
    isRefreshing = false
    lastUpdated = Date()
    if let info = nowPlaying?.nowPlaying?.song {
      lastMetadataSignature = metadataSignature(for: info)
    }
  }

  private static var uiTestNowPlaying: RadioNowPlaying {
    RadioNowPlaying(
      station: RadioNowPlaying.Station(
        name: "Twinskaraoke Radio",
        description: "Neuro 21 live from the karaoke room",
        listenUrl: "https://radio.twinskaraoke.com/listen/neuro_21/radio.mp3"
      ),
      listeners: RadioNowPlaying.Listeners(total: 42, unique: 24),
      nowPlaying: RadioNowPlaying.NowPlayingItem(
        song: RadioNowPlaying.SongInfo(
          id: "ui-radio-song-1",
          art: nil,
          text: "Wake Me Up Before You Go-Go - Wham!",
          artist: "Wham!",
          title: "Wake Me Up Before You Go-Go",
          customFields: RadioNowPlaying.CustomFields(songID: "ui-radio-song-1")
        )
      ),
      playingNext: RadioNowPlaying.NowPlayingItem(
        song: RadioNowPlaying.SongInfo(
          id: "ui-radio-song-2",
          art: nil,
          text: "Hero - Mili",
          artist: "Mili",
          title: "Hero",
          customFields: RadioNowPlaying.CustomFields(songID: "ui-radio-song-2")
        )
      ),
      songHistory: [
        RadioNowPlaying.HistoryItem(
          song: RadioNowPlaying.SongInfo(
            id: "ui-radio-song-3",
            art: nil,
            text: "Cure For Me - AURORA",
            artist: "AURORA",
            title: "Cure For Me",
            customFields: RadioNowPlaying.CustomFields(songID: "ui-radio-song-3")
          )
        ),
        RadioNowPlaying.HistoryItem(
          song: RadioNowPlaying.SongInfo(
            id: "ui-radio-song-4",
            art: nil,
            text: "Bad Apple!! - Nomico",
            artist: "Nomico",
            title: "Bad Apple!!",
            customFields: RadioNowPlaying.CustomFields(songID: "ui-radio-song-4")
          )
        ),
      ]
    )
  }
}
