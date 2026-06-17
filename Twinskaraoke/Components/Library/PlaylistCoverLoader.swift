import Combine
import Foundation
import SwiftUI

@MainActor
final class PlaylistCoverLoader: ObservableObject {
  @Published var artworkURLs: [URL] = []
  private var loadedID: String?
  private var fallbackSongs: [Song] = []
  private var loadedPlaylist: Playlist?
  private var loadTask: Task<Void, Never>?

  func load(playlistID: String, fallback: [Song]? = nil) {
    if loadedID == playlistID {
      fallbackSongs = fallback ?? fallbackSongs
      refreshFallbackArtwork()
      return
    }
    loadedID = playlistID
    fallbackSongs = fallback ?? []
    loadedPlaylist = nil
    artworkURLs = Self.extractArtworkURLs(fromSongs: fallbackSongs)
    loadTask?.cancel()

    let urlString = "\(StorageHost.api)/api/playlist/\(playlistID)"
    guard let url = URL(string: urlString) else { return }

    var request = URLRequest(url: url)
    if let token = UserDefaults.standard.string(forKey: "nk.token"), !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    GuestIdentity.applyIfNeeded(to: &request)

    loadTask = Task { [weak self, request] in
      guard let data = try? await URLSession.shared.data(for: request).0 else { return }
      guard !Task.isCancelled else { return }
      self?.applyLoadedPlaylistData(data, playlistID: playlistID)
    }
  }

  deinit {
    loadTask?.cancel()
  }

  private func applyLoadedPlaylistData(_ data: Data, playlistID: String) {
    guard loadedID == playlistID else { return }
    loadedPlaylist = try? JSONDecoder().decode(Playlist.self, from: data)
    fallbackSongs = loadedPlaylist?.songListDTOs ?? SongPayloadDecoder.decodeSongs(from: data) ?? fallbackSongs
    refreshFallbackArtwork()
  }

  func refreshFallbackArtwork() {
    var urls: [URL] = []
    if let loadedPlaylist {
      urls.append(contentsOf: Self.extractMosaicURLs(from: loadedPlaylist))
    }
    urls.append(contentsOf: Self.extractArtworkURLs(fromSongs: fallbackSongs))
    artworkURLs = Playlist.uniqueURLs(urls, limit: 4)
  }

  private static func extractMosaicURLs(from playlist: Playlist) -> [URL] {
    let mediaURLs = playlist.mosaicMedia?.compactMap { media -> URL? in
      guard let path = media.absolutePath, !path.isEmpty else { return nil }
      return Playlist.mediaURL(from: path)
    } ?? []
    if !mediaURLs.isEmpty { return Playlist.uniqueURLs(mediaURLs, limit: 4) }
    return extractArtworkURLs(fromSongs: playlist.songListDTOs ?? [])
  }

  private static func extractArtworkURLs(fromSongs songs: [Song]) -> [URL] {
    Playlist.uniqueURLs(songs.compactMap(\.imageURL), limit: 4)
  }
}
