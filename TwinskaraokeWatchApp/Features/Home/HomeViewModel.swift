import Combine
import Foundation

class HomeViewModel: ObservableObject {
  @Published var trending: [Song] = []
  @Published var isLoading = false
  func fetchTrending() {
    guard
      let url = URL(
        string: "\(StorageHost.api)/api/explore/trendings?days=7&take=10")
    else { return }
    isLoading = true
    var request = URLRequest(url: url)
    request.setValue(GuestIdentity.current, forHTTPHeaderField: "x-guest-id")
    URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
      Task { @MainActor [weak self] in
        guard let self = self else { return }
        defer { self.isLoading = false }
        guard let data, let songs = try? JSONDecoder().decode([Song].self, from: data) else {
          return
        }
        self.trending = songs
      }
    }.resume()
  }
}
