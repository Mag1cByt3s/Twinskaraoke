import Combine
import Foundation

class RandomSongsViewModel: ObservableObject {
  @Published var songs: [Song] = []
  @Published var isLoading = false
  @Published var errorMessage: String?
  private var fetchToken: Int = 0

  func fetch() {
    guard let url = URL(string: "\(StorageHost.api)/api/songs/random") else {
      errorMessage = "The random songs endpoint is unavailable."
      return
    }
    fetchToken += 1
    let token = fetchToken
    isLoading = true
    errorMessage = nil
    var request = URLRequest(url: url)
    GuestIdentity.applyIfNeeded(to: &request)
    URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      let result = Self.decodeRandomSongs(data: data, response: response, error: error)
      DispatchQueue.main.async {
        guard let self, self.fetchToken == token else { return }
        if let songs = result.songs {
          self.songs = songs
          self.errorMessage = nil
        } else {
          self.errorMessage = result.errorMessage
        }
        self.isLoading = false
      }
    }.resume()
  }

  nonisolated private static func decodeRandomSongs(
    data: Data?,
    response: URLResponse?,
    error: Error?
  ) -> (songs: [Song]?, errorMessage: String?) {
    if let error {
      return (nil, error.localizedDescription)
    }
    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
      return (nil, "The server returned HTTP \(http.statusCode).")
    }
    guard let data else {
      return (nil, "Check your connection and try again.")
    }
    guard let decoded = try? JSONDecoder().decode([Song].self, from: data) else {
      return (nil, "The random songs response could not be read.")
    }
    return (decoded, nil)
  }
}
