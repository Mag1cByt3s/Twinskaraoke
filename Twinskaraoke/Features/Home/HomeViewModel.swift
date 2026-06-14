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
    if ProcessInfo.processInfo.arguments.contains("-UITestMode") {
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
    fetchData(urlString: "\(StorageHost.api)/api/explore/trendings?days=7&take=20") {
      [weak self] (response: [Song]?) in
      if let response { DispatchQueue.main.async { self?.trending = response } }
      group.leave()
    }
    group.enter()
    fetchData(urlString: "\(StorageHost.api)/api/user/suggestions?take=20") {
      [weak self] (response: [Song]?) in
      if let response { DispatchQueue.main.async { self?.suggestions = response } }
      group.leave()
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
    fetchLatestReleases { [weak self] songs in
      DispatchQueue.main.async {
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
    fetchData(urlString: topPicksURL(startIndex: startIndex, source: topPicksSource)) {
      [weak self] (response: [PlaylistListItem]?) in
      DispatchQueue.main.async {
        guard let self = self else { return }
        let playlists = response?.map { $0.asPlaylist() } ?? []
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
    fetchData(urlString: topPicksURL(startIndex: startIndex, source: .setlists)) {
      [weak self] (response: LossyArray<PlaylistListItem>?) in
      let playlists = response?.elements.map { $0.asPlaylist() } ?? []
      if !playlists.isEmpty {
        self?.topPicksSource = .setlists
        completion(playlists)
      } else {
        self?.topPicksSource = .publicPlaylists
        self?.fetchData(
          urlString: self?.topPicksURL(startIndex: startIndex, source: .publicPlaylists) ?? ""
        ) { (fallback: LossyArray<PlaylistListItem>?) in
          completion(fallback?.elements.map { $0.asPlaylist() })
        }
      }
    }
  }

  private func topPicksURL(startIndex: Int, source: TopPicksSource) -> String {
    switch source {
    case .publicPlaylists:
      return "\(StorageHost.api)/api/playlist/public?startIndex=\(startIndex)&pageSize=\(topPicksPageSize)&search=&sortBy=UpdatedAt&sortDescending=True"
    case .setlists:
      return "\(StorageHost.api)/api/playlists?startIndex=\(startIndex)&pageSize=\(topPicksPageSize)&search=&sortBy=&sortDescending=True&isSetlist=True&year=0"
    }
  }

  private func fetchLatestReleases(completion: @escaping ([Song]) -> Void) {
    guard let url = URL(string: "\(StorageHost.api)/api/songs") else {
      completion([])
      return
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token = UserDefaults.standard.string(forKey: "nk.token") {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    GuestIdentity.applyIfNeeded(to: &request)
    request.httpBody = try? JSONSerialization.data(withJSONObject: [
      "page": 1,
      "pageSize": 24,
      "search": "",
    ])

    URLSession.shared.dataTask(with: request) { data, _, _ in
      Task { @MainActor in
        guard let data,
          let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data)
        else {
          completion([])
          return
        }
        let filtered = decoded.items.filter {
          !$0.title.localizedCaseInsensitiveContains("Temporary Stream Audio")
        }
        let curated = Array((filtered.isEmpty ? decoded.items : filtered).prefix(12))
        completion(curated)
      }
    }.resume()
  }
  private func fetchData<T: Decodable>(urlString: String, completion: @escaping (T?) -> Void) {
    guard let url = URL(string: urlString) else {
      completion(nil)
      return
    }
    var request = URLRequest(url: url)
    if let token = UserDefaults.standard.string(forKey: "nk.token") {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    GuestIdentity.applyIfNeeded(to: &request)
    URLSession.shared.dataTask(with: request) { data, resp, error in
      if let error {
        DebugLogger.log("Home fetch failed: \(urlString) — \(error.localizedDescription)", category: .network)
        completion(nil)
        return
      }
      if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
        DebugLogger.log("Home fetch HTTP \(http.statusCode): \(urlString)", category: .network)
        completion(nil)
        return
      }
      guard let data else {
        completion(nil)
        return
      }
      do {
        let decoded = try JSONDecoder().decode(T.self, from: data)
        completion(decoded)
      } catch {
        DebugLogger.log("Home fetch decode error: \(urlString) — \(error)", category: .network)
        completion(nil)
      }
    }.resume()
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
      fixturePlaylist(
        id: "ui-home-playlist-essentials",
        name: "Karaoke Essentials",
        songs: Array(fixtureSongs.prefix(4))
      ),
      fixturePlaylist(
        id: "ui-home-playlist-pop",
        name: "Pop Covers",
        songs: Array(fixtureSongs.dropFirst(2).prefix(4))
      ),
      fixturePlaylist(
        id: "ui-home-playlist-night",
        name: "Late Night Singalong",
        songs: Array(fixtureSongs.suffix(4))
      ),
    ]
  }

  private static var fixtureSongs: [Song] {
    [
      fixtureSong(
        id: "ui-home-song-1",
        title: "Wake Me Up Before You Go-Go",
        originalArtists: ["Wham!"],
        coverArtists: ["Neuro"]
      ),
      fixtureSong(
        id: "ui-home-song-2",
        title: "Hero",
        originalArtists: ["Mili"],
        coverArtists: ["Neuro"]
      ),
      fixtureSong(
        id: "ui-home-song-3",
        title: "Cure For Me",
        originalArtists: ["AURORA"],
        coverArtists: ["Neuro"]
      ),
      fixtureSong(
        id: "ui-home-song-4",
        title: "Be My Star",
        originalArtists: ["LEVEL NINE"],
        coverArtists: ["Neuro"]
      ),
      fixtureSong(
        id: "ui-home-song-5",
        title: "Young and Beautiful",
        originalArtists: ["Lana Del Rey"],
        coverArtists: ["Neuro"]
      ),
      fixtureSong(
        id: "ui-home-song-6",
        title: "Send Me an Angel",
        originalArtists: ["Scorpions"],
        coverArtists: ["Neuro"]
      ),
    ]
  }

  private static func fixtureSong(
    id: String,
    title: String,
    originalArtists: [String],
    coverArtists: [String]
  ) -> Song {
    Song(
      id: id,
      title: title,
      duration: 210,
      absolutePath: nil,
      cloudflareID: nil,
      coverArt: nil,
      originalArtists: originalArtists,
      coverArtists: coverArtists,
      userUploaded: true
    )
  }

  private func fixturePlaylist(id: String, name: String, songs: [Song]) -> Playlist {
    Playlist(
      id: id,
      name: name,
      songCount: songs.count,
      media: nil,
      mosaicMedia: nil,
      songListDTOs: songs
    )
  }
}
