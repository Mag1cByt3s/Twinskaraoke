import Combine
import Foundation

class RandomSongsViewModel: ObservableObject {
  @Published var songs: [Song] = []
  @Published var isLoading = false
  private var fetchToken: Int = 0
  func fetch() {
    guard let url = URL(string: "\(StorageHost.api)/api/songs/random") else { return }
    fetchToken += 1
    let token = fetchToken
    isLoading = true
    var request = URLRequest(url: url)
    GuestIdentity.applyIfNeeded(to: &request)
    URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
      let decoded = data.flatMap { try? JSONDecoder().decode([Song].self, from: $0) }
      DispatchQueue.main.async {
        guard let self, self.fetchToken == token else { return }
        if let decoded { self.songs = decoded }
        self.isLoading = false
      }
    }.resume()
  }
}
