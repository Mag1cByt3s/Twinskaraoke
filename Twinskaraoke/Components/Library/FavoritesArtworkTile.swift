import Combine
import SwiftUI

struct FavoritesArtworkTile: View {
  var sizeFraction: CGFloat = 0.45
  var body: some View {
    GeometryReader { geo in
      ZStack {
        Color.appFavoritesTileBackground
        Image(systemName: "star.fill")
          .resizable()
          .scaledToFit()
          .frame(
            width: min(geo.size.width, geo.size.height) * sizeFraction,
            height: min(geo.size.width, geo.size.height) * sizeFraction
          )
          .foregroundStyle(
            LinearGradient(
              colors: [
                Color(red: 1.0, green: 0.18, blue: 0.33),
                Color(red: 1.0, green: 0.36, blue: 0.55),
              ],
              startPoint: .top, endPoint: .bottom
            )
          )
      }
      .frame(width: geo.size.width, height: geo.size.height)
    }
  }
}

struct PlaylistArtwork: View {
  let playlist: Playlist
  var cornerRadius: CGFloat = 10

  var body: some View {
    if playlist.isFavorites || !initialCoverURLs.isEmpty {
      PlaylistArtworkContent(
        playlist: playlist,
        coverURLs: initialCoverURLs,
        cornerRadius: cornerRadius
      )
    } else {
      PlaylistCoverWithLoader(playlist: playlist, cornerRadius: cornerRadius)
    }
  }

  private var initialCoverURLs: [URL] {
    if let url = playlist.explicitCoverURL {
      return [url]
    }
    return playlist.initialMosaicArtworkURLs
  }
}

struct PlaylistArtworkContent: View {
  let playlist: Playlist
  let coverURLs: [URL]
  var cornerRadius: CGFloat = 10

  var body: some View {
    Group {
      if playlist.isFavorites {
        FavoritesArtworkTile()
      } else if let url = coverURLs.first, coverURLs.count == 1 {
        LoadingImage(url: url, cornerRadius: cornerRadius)
      } else if coverURLs.count > 1 {
        PlaylistMosaicArtwork(urls: coverURLs, cornerRadius: cornerRadius)
      } else {
        PlaylistPlaceholderArtwork(seed: playlist.id)
      }
    }
  }
}

private struct PlaylistCoverWithLoader: View {
  let playlist: Playlist
  let cornerRadius: CGFloat
  @StateObject private var loader = PlaylistCoverLoader()
  @ObservedObject private var fallbackArt = FallbackArtProvider.shared

  var body: some View {
    PlaylistArtworkContent(
      playlist: playlist,
      coverURLs: loader.artworkURLs,
      cornerRadius: cornerRadius
    )
    .onAppear {
      loader.load(playlistID: playlist.id, fallback: playlist.songListDTOs)
    }
    .onChange(of: playlist.id) { _, newID in
      loader.load(playlistID: newID, fallback: playlist.songListDTOs)
    }
    .onReceive(fallbackArt.objectWillChange) { _ in
      loader.refreshFallbackArtwork()
    }
  }
}

struct PlaylistMosaicArtwork: View {
  let urls: [URL]
  var cornerRadius: CGFloat = 10
  var showsLoading = false

  var body: some View {
    GeometryReader { geo in
      let side = min(geo.size.width, geo.size.height)
      let cell = side / 2
      LazyVGrid(
        columns: [
          GridItem(.fixed(cell), spacing: 0),
          GridItem(.fixed(cell), spacing: 0),
        ],
        spacing: 0
      ) {
        ForEach(0..<4, id: \.self) { index in
          if let url = artworkURL(at: index) {
            LoadingImage(url: url, cornerRadius: 0, showsLoading: showsLoading)
              .frame(width: cell, height: cell)
          } else {
            PlaylistPlaceholderArtwork(seed: "\(index)-\(urls.count)")
              .frame(width: cell, height: cell)
          }
        }
      }
      .frame(width: side, height: side)
      .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }

  private func artworkURL(at index: Int) -> URL? {
    guard !urls.isEmpty else { return nil }
    return urls[index % urls.count]
  }
}

struct PlaylistPlaceholderArtwork: View {
  let seed: String

  private var palette: (Color, Color) {
    PlaylistPlaceholderArtwork.colorPair(for: seed)
  }

  var body: some View {
    GeometryReader { geo in
      ZStack {
        LinearGradient(
          colors: [palette.0, palette.1],
          startPoint: .topLeading, endPoint: .bottomTrailing
        )
        Image(systemName: "music.note.list")
          .resizable()
          .scaledToFit()
          .frame(
            width: min(geo.size.width, geo.size.height) * 0.4,
            height: min(geo.size.width, geo.size.height) * 0.4
          )
          .foregroundStyle(.white.opacity(0.85))
      }
      .frame(width: geo.size.width, height: geo.size.height)
    }
  }

  static func colorPair(for seed: String) -> (Color, Color) {
    let hash = seed.utf8.reduce(0) { acc, byte in
      (acc &* 31) &+ UInt64(byte)
    }
    let hue = Double((hash >> 16) & 0xFF) / 255.0
    let baseSat: Double = 0.55 + Double((hash >> 8) & 0x3F) / 255.0 * 0.35
    let topBrightness: Double = 0.50 + Double(hash & 0x3F) / 255.0 * 0.30
    let bottomBrightness: Double = 0.22 + Double((hash >> 24) & 0x3F) / 255.0 * 0.25

    func hsb(_ h: Double, _ s: Double, _ b: Double) -> Color {
      Color(hue: h, saturation: s, brightness: b)
    }
    return (
      hsb(hue, baseSat, topBrightness),
      hsb(hue, baseSat - 0.08, bottomBrightness)
    )
  }
}

extension Playlist {
  var explicitCoverURL: URL? {
    if let cfId = media?.cloudflareId, !cfId.isEmpty {
      return URL(string: "\(StorageHost.images)/\(cfId)/width=480,quality=85,format=auto")
    }
    if let path = media?.absolutePath, !path.isEmpty {
      return Playlist.mediaURL(from: path)
    }
    return nil
  }

  var initialMosaicArtworkURLs: [URL] {
    let mosaicURLs = mosaicMedia?.compactMap { media -> URL? in
      guard let path = media.absolutePath, !path.isEmpty else { return nil }
      return Playlist.mediaURL(from: path)
    } ?? []
    if !mosaicURLs.isEmpty {
      return Playlist.uniqueURLs(mosaicURLs, limit: 4)
    }
    return Playlist.uniqueURLs(songListDTOs?.compactMap(\.imageURL) ?? [], limit: 4)
  }

  static func mediaURL(from path: String) -> URL? {
    let normalized = path.hasPrefix("/") ? path : "/\(path)"
    return URL(string: "\(StorageHost.images)\(normalized)/width=480,quality=85,format=auto")
  }

  static func uniqueURLs(_ urls: [URL], limit: Int) -> [URL] {
    var seen = Set<String>()
    var result: [URL] = []
    for url in urls {
      guard seen.insert(url.absoluteString).inserted else { continue }
      result.append(url)
      if result.count == limit { break }
    }
    return result
  }
}
