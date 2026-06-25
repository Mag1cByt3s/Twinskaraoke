import Combine
import Foundation

@MainActor
final class VideoGalleryViewModel: ObservableObject {
    @Published var videos: [GalleryVideo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var canLoadMore = true
    private var page = 1
    private let pageSize = 25

    func fetchInitial() {
        guard videos.isEmpty else { return }
        page = 1
        canLoadMore = true
        load(reset: true)
    }

    func refresh() {
        page = 1
        canLoadMore = true
        load(reset: true)
    }

    func loadMoreIfNeeded(current: GalleryVideo) {
        guard let idx = videos.firstIndex(of: current) else { return }
        if idx >= videos.count - 5, !isLoading, canLoadMore {
            load(reset: false)
        }
    }

    private func load(reset: Bool) {
        let urlString =
            "\(StorageHost.api)/api/videos?page=\(page)&pageSize=\(pageSize)&sortBy=UploadedAt&sortDescending=True"
        guard let url = URL(string: urlString) else {
            errorMessage = "The video gallery endpoint is unavailable."
            return
        }
        isLoading = true
        if reset { errorMessage = nil }
        var request = URLRequest(url: url)
        GuestIdentity.applyIfNeeded(to: &request)
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor [weak self, data, response, error, reset] in
                self?.applyVideosResponse(data, response: response, error: error, reset: reset)
            }
        }.resume()
    }

    private func applyVideosResponse(
        _ data: Data?,
        response: URLResponse?,
        error: Error?,
        reset: Bool
    ) {
        defer { isLoading = false }

        if let error {
            errorMessage = error.localizedDescription
            return
        }
        if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
            errorMessage = "The server returned HTTP \(http.statusCode)."
            return
        }
        guard let data, let decoded = try? JSONDecoder().decode(VideosResponse.self, from: data) else {
            errorMessage = "The video response could not be read."
            return
        }

        if reset {
            videos = decoded.items
        } else {
            videos += decoded.items
        }
        page += 1
        canLoadMore = videos.count < decoded.totalCount
        errorMessage = nil
    }
}

@MainActor
final class SimilarVideosViewModel: ObservableObject {
    @Published var videos: [GalleryVideo] = []
    @Published var isLoading = false

    func fetch(excluding currentID: String) {
        guard videos.isEmpty else { return }
        let urlString =
            "\(StorageHost.api)/api/videos?startIndex=0&pageSize=20&sortBy=CreatedAt&sortDescending=true"
        guard let url = URL(string: urlString) else { return }
        isLoading = true
        var request = URLRequest(url: url)
        GuestIdentity.applyIfNeeded(to: &request)
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            Task { @MainActor [weak self, data, currentID] in
                self?.applySimilarVideosResponse(data, excluding: currentID)
            }
        }.resume()
    }

    private func applySimilarVideosResponse(_ data: Data?, excluding currentID: String) {
        defer { isLoading = false }

        guard let data, let decoded = try? JSONDecoder().decode(VideosResponse.self, from: data) else {
            return
        }

        videos = decoded.items.filter { $0.id != currentID }
    }
}
