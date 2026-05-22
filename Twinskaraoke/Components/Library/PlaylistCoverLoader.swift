import Combine
import Foundation
import SwiftUI

@MainActor
final class PlaylistCoverLoader: ObservableObject {
  @Published var imageURL: URL?
  private var loadedID: String?

  func load(playlistID: String) {
    guard loadedID != playlistID else { return }
    loadedID = playlistID
    imageURL = nil

    let urlString = "\(StorageHost.api)/api/playlist/\(playlistID)"
    guard let url = URL(string: urlString) else { return }

    var request = URLRequest(url: url)
    if let token = UserDefaults.standard.string(forKey: "nk.token"), !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
      guard let self, let data else { return }
      Task { @MainActor in
        guard self.loadedID == playlistID else { return }
        self.imageURL = Self.extractFirstImageURL(from: data)
      }
    }.resume()
  }

  private static func extractFirstImageURL(from data: Data) -> URL? {
    let decoder = JSONDecoder()
    if let playlist = try? decoder.decode(Playlist.self, from: data),
       let url = playlist.imageURL {
      return url
    }
    if let songs = try? decoder.decode([Song].self, from: data),
       let url = songs.first?.imageURL {
      return url
    }
    if let wrapped = try? decoder.decode(PlaylistSongsResponse.self, from: data),
       let url = wrapped.songs.first?.imageURL {
      return url
    }
    return nil
  }
}

private struct PlaylistSongsResponse: Codable {
  let songs: [Song]
  enum CodingKeys: String, CodingKey { case items, songListDTOs, songs }
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    if let v = try? c.decode([Song].self, forKey: .songListDTOs) { songs = v }
    else if let v = try? c.decode([Song].self, forKey: .items) { songs = v }
    else if let v = try? c.decode([Song].self, forKey: .songs) { songs = v }
    else { songs = [] }
  }
  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(songs, forKey: .songs)
  }
}
