import Combine
import Foundation

@MainActor
final class PlaylistsViewModel: ObservableObject {
    @Published var playlists: [Playlist] = []
    @Published var favoriteSongs: [Song] = []
    @Published var isLoading = false

    var favoritesPlaylist: Playlist {
        let favoriteCount = max(favoriteSongs.count, FavoritesManager.shared.favoriteIDs.count)
        return Playlist(
            id: Playlist.favoritesID,
            name: "Favourite Songs",
            songCount: favoriteCount,
            mosaicMedia: nil,
            songListDTOs: favoriteSongs
        )
    }

    func allPlaylists(saved: [Playlist]) -> [Playlist] {
        let serverIDs = Set(playlists.map(\.id))
        let localOnly = saved.filter { !serverIDs.contains($0.id) }
        return [favoritesPlaylist] + playlists + localOnly
    }

    func recentlyAddedPlaylists(saved: [Playlist]) -> [Playlist] {
        let serverIDs = Set(playlists.map(\.id))
        let localOnly = saved.filter { !serverIDs.contains($0.id) }
        let combined = (playlists + localOnly).sorted { lhs, rhs in
            RecentlyAddedTracker.shared.date(for: lhs.id)
                > RecentlyAddedTracker.shared.date(for: rhs.id)
        }
        return [favoritesPlaylist] + combined
    }

    func fetchPlaylists() {
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            defer { isLoading = false }
            do {
                let loaded = try await KaraokeAPIClient.playlists(
                    startIndex: 0,
                    pageSize: 25,
                    isSetlist: false,
                    sortDescending: false
                )
                playlists = loaded
                RecentlyAddedTracker.shared.registerIfNew(loaded.map(\.id))
            } catch {
                playlists = []
            }
        }
    }

    func fetchFavoriteSongs() {
        Task { [weak self] in
            guard let self else { return }
            do {
                favoriteSongs = try await KaraokeAPIClient.favoriteSongs()
            } catch {
                favoriteSongs = []
            }
        }
    }
}
