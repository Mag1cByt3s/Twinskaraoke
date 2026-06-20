import Combine
import Foundation

final class HomeViewModel: ObservableObject {
  private enum TopPicksSource {
    case publicPlaylists
    case setlists
  }

  @Published var trending: [Song] = []
  @Published var suggestions: [Song] = []
  @Published var recentPlaylists: [Playlist] = []
  @Published var newReleases: [Song] = []
  @Published var isLoading = false
  @Published var isLoadingMoreTopPicks = false
  @Published var canLoadMoreTopPicks = true
  @Published var latestSingle: Song?
  @Published var latestSingleContext: [Song] = []
  private var hasLoaded = false
  private var topPicksPage = 0
  private let topPicksPageSize = 12
  private var topPicksSource: TopPicksSource = .setlists

  init() {
    fetchHomeData()
  }

  func fetchHomeData(force: Bool = false) {
    if AppRuntime.isUITestMode {
      applyUITestFixture()
      return
    }

    if hasLoaded && !force { return }
    hasLoaded = true
    isLoading = true
    topPicksPage = 0
    canLoadMoreTopPicks = true
    let group = DispatchGroup()
    group.enter()
    Task { [weak self] in
      let response = try? await KaraokeAPIClient.trendingSongs(take: 20)
      await MainActor.run {
        if let response { self?.trending = response }
        group.leave()
      }
    }
    group.enter()
    Task { [weak self] in
      let response = try? await KaraokeAPIClient.songSuggestions(take: 20)
      await MainActor.run {
        if let response { self?.suggestions = response }
        group.leave()
      }
    }
    group.enter()
    fetchTopPicks(startIndex: 0) { [weak self] response in
      DispatchQueue.main.async {
        if let response {
          self?.recentPlaylists = response
          self?.topPicksPage = 1
          self?.canLoadMoreTopPicks = response.count == (self?.topPicksPageSize ?? 0)
        }
        group.leave()
      }
    }
    group.enter()
    Task { [weak self] in
      let songs = (try? await KaraokeAPIClient.latestReleases()) ?? []
      await MainActor.run {
        guard let self else {
          group.leave()
          return
        }
        self.newReleases = songs
        self.latestSingle = songs.first
        self.latestSingleContext = songs
        group.leave()
      }
    }
    group.notify(queue: .main) { [weak self] in self?.isLoading = false }
  }
  func loadMoreTopPicksIfNeeded(current: Playlist) {
    guard let idx = recentPlaylists.firstIndex(where: { $0.id == current.id }) else { return }
    if idx >= recentPlaylists.count - 3 && !isLoadingMoreTopPicks && canLoadMoreTopPicks {
      loadMoreTopPicks()
    }
  }

  func topPicksURLForList(startIndex: Int, pageSize: Int) -> String {
    switch topPicksSource {
    case .setlists:
      return "\(StorageHost.api)/api/playlists?startIndex=\(startIndex)&pageSize=\(pageSize)&search=&sortBy=&sortDescending=True&isSetlist=True&year=0"
    case .publicPlaylists:
      return "\(StorageHost.api)/api/playlist/public?startIndex=\(startIndex)&pageSize=\(pageSize)&search=&sortBy=UpdatedAt&sortDescending=True"
    }
  }
  private func loadMoreTopPicks() {
    isLoadingMoreTopPicks = true
    let startIndex = topPicksPage * topPicksPageSize
    let source = topPicksSource
    let pageSize = topPicksPageSize
    Task { [weak self] in
      let playlists: [Playlist]
      switch source {
      case .setlists:
        playlists =
          (try? await KaraokeAPIClient.playlists(
            startIndex: startIndex,
            pageSize: pageSize,
            isSetlist: true,
            sortDescending: true
          )) ?? []
      case .publicPlaylists:
        playlists =
          (try? await KaraokeAPIClient.publicPlaylists(
            startIndex: startIndex,
            pageSize: pageSize
          )) ?? []
      }
      await MainActor.run {
        guard let self else { return }
        if !playlists.isEmpty {
          let existing = Set(self.recentPlaylists.map { $0.id })
          self.recentPlaylists += playlists.filter { !existing.contains($0.id) }
          self.topPicksPage += 1
          self.canLoadMoreTopPicks = playlists.count == self.topPicksPageSize
        } else {
          self.canLoadMoreTopPicks = false
        }
        self.isLoadingMoreTopPicks = false
      }
    }
  }

  private func fetchTopPicks(startIndex: Int, completion: @escaping ([Playlist]?) -> Void) {
    let pageSize = topPicksPageSize
    Task { [weak self] in
      let setlists =
        (try? await KaraokeAPIClient.playlists(
          startIndex: startIndex,
          pageSize: pageSize,
          isSetlist: true,
          sortDescending: true
        )) ?? []
      if !setlists.isEmpty {
        await MainActor.run {
          self?.topPicksSource = .setlists
          completion(setlists)
        }
        return
      }

      let fallback =
        try? await KaraokeAPIClient.publicPlaylists(
          startIndex: startIndex,
          pageSize: pageSize
        )
      await MainActor.run {
        self?.topPicksSource = .publicPlaylists
        completion(fallback)
      }
    }
  }

  private func applyUITestFixture() {
    hasLoaded = true
    isLoading = false
    isLoadingMoreTopPicks = false
    canLoadMoreTopPicks = false
    topPicksSource = .setlists

    let fixtureSongs = Self.fixtureSongs
    trending = Array(fixtureSongs.suffix(4))
    suggestions = Array(fixtureSongs.prefix(4))
    newReleases = fixtureSongs
    latestSingle = fixtureSongs.first
    latestSingleContext = fixtureSongs
    recentPlaylists = [
      UITestFixtures.playlist(
        id: "ui-home-playlist-essentials",
        name: "Karaoke Essentials",
        songs: Array(fixtureSongs.prefix(4))
      ),
      UITestFixtures.playlist(
        id: "ui-home-playlist-pop",
        name: "Pop Covers",
        songs: Array(fixtureSongs.dropFirst(2).prefix(4))
      ),
      UITestFixtures.playlist(
        id: "ui-home-playlist-night",
        name: "Late Night Singalong",
        songs: Array(fixtureSongs.suffix(4))
      ),
    ]
  }

  private static var fixtureSongs: [Song] {
    [
      UITestFixtures.song(
        id: "ui-home-song-1",
        title: "Wake Me Up Before You Go-Go",
        originalArtists: ["Wham!"],
        coverArtists: ["Neuro"]
      ),
      UITestFixtures.song(
        id: "ui-home-song-2",
        title: "Hero",
        originalArtists: ["Mili"],
        coverArtists: ["Neuro"]
      ),
      UITestFixtures.song(
        id: "ui-home-song-3",
        title: "Cure For Me",
        originalArtists: ["AURORA"],
        coverArtists: ["Neuro"]
      ),
      UITestFixtures.song(
        id: "ui-home-song-4",
        title: "Be My Star",
        originalArtists: ["LEVEL NINE"],
        coverArtists: ["Neuro"]
      ),
      UITestFixtures.song(
        id: "ui-home-song-5",
        title: "Young and Beautiful",
        originalArtists: ["Lana Del Rey"],
        coverArtists: ["Neuro"]
      ),
      UITestFixtures.song(
        id: "ui-home-song-6",
        title: "Send Me an Angel",
        originalArtists: ["Scorpions"],
        coverArtists: ["Neuro"]
      ),
    ]
  }
}
