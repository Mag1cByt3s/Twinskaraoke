import Combine
import SwiftUI

@MainActor
final class PlaybackRowState: ObservableObject {
    static let shared = PlaybackRowState()

    @Published private(set) var currentSongID: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var isRadioMode = false
    @Published private(set) var radioArtworkURL: URL?

    private var cancellables = Set<AnyCancellable>()

    private init() {
        let manager = AudioPlayerManager.shared
        manager.$currentSong
            .map(\.?.id)
            .removeDuplicates()
            .sink { [weak self] in self?.currentSongID = $0 }
            .store(in: &cancellables)

        manager.$isPlaying
            .removeDuplicates()
            .sink { [weak self] in self?.isPlaying = $0 }
            .store(in: &cancellables)

        manager.$isRadioMode
            .removeDuplicates()
            .sink { [weak self] in self?.isRadioMode = $0 }
            .store(in: &cancellables)

        manager.$radioArtworkURL
            .removeDuplicates()
            .sink { [weak self] in self?.radioArtworkURL = $0 }
            .store(in: &cancellables)
    }

    func displayImageURL(for song: Song) -> URL? {
        if isRadioMode, currentSongID == song.id, let radioArtworkURL {
            return radioArtworkURL
        }
        return song.imageURL
    }
}
