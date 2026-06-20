import Combine
import SwiftUI

struct FavoritesArtworkTile: View {
  var sizeFraction: CGFloat = 0.46
  private let cornerRadius: CGFloat = 4

  var body: some View {
    GeometryReader { geo in
      let side = min(geo.size.width, geo.size.height)
      ZStack {
        Color(red: 0.94, green: 0.96, blue: 0.96)

        Image(systemName: "star.fill")
          .font(.system(size: side * sizeFraction, weight: .semibold))
          .foregroundStyle(Color(red: 1.0, green: 0.11, blue: 0.22))
          .accessibilityHidden(true)
      }
      .frame(width: geo.size.width, height: geo.size.height)
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
  }
}

struct PlaylistArtwork: View {
  let playlist: Playlist
  var cornerRadius: CGFloat = 10

  var body: some View {
    if playlist.isFavorites || canUseInitialArtwork {
      PlaylistArtworkContent(
        playlist: playlist,
        coverURLs: initialCoverURLs,
        cornerRadius: cornerRadius
      )
    } else {
      PlaylistCoverWithLoader(playlist: playlist, cornerRadius: cornerRadius)
    }
  }

  private var canUseInitialArtwork: Bool {
    if playlist.explicitCoverURL != nil {
      return true
    }
    return initialCoverURLs.count >= 4
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
        RemoteArtworkImage(url: url, cornerRadius: cornerRadius)
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
            RemoteArtworkImage(url: url, cornerRadius: 0, showsLoading: showsLoading)
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

  var body: some View {
    GeometryReader { geo in
      let side = min(geo.size.width, geo.size.height)
      ZStack {
        MusicArtworkPlaceholder(cornerRadius: 0)
        RoundedRectangle(cornerRadius: max(side * 0.05, 4), style: .continuous)
          .fill(Color.appPlaceholderSecondary.opacity(0.72))
          .frame(width: side * 0.54, height: side * 0.54)
          .offset(x: -side * 0.12, y: -side * 0.10)
        VStack(alignment: .leading, spacing: max(side * 0.035, 4)) {
          MusicSkeletonLine(width: side * 0.34, height: max(side * 0.045, 6), tone: .tertiary)
          MusicSkeletonLine(width: side * 0.24, height: max(side * 0.035, 5), tone: .primary)
        }
        .offset(x: side * 0.18, y: side * 0.21)
      }
      .frame(width: geo.size.width, height: geo.size.height)
    }
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
    return Playlist.songArtworkURLs(songListDTOs ?? [], limit: 4)
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

  static func songArtworkURLs(_ songs: [Song], limit: Int) -> [URL] {
    var seenOwnArtwork = Set<String>()
    var result: [URL] = []
    for song in songs {
      guard let url = song.imageURL else { continue }
      if song.hasOwnArtwork {
        guard seenOwnArtwork.insert(url.absoluteString).inserted else { continue }
      }
      result.append(url)
      if result.count == limit { break }
    }
    return result
  }
}
