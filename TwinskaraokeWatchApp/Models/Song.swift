import Foundation

struct Song: Codable, Identifiable, Equatable {
  let id: String
  let title: String
  let duration: Int
  let absolutePath: String
  let coverArt: SongMedia?
  let coverArtists: [String]?
  let originalArtists: [String]?
  let cloudflareId: String?
  var imageURL: URL? {
    if let cfId = cloudflareId, !cfId.isEmpty {
      return URL(string: "\(StorageHost.images)/\(cfId)/public")
    }
    guard let path = coverArt?.absolutePath else { return neuroFallbackImageURL }
    return URL(string: StorageHost.images + path + "/quality=95")
  }
  private static let neuroArtistNames: Set<String> = ["Neuro", "Neuro v1", "Neuro v2"]
  private var neuroFallbackImageURL: URL? {
    let artists = coverArtists ?? []
    let isNeuro = artists.contains { Self.neuroArtistNames.contains($0) }
    guard isNeuro else { return nil }
    return URL(
      string:
        "\(StorageHost.images)/WxURxyML82UkE7gY-PiBKw/277232b2-e00e-426b-ffb8-bb8664a73600/quality=95"
    )
  }
  var audioURL: URL? {
    let cleanPath = absolutePath.hasPrefix("/") ? String(absolutePath.dropFirst()) : absolutePath
    return URL(string: StorageHost.base + "/" + cleanPath)
  }
  var artistName: String {
    if let originals = originalArtists, !originals.isEmpty {
      return originals.joined(separator: ", ")
    }
    return coverArtists?.joined(separator: ", ") ?? "Unknown Artist"
  }
  var durationText: String {
    let minutes = duration / 60
    let seconds = duration % 60
    return String(format: "%d:%02d", minutes, seconds)
  }
  static func == (lhs: Song, rhs: Song) -> Bool {
    lhs.id == rhs.id
  }
}

struct SongMedia: Codable {
  let absolutePath: String
}

struct PlaylistDetail: Codable {
  let id: String
  let name: String
  let songListDTOs: [Song]
}
