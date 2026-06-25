import Combine
import Foundation

@MainActor
final class PlaylistSongCountStore: ObservableObject {
    static let shared = PlaylistSongCountStore()

    @Published private var resolvedCounts: [String: Int] = [:]
    private var loadingIDs: Set<String> = []

    func displayedCount(for playlist: Playlist) -> Int? {
        if let resolved = resolvedCounts[playlist.id], resolved > 0 {
            return resolved
        }
        let embeddedCount = playlist.songListDTOs?.count ?? 0
        if embeddedCount > 0 {
            return max(playlist.songCount, embeddedCount)
        }
        return playlist.songCount > 0 ? playlist.songCount : nil
    }

    func loadIfNeeded(for playlist: Playlist) {
        guard !playlist.isFavorites, !playlist.isPersonal else { return }
        guard playlist.songCount == 0 else { return }
        guard resolvedCounts[playlist.id] == nil else { return }
        guard !loadingIDs.contains(playlist.id) else { return }

        Task {
            loadingIDs.insert(playlist.id)
            let count: Int?
            do {
                count = try await KaraokeAPIClient.playlistSongCount(id: playlist.id)
            } catch {
                count = nil
            }

            loadingIDs.remove(playlist.id)
            if let count, count > 0 {
                resolvedCounts[playlist.id] = count
            }
        }
    }
}
