import Combine
import Foundation

class PlaylistsViewModel: ObservableObject {
  @Published var playlists: [Playlist] = []
  @Published var isLoading = false
  func fetchMusic() {
    guard
      let url = URL(
        string:
          "\(StorageHost.api)/api/playlists?startIndex=0&pageSize=15&search=&sortBy=&sortDescending=False&isSetlist=True&year=0"
      )
    else { return }
    isLoading = true
    var request = URLRequest(url: url)
    request.setValue(GuestIdentity.current, forHTTPHeaderField: "x-guest-id")
    URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
      Task { @MainActor [weak self] in
        guard let self = self else { return }
        defer { self.isLoading = false }
        guard let data,
          let decodedData = try? JSONDecoder().decode([Playlist].self, from: data)
        else { return }
        self.playlists = decodedData
      }
    }.resume()
  }
}
