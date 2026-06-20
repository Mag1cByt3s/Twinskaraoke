import SwiftUI

struct RadioPlayerLayout: View {
  @EnvironmentObject var audioManager: AudioPlayerManager
  @ObservedObject var favorites: FavoritesManager
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @Binding var showingQueue: Bool
  let song: Song
  let artSize: CGFloat
  var body: some View {
    VStack(spacing: 0) {
      Spacer(minLength: 8)
      PlayerArtworkView(song: song, size: artSize)
        .contextMenu {
          radioActions
        } preview: {
          SongContextPreview(song: song)
        }
      Spacer(minLength: 28)
      headerRow
        .padding(.horizontal, 32)
        .contextMenu {
          radioActions
        } preview: {
          SongContextPreview(song: song)
        }
      Spacer(minLength: 24)
      playStopButton
      Spacer(minLength: 24)
      PlayerVolumeRow()
      PlayerBottomToolbar(
        showingQueue: $showingQueue,
        song: song,
        onLyricsToggle: {},
        showLyrics: false
      )
      Spacer(minLength: 8)
    }
  }
  private var headerRow: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Circle()
            .fill(Color.appAccent)
            .frame(width: 7, height: 7)
            .scaleEffect(reduceMotion ? 1.0 : (audioManager.isPlaying ? 1.0 : 0.6))
            .animation(liveDotAnimation, value: audioManager.isPlaying)
          Text("LIVE RADIO")
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.appAccent)
            .tracking(1.2)
          if let listeners = RadioController.shared.nowPlaying?.listeners {
            Text("·")
              .font(.system(size: 11, weight: .bold))
              .foregroundColor(.secondary.opacity(0.7))
            Text("\(listeners.unique) listening")
              .font(.system(size: 11))
              .foregroundColor(.secondary)
          }
        }
        MarqueeText(
          text: song.title,
          font: .system(size: 22, weight: .bold),
          color: .primary
        )
        Text(song.displayArtist)
          .font(.system(size: 17))
          .foregroundColor(.secondary)
          .lineLimit(1)
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Live radio")
      .accessibilityValue("\(song.title), \(song.displayArtist)")
      Spacer(minLength: 8)
      if canFavoriteRadioSong, let songID = radioFavoriteID {
        Button {
          toggleRadioFavorite(songID)
        } label: {
          Group {
            let isFav = favorites.isFavorite(songID)
            if #available(iOS 17.0, *), !reduceMotion {
              Image(systemName: isFav ? "star.fill" : "star")
                .contentTransition(.symbolEffect(.replace))
            } else {
              Image(systemName: isFav ? "star.fill" : "star")
            }
          }
          .font(.system(size: 24, weight: .regular))
          .foregroundColor(favorites.isFavorite(songID) ? .appAccent : .primary)
          .frame(width: 36, height: 36)
          .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6))
        .accessibilityLabel(
          favorites.isFavorite(songID) ? "Remove from Favorites" : "Add to Favorites"
        )
        .accessibilityValue(song.title)
        .accessibilityHint("Updates favorites for the current radio song.")
      }
    }
  }
  private var playStopButton: some View {
    Button {
      audioManager.togglePlayPause()
    } label: {
      Group {
        if #available(iOS 17.0, *), !reduceMotion {
          Image(systemName: audioManager.isPlaying ? "stop.fill" : "play.fill")
            .contentTransition(.symbolEffect(.replace))
        } else {
          Image(systemName: audioManager.isPlaying ? "stop.fill" : "play.fill")
        }
      }
      .font(.system(size: 56, weight: .regular))
      .foregroundColor(.primary)
      .frame(width: 88, height: 88)
      .contentShape(Rectangle())
    }
    .buttonStyle(PressableButtonStyle(scale: 0.9, dim: 0.6, haptic: .medium))
    .accessibilityLabel(audioManager.isPlaying ? "Stop live radio" : "Play live radio")
    .accessibilityValue(song.title)
    .accessibilityHint("Controls the live radio stream.")
  }

  @ViewBuilder
  private var radioActions: some View {
    Button {
      AppHaptic.medium.play()
      audioManager.togglePlayPause()
    } label: {
      Label(
        audioManager.isPlaying ? "Stop Live Radio" : "Play Live Radio",
        systemImage: audioManager.isPlaying ? "stop.fill" : "play.fill"
      )
    }

    Button {
      AppHaptic.selection.play()
      showingQueue = true
    } label: {
      Label("Show Live Schedule", systemImage: "list.bullet")
    }

    if canFavoriteRadioSong, let songID = radioFavoriteID {
      Button {
        toggleRadioFavorite(songID)
      } label: {
        Label(
          favorites.isFavorite(songID) ? "Remove from Favorites" : "Add to Favorites",
          systemImage: favorites.isFavorite(songID) ? "star.slash" : "star"
        )
      }
    }
  }

  private func toggleRadioFavorite(_ songID: String) {
    let wasFavorite = favorites.isFavorite(songID)
    favorites.toggle(songID: songID)
    if wasFavorite {
      AppHaptic.selection.play()
    } else {
      AppHaptic.success.play()
    }
  }

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  private var liveDotAnimation: Animation? {
    guard !reduceMotion else { return nil }
    return audioManager.isPlaying
      ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
      : .default
  }

  private var radioFavoriteID: String? {
    RadioController.shared.nowPlaying?.nowPlaying?.song.resolvedSongID
  }
  private var canFavoriteRadioSong: Bool {
    radioFavoriteID != nil
  }
}
