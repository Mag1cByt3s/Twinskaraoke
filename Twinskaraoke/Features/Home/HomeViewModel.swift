import Combine
import Foundation

class HomeViewModel: ObservableObject {
  @Published var trending: [Song] = []
  @Published var suggestions: [Song] = []
  @Published var recentPlaylists: [Playlist] = []
  @Published var isLoading = false
  @Published var isLoadingMoreTopPicks = false
  @Published var canLoadMoreTopPicks = true
  @Published var latestSingle: Song?
  @Published var latestSingleContext: [Song] = []
  private var hasLoaded = false
  private var topPicksPage = 0
  private let topPicksPageSize = 12
  private var loadedSinglePlaylistID: String?
  func fetchHomeData(force: Bool = false) {
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
    fetchData(urlString: topPicksURL(startIndex: 0)) { [weak self] (response: [Playlist]?) in
      DispatchQueue.main.async {
        if let response {
          self?.recentPlaylists = response
          self?.topPicksPage = 1
          self?.canLoadMoreTopPicks = response.count == (self?.topPicksPageSize ?? 0)
          if let first = response.first { self?.loadLatestSingle(from: first) }
        }
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
  private func loadMoreTopPicks() {
    isLoadingMoreTopPicks = true
    let startIndex = topPicksPage * topPicksPageSize
    fetchData(urlString: topPicksURL(startIndex: startIndex)) { [weak self] (response: [Playlist]?) in
      DispatchQueue.main.async {
        guard let self = self else { return }
        if let response, !response.isEmpty {
          let existing = Set(self.recentPlaylists.map { $0.id })
          self.recentPlaylists += response.filter { !existing.contains($0.id) }
          self.topPicksPage += 1
          self.canLoadMoreTopPicks = response.count == self.topPicksPageSize
        } else {
          self.canLoadMoreTopPicks = false
        }
        self.isLoadingMoreTopPicks = false
      }
    }
  }
  private func topPicksURL(startIndex: Int) -> String {
    "\(StorageHost.api)/api/playlists?startIndex=\(startIndex)&pageSize=\(topPicksPageSize)&search=&sortBy=&sortDescending=True&isSetlist=True&year=0"
  }
  private func loadLatestSingle(from playlist: Playlist) {
    if loadedSinglePlaylistID == playlist.id, latestSingle != nil { return }
    loadedSinglePlaylistID = playlist.id
    if let inline = playlist.songListDTOs, let first = inline.first {
      self.latestSingle = first
      self.latestSingleContext = inline
      return
    }
    guard let url = URL(string: "\(StorageHost.api)/api/playlist/\(playlist.id)") else { return }
    var request = URLRequest(url: url)
    if let token = UserDefaults.standard.string(forKey: "nk.token") {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    GuestIdentity.applyIfNeeded(to: &request)
    URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
      guard let data,
        let decoded = try? JSONDecoder().decode(Playlist.self, from: data),
        let songs = decoded.songListDTOs, let first = songs.first
      else { return }
      DispatchQueue.main.async {
        self?.latestSingle = first
        self?.latestSingleContext = songs
      }
    }.resume()
  }
  private func fetchData<T: Codable>(urlString: String, completion: @escaping (T?) -> Void) {
    guard let url = URL(string: urlString) else {
      completion(nil)
      return
    }
    var request = URLRequest(url: url)
    if let token = UserDefaults.standard.string(forKey: "nk.token") {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    GuestIdentity.applyIfNeeded(to: &request)
    URLSession.shared.dataTask(with: request) { data, _, _ in
      if let data, let decoded = try? JSONDecoder().decode(T.self, from: data) {
        completion(decoded)
      } else {
        completion(nil)
      }
    }.resume()
  }
}
