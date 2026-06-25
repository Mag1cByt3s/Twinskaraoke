import Combine
import Foundation

@MainActor
class PlaylistDetailViewModel: ObservableObject {
    @Published var songs: [Song]?
    @Published var isLoading = false
    @Published private var loadFailed = false
    private var loadedID: String?
    private var loadTask: Task<Void, Never>?
    var emptyStateMessage: String {
        if loadFailed {
            return "The playlist couldn't be loaded. Check your connection and try again."
        }
        return "Pull down or tap refresh to check for new songs."
    }

    func reload(playlistID: String, fallback: [Song]? = nil) {
        loadedID = nil
        loadFailed = false
        load(playlistID: playlistID, fallback: fallback)
    }

    func load(playlistID: String, fallback: [Song]?) {
        let alreadyLoaded = (loadedID == playlistID) && songs != nil && !isLoading
        if alreadyLoaded { return }
        loadedID = playlistID
        loadTask?.cancel()
        if songs?.isEmpty ?? true, let fallback, !fallback.isEmpty {
            songs = fallback
        }
        if AppRuntime.isUITestMode,
           let fallback, !fallback.isEmpty
        {
            loadTask = nil
            songs = fallback
            isLoading = false
            loadFailed = false
            return
        }
        isLoading = true
        loadTask = Task { [weak self] in
            do {
                let loadedSongs = try await KaraokeAPIClient.playlistSongs(id: playlistID)
                guard !Task.isCancelled else { return }
                self?.applyLoadedSongs(
                    loadedSongs,
                    playlistID: playlistID,
                    requestFailed: false
                )
            } catch {
                guard !Task.isCancelled else { return }
                self?.applyLoadedSongs(nil, playlistID: playlistID, requestFailed: true)
            }
        }
    }

    deinit {
        loadTask?.cancel()
    }

    private func applyLoadedSongs(_ list: [Song]?, playlistID: String, requestFailed: Bool) {
        guard loadedID == playlistID else { return }
        if let list {
            songs = list
        }
        loadFailed = requestFailed && (songs?.isEmpty ?? true)
        isLoading = false
    }
}
