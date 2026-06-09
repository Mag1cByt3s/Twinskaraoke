import Combine
import Foundation

#if canImport(UIKit)
  import UIKit
#endif

nonisolated struct GenreSummary: Decodable, Identifiable, Sendable {
  let id: String
  let name: String
  let songCount: Int

  enum CodingKeys: String, CodingKey { case id, name, songCount, count }
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    name = try c.decode(String.self, forKey: .name)
    if let v = try c.decodeIfPresent(Int.self, forKey: .songCount) {
      songCount = v
    } else {
      songCount = (try? c.decode(Int.self, forKey: .count)) ?? 0
    }
  }
}

nonisolated private struct GenreDetail: Decodable, Sendable {
  let id: String
  let name: String
  let songs: [Song]?
}

@MainActor
final class PublicPlaylistsViewModel: ObservableObject {
  @Published var playlists: [Playlist] = []
  @Published var isLoadingMore = false
  private var canLoadMore = true
  private var hasLoaded = false
  private let pageSize = 25

  func loadIfNeeded() {
    guard !hasLoaded else { return }
    hasLoaded = true
    fetchPage(startIndex: 0, replace: true)
  }

  func loadMoreIfNeeded(current: Playlist) {
    guard let idx = playlists.firstIndex(where: { $0.id == current.id }) else { return }
    if idx >= playlists.count - 4 && !isLoadingMore && canLoadMore {
      fetchPage(startIndex: playlists.count, replace: false)
    }
  }

  func urlForList(startIndex: Int, pageSize: Int) -> String {
    "\(StorageHost.api)/api/playlist/public?startIndex=\(startIndex)&pageSize=\(pageSize)&search=&sortBy=UpdatedAt&sortDescending=True"
  }

  private func fetchPage(startIndex: Int, replace: Bool) {
    let urlString = urlForList(startIndex: startIndex, pageSize: pageSize)
    guard let url = URL(string: urlString) else { return }
    if !replace { isLoadingMore = true }
    var request = URLRequest(url: url)
    GuestIdentity.applyIfNeeded(to: &request)
    URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        let items = Self.decode(data: data)
        if replace {
          self.playlists = items
        } else {
          let existing = Set(self.playlists.map { $0.id })
          self.playlists += items.filter { !existing.contains($0.id) }
        }
        self.canLoadMore = items.count >= self.pageSize
        self.isLoadingMore = false
      }
    }.resume()
  }

  private static func decode(data: Data?) -> [Playlist] {
    guard let data else { return [] }
    let decoder = JSONDecoder()
    if let items = (try? decoder.decode(LossyArray<PlaylistListItem>.self, from: data))?.elements {
      return items.map { $0.asPlaylist() }
    }
    if let items = try? decoder.decode([PlaylistListItem].self, from: data) {
      return items.map { $0.asPlaylist() }
    }
    return []
  }
}

nonisolated private enum TopChartSection: Sendable {
  case songs
  case weeklyTrending
}

@MainActor
final class TopChartViewModel: ObservableObject {
  @Published var songs: [Song] = []
  @Published var weeklyTrending: [Song] = []

  func loadIfNeeded() {
    fetch(
      url: "\(StorageHost.api)/api/explore/trendings?days=all",
      target: .songs)
    fetch(
      url: "\(StorageHost.api)/api/explore/trendings?days=7&take=20",
      target: .weeklyTrending)
  }

  private func fetch(url: String, target: TopChartSection) {
    guard let u = URL(string: url) else { return }
    var request = URLRequest(url: u)
    GuestIdentity.applyIfNeeded(to: &request)
    URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
      Task { @MainActor [weak self, data, target] in
        self?.applyTopChartResponse(data, to: target)
      }
    }.resume()
  }

  private func applyTopChartResponse(_ data: Data?, to target: TopChartSection) {
    guard let data, let list = try? JSONDecoder().decode([Song].self, from: data) else {
      return
    }

    switch target {
    case .songs:
      songs = list
    case .weeklyTrending:
      weeklyTrending = list
    }
  }
}

@MainActor
final class GenresViewModel: ObservableObject {
  @Published var genres: [GenreSummary] = []
  @Published var artworkURLs: [String: URL] = [:]
  @Published var firstSongs: [String: Song] = [:]
  @Published var allSongs: [String: [Song]] = [:]
  @Published var isLoading = false
  @Published var isLoadingMore = false
  @Published var canLoadMore = true
  private var page = 0
  private let pageSize = 50
  private var genreDetailOrder: [String] = []
  private let maxCachedGenreDetails = 30

  init() {
    #if canImport(UIKit)
      NotificationCenter.default.addObserver(
        forName: UIApplication.didReceiveMemoryWarningNotification,
        object: nil, queue: .main
      ) { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.clearCachedGenreDetails()
        }
      }
    #endif
  }

  func loadIfNeeded() {
    fetchPage(0, replace: true)
  }

  func loadMoreIfNeeded(current: GenreSummary) {
    guard let idx = genres.firstIndex(where: { $0.id == current.id }) else { return }
    if idx >= genres.count - 6 && !isLoadingMore && canLoadMore {
      fetchPage(page, replace: false)
    }
  }

  private func clearCachedGenreDetails() {
    allSongs.removeAll()
    firstSongs.removeAll()
    genreDetailOrder.removeAll()
  }

  private func fetchPage(_ page: Int, replace: Bool) {
    guard
      let url = URL(
        string:
          "\(StorageHost.api)/api/filters/genres?page=\(page)&pageSize=\(pageSize)")
    else { return }
    if replace {
      isLoading = true
    } else {
      isLoadingMore = true
    }
    var request = URLRequest(url: url)
    GuestIdentity.applyIfNeeded(to: &request)
    URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
      Task { @MainActor [weak self, data, page, replace] in
        self?.applyGenrePageResponse(data, page: page, replace: replace)
      }
    }.resume()
  }

  private func applyGenrePageResponse(_ data: Data?, page: Int, replace: Bool) {
    defer {
      isLoading = false
      isLoadingMore = false
    }

    guard let data, let list = try? JSONDecoder().decode([GenreSummary].self, from: data) else {
      canLoadMore = false
      return
    }

    let filtered = list.filter { $0.songCount > 0 }
    if replace {
      genres = filtered
    } else {
      let existing = Set(genres.map { $0.id })
      genres += filtered.filter { !existing.contains($0.id) }
    }
    canLoadMore = list.count == pageSize
    self.page = page + 1
    for genre in filtered {
      fetchDetail(for: genre)
    }
  }

  private static let neuroFallbackURL: URL? = FallbackArtProvider.shared.randomURL

  private func fetchDetail(for genre: GenreSummary) {
    if allSongs[genre.id] != nil { return }
    guard let url = URL(string: "\(StorageHost.api)/api/genres/\(genre.id)") else {
      return
    }
    var request = URLRequest(url: url)
    GuestIdentity.applyIfNeeded(to: &request)
    URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
      Task { @MainActor [weak self, data, genre] in
        self?.applyGenreDetailResponse(data, for: genre)
      }
    }.resume()
  }

  private func applyGenreDetailResponse(_ data: Data?, for genre: GenreSummary) {
    guard let data,
      let detail = try? JSONDecoder().decode(GenreDetail.self, from: data),
      let songs = detail.songs
    else {
      return
    }

    allSongs[genre.id] = songs
    if let first = songs.first {
      firstSongs[genre.id] = first
    }
    let artURL = songs.first(where: { $0.hasOwnArtwork })?.imageURL ?? Self.neuroFallbackURL
    artworkURLs[genre.id] = artURL
    genreDetailOrder.removeAll { $0 == genre.id }
    genreDetailOrder.append(genre.id)
    while genreDetailOrder.count > maxCachedGenreDetails {
      let oldest = genreDetailOrder.removeFirst()
      allSongs.removeValue(forKey: oldest)
      firstSongs.removeValue(forKey: oldest)
    }
  }
}

@MainActor
final class SearchCategorySongsViewModel: ObservableObject {
  @Published var songs: [Song] = []
  @Published var isLoading = false
  @Published private var loadFailed = false
  @Published private(set) var hasLoaded = false
  private let query: String
  private var requestToken = 0

  init(query: String) {
    self.query = query
  }

  func loadIfNeeded() {
    guard !hasLoaded else { return }
    hasLoaded = true
    fetch()
  }

  func refresh() {
    hasLoaded = true
    fetch()
  }

  var emptyStateMessage: String {
    if loadFailed {
      return "The category couldn’t be loaded. Check your connection and try again."
    }
    return "Try another category or search term."
  }

  private func fetch() {
    guard let url = URL(string: "\(StorageHost.api)/api/songs") else {
      loadFailed = songs.isEmpty
      return
    }
    requestToken += 1
    let token = requestToken
    isLoading = true
    loadFailed = false

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    GuestIdentity.applyIfNeeded(to: &request)
    request.httpBody = try? JSONSerialization.data(withJSONObject: [
      "page": 1,
      "pageSize": 100,
      "search": query,
    ])

    URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      let statusCode = (response as? HTTPURLResponse)?.statusCode
      let requestFailed = error != nil || statusCode.map { !(200..<300).contains($0) } == true
      Task { @MainActor [weak self, data, token, requestFailed] in
        self?.applyResponse(data, token: token, requestFailed: requestFailed)
      }
    }.resume()
  }

  private func applyResponse(_ data: Data?, token: Int, requestFailed: Bool) {
    guard token == requestToken else { return }
    defer { isLoading = false }

    guard !requestFailed else {
      loadFailed = songs.isEmpty
      return
    }

    guard let data else {
      loadFailed = songs.isEmpty
      return
    }

    if let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data) {
      songs = decoded.items
    } else {
      songs = SongPayloadDecoder.decodeSongs(from: data) ?? []
    }
    loadFailed = false
  }
}

@MainActor
final class SearchViewModel: ObservableObject {
  @Published var results: [Song] = []
  @Published var searchText = ""
  @Published var isSearching = false
  @Published var searchErrorMessage: String?
  private var cancellables = Set<AnyCancellable>()
  private var queryToken: Int = 0

  init() {
    $searchText
      .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
      .removeDuplicates()
      .sink { [weak self] query in
        if !query.isEmpty { self?.search(query) } else { self?.clearSearch() }
      }
      .store(in: &cancellables)
  }

  func retrySearch() {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return }
    search(query)
  }

  func search(_ query: String) {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty else {
      clearSearch()
      return
    }
    guard let url = URL(string: "\(StorageHost.api)/api/songs") else {
      results = []
      isSearching = false
      searchErrorMessage = "Search couldn't be started. Try again."
      return
    }
    queryToken += 1
    let token = queryToken
    results = []
    isSearching = true
    searchErrorMessage = nil
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    GuestIdentity.applyIfNeeded(to: &request)
    request.httpBody = try? JSONSerialization.data(withJSONObject: [
      "page": 1, "pageSize": 30, "search": trimmedQuery,
    ])
    URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      let statusCode = (response as? HTTPURLResponse)?.statusCode
      let failureMessage: String?
      if error != nil {
        failureMessage = "Check your connection and try again."
      } else if let statusCode, !(200..<300).contains(statusCode) {
        failureMessage = "Search returned an unexpected response. Try again."
      } else {
        failureMessage = nil
      }
      Task { @MainActor [weak self, data, token, failureMessage] in
        self?.applySearchResponse(data, token: token, failureMessage: failureMessage)
      }
    }.resume()
  }

  private func clearSearch() {
    queryToken += 1
    results = []
    isSearching = false
    searchErrorMessage = nil
  }

  private func applySearchResponse(_ data: Data?, token: Int, failureMessage: String?) {
    guard queryToken == token else { return }
    defer { isSearching = false }

    guard failureMessage == nil else {
      results = []
      searchErrorMessage = failureMessage
      return
    }

    guard let data else {
      results = []
      searchErrorMessage = "Search couldn't load results. Try again."
      return
    }

    if let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data) {
      results = decoded.items
      searchErrorMessage = nil
    } else if let decodedSongs = SongPayloadDecoder.decodeSongs(from: data) {
      results = decodedSongs
      searchErrorMessage = nil
    } else {
      results = []
      searchErrorMessage = "Search results couldn't be read. Try again."
    }
  }
}
