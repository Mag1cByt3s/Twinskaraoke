import Combine
import Foundation

struct GalleryArtist: Codable, Identifiable, Equatable {
  let id: String
  let name: String
  let socialLink: String?
  let userId: String?
  let arts: [GalleryArt]?
}

struct GalleryArt: Codable, Identifiable, Equatable {
  let id: String
  let fileName: String?
  let description: String?
  let credit: String?
  let cloudflareId: String?
  let absolutePath: String?
  let upvotes: Int?
  var imageURL: URL? {
    if let identifier = cloudflareId {
      return URL(string: "\(StorageHost.images)/\(identifier)/public")
    }
    guard let path = absolutePath else { return nil }
    return URL(string: StorageHost.images + path + "/quality=95")
  }
  var fullHDImageURL: URL? {
    if let identifier = cloudflareId {
      return URL(string: "\(StorageHost.images)/\(identifier)/quality=95")
    }
    guard let path = absolutePath else { return imageURL }
    return URL(string: StorageHost.images + path + "/quality=95")
  }
  var blurPreviewURL: URL? {
    guard let path = absolutePath else { return nil }
    return URL(string: StorageHost.images + path + "/width=20,quality=30,blur=30")
  }
}

class ArtGalleryViewModel: ObservableObject {
  @Published var artists: [GalleryArtist] = []
  @Published var isLoading = false
  @Published var loadFailed = false
  func fetch(force: Bool = false) {
    guard force || artists.isEmpty else { return }
    guard let url = URL(string: "\(StorageHost.api)/api/media/artists?loadArts=true")
    else { return }
    loadFailed = false
    isLoading = true
    var request = URLRequest(url: url)
    GuestIdentity.applyIfNeeded(to: &request)
    URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
      guard let self = self else { return }
      if let data, let decoded = try? JSONDecoder().decode([GalleryArtist].self, from: data) {
        let filtered = decoded.filter { ($0.arts?.count ?? 0) > 0 }
          .sorted { ($0.arts?.count ?? 0) > ($1.arts?.count ?? 0) }
        DispatchQueue.main.async {
          self.artists = filtered
          self.loadFailed = false
          self.isLoading = false
        }
      } else {
        DispatchQueue.main.async {
          self.loadFailed = self.artists.isEmpty
          self.isLoading = false
        }
      }
    }.resume()
  }
}
