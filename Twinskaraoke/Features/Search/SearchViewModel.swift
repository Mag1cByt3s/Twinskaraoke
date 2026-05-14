import Combine
import Foundation

#if canImport(UIKit)
  import UIKit
#endif

struct GenreSummary: Decodable, Identifiable {
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

private struct GenreDetail: Decodable {
  let id: String
  let name: String
  let songs: [Song]?
}

@MainActor
class TopChartViewModel: ObservableObject {
  @Published var songs: [Song] = []
  @Published var weeklyTrending: [Song] = []
  func loadIfNeeded() {
    fetch(
      url: "\(StorageHost.api)/api/explore/trendings?days=all",
      keyPath: \.songs)
    fetch(
      url: "\(StorageHost.api)/api/explore/trendings?days=7&take=20",
      keyPath: \.weeklyTrending)
  }
  private func fetch(url: String, keyPath: ReferenceWritableKeyPath<TopChartViewModel, [Song]>) {
    guard let u = URL(string: url) else { return }
    var request = URLRequest(url: u)
    GuestIdentity.applyIfNeeded(to: &request)
    URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
      guard let data, let list = try? JSONDecoder().decode([Song].self, from: data) else {
        return
      }
      Task { @MainActor in self?[keyPath: keyPath] = list }
    }.resume()
  }
}

@MainActor
class GenresViewModel: ObservableObject {
  @Published var genres: [GenreSummary] = []
  @Published var artworkURLs: [String: URL] = [:]
  @Published var firstSongs: [String: Song] = [:]
  @Published var allSongs: [String: [Song]] = [:]
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
        self?.allSongs.removeAll()
        self?.firstSongs.removeAll()
        self?.genreDetailOrder.removeAll()
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
  private func fetchPage(_ page: Int, replace: Bool) {
    guard
      let url = URL(
        string:
          "\(StorageHost.api)/api/filters/genres?page=\(page)&pageSize=\(pageSize)")
    else { return }
    isLoadingMore = !replace
    var request = URLRequest(url: url)
    GuestIdentity.applyIfNeeded(to: &request)
    URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
      let decoded = data.flatMap { try? JSONDecoder().decode([GenreSummary].self, from: $0) }
      Task { @MainActor in
        guard let self else { return }
        defer { self.isLoadingMore = false }
        guard let list = decoded else {
          self.canLoadMore = false
          return
        }
        let filtered = list.filter { $0.songCount > 0 }
        if replace {
          self.genres = filtered
        } else {
          let existing = Set(self.genres.map { $0.id })
          self.genres += filtered.filter { !existing.contains($0.id) }
        }
        self.canLoadMore = list.count == self.pageSize
        self.page = page + 1
        for genre in filtered { self.fetchDetail(for: genre) }
      }
    }.resume()
  }
  private static let neuroFallbackURL = URL(
    string:
      "\(StorageHost.images)/WxURxyML82UkE7gY-PiBKw/277232b2-e00e-426b-ffb8-bb8664a73600/quality=95"
  )!
  private func fetchDetail(for genre: GenreSummary) {
    if allSongs[genre.id] != nil { return }
    guard let url = URL(string: "\(StorageHost.api)/api/genres/\(genre.id)") else {
      return
    }
    var request = URLRequest(url: url)
    GuestIdentity.applyIfNeeded(to: &request)
    URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
      guard let data,
        let detail = try? JSONDecoder().decode(GenreDetail.self, from: data)
      else { return }
      Task { @MainActor in
        guard let self else { return }
        if let songs = detail.songs {
          self.allSongs[genre.id] = songs
          if let first = songs.first {
            self.firstSongs[genre.id] = first
          }
          let artURL = songs.first(where: { $0.hasOwnArtwork })?.imageURL ?? Self.neuroFallbackURL
          self.artworkURLs[genre.id] = artURL
          self.genreDetailOrder.removeAll { $0 == genre.id }
          self.genreDetailOrder.append(genre.id)
          while self.genreDetailOrder.count > self.maxCachedGenreDetails {
            let oldest = self.genreDetailOrder.removeFirst()
            self.allSongs.removeValue(forKey: oldest)
            self.firstSongs.removeValue(forKey: oldest)
          }
        }
      }
    }.resume()
  }
}

class SearchViewModel: ObservableObject {
  @Published var results: [Song] = []
  @Published var searchText = ""
  @Published var isSearching = false
  private var cancellables = Set<AnyCancellable>()
  private var queryToken: Int = 0
  init() {
    $searchText
      .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
      .removeDuplicates()
      .sink { [weak self] query in
        if !query.isEmpty { self?.search(query) } else { self?.results = [] }
      }
      .store(in: &cancellables)
  }
  func search(_ query: String) {
    guard let url = URL(string: "\(StorageHost.api)/api/songs") else { return }
    queryToken += 1
    let token = queryToken
    isSearching = true
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    GuestIdentity.applyIfNeeded(to: &request)
    request.httpBody = try? JSONSerialization.data(withJSONObject: [
      "page": 1, "pageSize": 30, "search": query,
    ])
    URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
      if let data, let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data) {
        DispatchQueue.main.async {
          guard let self, self.queryToken == token else { return }
          self.results = decoded.items
          self.isSearching = false
        }
      } else {
        DispatchQueue.main.async {
          guard let self, self.queryToken == token else { return }
          self.isSearching = false
        }
      }
    }.resume()
  }
}
