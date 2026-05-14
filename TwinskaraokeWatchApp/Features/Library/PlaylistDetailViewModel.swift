import Combine
import Foundation

class PlaylistDetailViewModel: ObservableObject {
  @Published var songs: [Song] = []
  @Published var isLoading = false
  let playlistID: String
  init(playlistID: String) {
    self.playlistID = playlistID
  }
  func fetchSongs() {
    guard let url = URL(string: "\(StorageHost.api)/api/playlist/\(playlistID)") else {
      return
    }
    isLoading = true
    var request = URLRequest(url: url)
    request.setValue(GuestIdentity.current, forHTTPHeaderField: "x-guest-id")
    URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
      Task { @MainActor [weak self] in
        guard let self = self else { return }
        defer { self.isLoading = false }
        guard let data,
          let decodedData = try? JSONDecoder().decode(PlaylistDetail.self, from: data)
        else { return }
        self.songs = decodedData.songListDTOs
      }
    }.resume()
  }
}
