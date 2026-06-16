import Combine
import Foundation

@MainActor
final class UserPlaylistsManager: ObservableObject {
  static let shared = UserPlaylistsManager()

  @Published private(set) var playlists: [UserPlaylist] = []
  @Published private(set) var isLoading = false

  private var loaded = false

  private static var endpoint: String {
    "\(StorageHost.api)/api/user/playlists"
  }

  private static var createEndpoint: String {
    "\(StorageHost.api)/api/playlist/save"
  }

  private var token: String? {
    UserDefaults.standard.string(forKey: "nk.token")
  }

  func loadIfNeeded() {
    fetchPlaylists()
  }

  func fetchPlaylists() {
    guard let token, !token.isEmpty else {
      playlists = []
      return
    }

    isLoading = true

    guard let url = URL(string: Self.endpoint) else {
      isLoading = false
      return
    }

    var request = URLRequest(url: url)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
      DispatchQueue.main.async {
        defer { self?.isLoading = false }

        guard let data,
          let http = response as? HTTPURLResponse,
          http.statusCode == 200
        else { return }

        if let decoded = try? JSONDecoder().decode([UserPlaylist].self, from: data) {
          self?.playlists = decoded
          RecentlyAddedTracker.shared.registerIfNew(decoded.map(\.id))
        }
      }
    }.resume()
  }

  func createPlaylist(
    name: String,
    description: String? = nil,
    isPublic: Bool = false,
    completion: ((Bool) -> Void)? = nil
  ) {
    guard let token, !token.isEmpty else {
      completion?(false)
      return
    }

    guard let url = URL(string: Self.createEndpoint) else {
      completion?(false)
      return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    var body: [String: Any] = [
      "Name": name,
      "IsPublic": isPublic,
      "IsSetList": false,
    ]
    if let description, !description.isEmpty {
      body["Description"] = description
    }

    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

    URLSession.shared.dataTask(with: request) { [weak self] _, response, _ in
      DispatchQueue.main.async {
        let http = response as? HTTPURLResponse
        let ok = http.map { (200..<300).contains($0.statusCode) } ?? false
        if ok {
          self?.fetchPlaylists()
        }
        completion?(ok)
      }
    }.resume()
  }

  func addSong(_ songID: String, toPlaylist playlistID: String, completion: ((Bool) -> Void)? = nil) {
    guard let token, !token.isEmpty else {
      completion?(false)
      return
    }

    guard
      let url = URL(
        string: "\(StorageHost.api)/api/user/playlists/\(playlistID)?songId=\(songID)")
    else {
      completion?(false)
      return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    URLSession.shared.dataTask(with: request) { _, response, _ in
      DispatchQueue.main.async {
        let http = response as? HTTPURLResponse
        let ok = http.map { (200..<300).contains($0.statusCode) } ?? false
        completion?(ok)
      }
    }.resume()
  }

  func clear() {
    playlists = []
    loaded = false
  }
}
