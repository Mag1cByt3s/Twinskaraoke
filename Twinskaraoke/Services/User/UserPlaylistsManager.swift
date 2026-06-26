import Combine
import Foundation

@MainActor
final class UserPlaylistsManager: ObservableObject {
    static let shared = UserPlaylistsManager()

    @Published private(set) var playlists: [UserPlaylist] = []
    @Published private(set) var isLoading = false

    private var loaded = false

    func loadIfNeeded() {
        fetchPlaylists(force: false)
    }

    func fetchPlaylists(force: Bool = true) {
        guard !isLoading else { return }
        guard force || !loaded else { return }
        guard UserDefaults.standard.string(forKey: "nk.token") != nil else {
            playlists = []
            loaded = false
            return
        }

        isLoading = true
        Task {
            defer { isLoading = false }

            guard let req = try? KaraokeAPIClient.request(path: "/api/user/playlists"),
                  let data = try? await KaraokeAPIClient.data(for: req),
                  let decoded = try? JSONDecoder().decode([UserPlaylist].self, from: data)
            else { return }

            await MainActor.run {
                self.playlists = decoded
                self.loaded = true
                RecentlyAddedTracker.shared.registerIfNew(decoded.map(\.id))
            }
        }
    }

    func createPlaylist(
        name: String,
        description: String? = nil,
        isPublic: Bool = false,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard UserDefaults.standard.string(forKey: "nk.token") != nil else {
            completion?(false)
            return
        }

        Task {
            var body: [String: Any] = [
                "Name": name,
                "IsPublic": isPublic,
                "IsSetList": false,
            ]
            if let description, !description.isEmpty {
                body["Description"] = description
            }

            guard let req = try? KaraokeAPIClient.jsonRequest(path: "/api/playlist/save", body: body),
                  (try? await KaraokeAPIClient.data(for: req)) != nil
            else {
                completion?(false)
                return
            }

            await MainActor.run { self.fetchPlaylists() }
            completion?(true)
        }
    }

    func addSong(
        _ songID: String,
        toPlaylist playlistID: String,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard UserDefaults.standard.string(forKey: "nk.token") != nil else {
            completion?(false)
            return
        }

        Task {
            guard var req = try? KaraokeAPIClient.request(
                path: "/api/user/playlists/\(playlistID)",
                queryItems: [URLQueryItem(name: "songId", value: songID)]
            ) else {
                completion?(false)
                return
            }
            req.httpMethod = "PUT"
            let ok = (try? await KaraokeAPIClient.data(for: req)) != nil
            completion?(ok)
        }
    }

    func clear() {
        playlists = []
        loaded = false
    }
}
