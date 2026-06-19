import Combine
import Foundation

class PlaylistsViewModel: ObservableObject {
  @Published var playlists: [Playlist] = []
  @Published var favoriteSongs: [Song] = []
  @Published var isLoading = false
  @MainActor
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
  @MainActor func allPlaylists(saved: [Playlist]) -> [Playlist] {
    let serverIDs = Set(playlists.map { $0.id })
    let localOnly = saved.filter { !serverIDs.contains($0.id) }
    return [favoritesPlaylist] + playlists + localOnly
  }
  @MainActor func recentlyAddedPlaylists(saved: [Playlist]) -> [Playlist] {
    let serverIDs = Set(playlists.map { $0.id })
    let localOnly = saved.filter { !serverIDs.contains($0.id) }
    let combined = (playlists + localOnly).sorted { lhs, rhs in
      RecentlyAddedTracker.shared.date(for: lhs.id)
        > RecentlyAddedTracker.shared.date(for: rhs.id)
    }
    return [favoritesPlaylist] + combined
  }
  func fetchPlaylists() {
    guard
      let url = URL(
        string:
          "\(StorageHost.api)/api/playlists?startIndex=0&pageSize=25&search=&sortBy=&sortDescending=False&isSetlist=False&year=0"
      )
    else { return }
    isLoading = true
    var request = URLRequest(url: url)
    GuestIdentity.applyIfNeeded(to: &request)
    URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
      if let data, let decoded = try? JSONDecoder().decode([PlaylistListItem].self, from: data) {
        let playlists = decoded.map { $0.asPlaylist() }
        DispatchQueue.main.async {
          self?.playlists = playlists
          RecentlyAddedTracker.shared.registerIfNew(playlists.map { $0.id })
          self?.isLoading = false
        }
      } else {
        DispatchQueue.main.async { self?.isLoading = false }
      }
    }.resume()
  }
  func fetchFavoriteSongs() {
    guard let url = URL(string: "\(StorageHost.api)/api/favorites/type?type=0") else {
      return
    }
    var request = URLRequest(url: url)
    if let token = UserDefaults.standard.string(forKey: "nk.token") {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    GuestIdentity.applyIfNeeded(to: &request)
    URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
      if let decoded = SongPayloadDecoder.decodeSongs(from: data) {
        DispatchQueue.main.async { self?.favoriteSongs = decoded }
      }
    }.resume()
  }
}
