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

@MainActor
final class ArtGalleryViewModel: ObservableObject {
    @Published var artists: [GalleryArtist] = []
    @Published var isLoading = false
    @Published var loadFailed = false
    private var hasLoaded = false

    func fetch(force: Bool = false) {
        guard !isLoading else { return }
        guard force || !hasLoaded else { return }
        guard let url = URL(string: "\(StorageHost.api)/api/media/artists?loadArts=true")
        else { return }
        loadFailed = false
        isLoading = true
        var request = URLRequest(url: url)
        GuestIdentity.applyIfNeeded(to: &request)
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            let filtered = data.flatMap { data -> [GalleryArtist]? in
                guard let decoded = try? JSONDecoder().decode([GalleryArtist].self, from: data) else {
                    return nil
                }
                return decoded
                    .filter { ($0.arts?.count ?? 0) > 0 }
                    .sorted { ($0.arts?.count ?? 0) > ($1.arts?.count ?? 0) }
            }
            Task { @MainActor [weak self, filtered] in
                guard let self else { return }
                if let filtered {
                    artists = filtered
                    hasLoaded = true
                    loadFailed = false
                } else {
                    loadFailed = artists.isEmpty
                }
                isLoading = false
            }
        }.resume()
    }
}
