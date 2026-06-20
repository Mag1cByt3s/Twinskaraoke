import Combine
import Foundation

@MainActor
class RandomSongsViewModel: ObservableObject {
  @Published var songs: [Song] = []
  @Published var isLoading = false
  @Published var errorMessage: String?
  private var fetchToken: Int = 0

  func fetch() {
    fetchToken += 1
    let token = fetchToken
    isLoading = true
    errorMessage = nil

    Task { [weak self] in
      guard let self else { return }
      do {
        let loadedSongs = try await KaraokeAPIClient.randomSongs()
        guard fetchToken == token else { return }
        songs = loadedSongs
        errorMessage = nil
      } catch KaraokeAPIClient.APIError.httpStatus(let statusCode) {
        guard fetchToken == token else { return }
        errorMessage = "The server returned HTTP \(statusCode)."
      } catch KaraokeAPIClient.APIError.decodeFailed {
        guard fetchToken == token else { return }
        errorMessage = "The random songs response could not be read."
      } catch {
        guard fetchToken == token else { return }
        errorMessage = error.localizedDescription
      }
      isLoading = false
    }
  }
}
