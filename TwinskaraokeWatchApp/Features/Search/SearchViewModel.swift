import Combine
import Foundation

class SearchViewModel: ObservableObject {
  @Published var results: [SearchSongItem] = []
  @Published var isLoading = false
  @Published var searchText = ""
  private var cancellables = Set<AnyCancellable>()
  init() {
    $searchText
      .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
      .removeDuplicates()
      .sink { [weak self] text in
        if !text.isEmpty {
          self?.performSearch(query: text)
        } else {
          self?.results = []
        }
      }
      .store(in: &cancellables)
  }
  func performSearch(query: String) {
    guard let url = URL(string: "\(StorageHost.api)/api/songs") else { return }
    isLoading = true
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(GuestIdentity.current, forHTTPHeaderField: "x-guest-id")
    let body: [String: Any] = [
      "page": 1,
      "pageSize": 20,
      "search": query,
    ]
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
      Task { @MainActor [weak self] in
        guard let self = self else { return }
        defer { self.isLoading = false }
        guard let data,
          let decoded = try? JSONDecoder().decode(SearchResponseRoot.self, from: data)
        else { return }
        self.results = decoded.items
      }
    }.resume()
  }
}
