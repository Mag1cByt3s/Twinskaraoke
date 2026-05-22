import Combine
import Foundation

@MainActor
final class RadioController: ObservableObject {
  static let shared = RadioController()
  static let metadataURL = URL(
    string: "https://radio.twinskaraoke.com/api/nowplaying_static/neuro_21.json")!
  static let stationID = "neuro_21"
  @Published var nowPlaying: RadioNowPlaying?
  private var pollTimer: Timer?
  private var refreshTask: Task<Void, Never>?
  private var lastMetadataSignature: String?
  private init() {}
  func start() {
    scheduleRefresh()
    pollTimer?.invalidate()
    let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
      self?.scheduleRefresh()
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
    guard let (data, _) = try? await URLSession.shared.data(from: Self.metadataURL) else { return }
    guard let np = try? JSONDecoder().decode(RadioNowPlaying.self, from: data) else { return }
    self.nowPlaying = np
    if AudioPlayerManager.shared.isRadioMode, let info = np.nowPlaying?.song {
      let signature = metadataSignature(for: info)
      if signature != lastMetadataSignature {
        lastMetadataSignature = signature
        let song = info.toSong(stationID: Self.stationID)
        let art = info.art.flatMap { URL(string: $0) }
        AudioPlayerManager.shared.updateRadioMetadata(song: song, artworkURL: art)
      }
    }
  }

  private func metadataSignature(for info: RadioNowPlaying.SongInfo) -> String {
    [
      info.resolvedSongID ?? info.id,
      info.title ?? info.text ?? "",
      info.artist ?? "",
      info.art ?? ""
    ].joined(separator: "|")
  }
}
