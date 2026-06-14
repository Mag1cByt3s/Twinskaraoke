import Combine
import Foundation

class HomeViewModel: ObservableObject {
  @Published var trending: [Song] = []
  @Published var isLoading = false
  func fetchTrending() {
    if ProcessInfo.processInfo.arguments.contains("-UITestMode") {
      applyUITestFixture()
      return
    }
    guard !isLoading, trending.isEmpty else { return }
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

  private func applyUITestFixture() {
    isLoading = false
    trending = [
      fixtureSong(
        id: "watch-ui-song-1",
        title: "Wake Me Up Before You Go-Go",
        originalArtists: ["Wham!"],
        coverArtists: ["Neuro"]
      ),
      fixtureSong(
        id: "watch-ui-song-2",
        title: "Hero",
        originalArtists: ["Mili"],
        coverArtists: ["Neuro"]
      ),
      fixtureSong(
        id: "watch-ui-song-3",
        title: "Cure For Me",
        originalArtists: ["AURORA"],
        coverArtists: ["Neuro"]
      ),
    ]
  }

  private func fixtureSong(
    id: String,
    title: String,
    originalArtists: [String],
    coverArtists: [String]
  ) -> Song {
    Song(
      id: id,
      title: title,
      duration: 210,
      absolutePath: nil,
      cloudflareID: nil,
      coverArt: nil,
      originalArtists: originalArtists,
      coverArtists: coverArtists,
      userUploaded: false
    )
  }
}
