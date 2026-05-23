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
    Group {
      if playlist.isFavorites {
        FavoritesArtworkTile()
      } else if let url = playlist.imageURL {
        LoadingImage(url: url, cornerRadius: cornerRadius)
      } else {
        PersonalPlaylistCover(playlist: playlist, cornerRadius: cornerRadius)
      }
    }
  }
}

private struct PersonalPlaylistCover: View {
  let playlist: Playlist
  let cornerRadius: CGFloat
  @StateObject private var loader = PlaylistCoverLoader()

  var body: some View {
    Group {
      if let url = loader.imageURL {
        LoadingImage(url: url, cornerRadius: cornerRadius)
      } else {
        PlaylistPlaceholderArtwork(seed: playlist.id)
      }
    }
    .onAppear {
      if playlist.isPersonal {
        loader.load(playlistID: playlist.id)
      }
    }
    .onChange(of: playlist.id) { _, newID in
      loader.load(playlistID: newID)
    }
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
