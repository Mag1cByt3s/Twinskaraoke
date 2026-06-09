import SwiftUI

enum SongRowSize {
  case compact, regular
  var artSize: CGFloat {
    switch self {
    case .compact: return 44
    case .regular: return 48
    }
  }
  var cornerRadius: CGFloat { AM.Radius.thumb }
  var titleFont: Font {
    switch self {
    case .compact: return .system(size: 15, weight: .regular)
    case .regular: return AM.Font.rowTitle
    }
  }
  var subtitleFont: Font {
    switch self {
    case .compact: return .system(size: 12)
    case .regular: return AM.Font.rowSubtitle
    }
  }
  var indicatorSize: CGFloat {
    switch self {
    case .compact: return 14
    case .regular: return 16
    }
  }
}

struct SongRow: View {
  let song: Song
  let size: SongRowSize
  var showsArtwork: Bool = true
  var trailing: AnyView? = nil
  @EnvironmentObject var audioManager: AudioPlayerManager
  @StateObject private var downloads = DownloadManager.shared
  @State private var showAddToPlaylist = false
  private var isCurrentSong: Bool { audioManager.currentSong?.id == song.id }
  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        if showsArtwork {
          LoadingImage(
            url: audioManager.displayImageURL(for: song), cornerRadius: size.cornerRadius
          )
          .frame(width: size.artSize, height: size.artSize)
          .clipShape(RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous))
        } else {
          RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
            .fill(Color(.tertiarySystemFill))
            .frame(width: size.artSize, height: size.artSize)
            .overlay {
              Image(systemName: "music.note")
                .font(.system(size: size.indicatorSize, weight: .semibold))
                .foregroundStyle(.secondary)
            }
        }
        if isCurrentSong {
          RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
            .fill(Color.appArtworkOverlay)
            .frame(width: size.artSize, height: size.artSize)
          EqualizerBars(isAnimating: audioManager.isPlaying)
            .frame(width: size.indicatorSize, height: size.indicatorSize)
            .foregroundColor(.primary)
        }
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(song.title)
          .font(size.titleFont)
          .foregroundColor(isCurrentSong ? .appAccent : .primary)
          .lineLimit(1)
        Text(song.displayArtist)
          .font(size.subtitleFont)
          .foregroundColor(.secondary)
          .lineLimit(1)
      }
      Spacer()
      if downloads.isDownloaded(song.id) {
        Image(systemName: "arrow.down.circle.fill")
          .font(.system(size: 13))
          .foregroundColor(.secondary)
      } else if downloads.isDownloading(song.id) {
        LoadingIndicator(size: 18)
      }
      if !song.durationText.isEmpty {
        Text(song.durationText)
          .font(.system(size: 13, design: .rounded))
          .foregroundColor(.secondary)
          .monospacedDigit()
      }
      if let trailing {
        trailing
      } else {
        Menu {
          songActions
        } label: {
          Image(systemName: "ellipsis")
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.secondary)
            .frame(width: 32, height: 32)
            .background(.primary.opacity(0.055), in: Circle())
            .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.65, haptic: .selection))
      }
    }
    .padding(.vertical, size == .regular ? 5 : 3)
    .contentShape(Rectangle())
    .contextMenu {
      songActions
    } preview: {
      SongContextPreview(song: song)
        .environmentObject(audioManager)
    }
    .sheet(isPresented: $showAddToPlaylist) {
      AddToPlaylistSheet(song: song)
    }
  }

  @ViewBuilder
  private var songActions: some View {
    SongActionsMenuItems(song: song) {
      showAddToPlaylist = true
    }
  }
}

struct SongRowSkeleton: View {
  let size: SongRowSize

  private var titleWidth: CGFloat {
    switch size {
    case .compact: return 132
    case .regular: return 172
    }
  }

  private var subtitleWidth: CGFloat {
    switch size {
    case .compact: return 92
    case .regular: return 118
    }
  }

  var body: some View {
    HStack(spacing: 12) {
      RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
        .fill(Color.appPlaceholderPrimary)
        .frame(width: size.artSize, height: size.artSize)

      VStack(alignment: .leading, spacing: 8) {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
          .fill(Color.appPlaceholderSecondary)
          .frame(width: titleWidth, height: size == .regular ? 12 : 11)
        RoundedRectangle(cornerRadius: 3, style: .continuous)
          .fill(Color.appPlaceholderPrimary)
          .frame(width: subtitleWidth, height: size == .regular ? 10 : 9)
      }

      Spacer(minLength: 12)

      RoundedRectangle(cornerRadius: 3, style: .continuous)
        .fill(Color.appPlaceholderPrimary)
        .frame(width: 38, height: 10)

      Circle()
        .fill(Color.appPlaceholderPrimary)
        .frame(width: 32, height: 32)
    }
    .padding(.vertical, size == .regular ? 5 : 3)
    .redacted(reason: .placeholder)
    .accessibilityLabel("Loading song")
  }
}

struct SongActionsMenuItems: View {
  let song: Song
  let onAddToPlaylist: () -> Void
  @EnvironmentObject private var audioManager: AudioPlayerManager
  @StateObject private var downloads = DownloadManager.shared
  @ObservedObject private var favorites = FavoritesManager.shared

  var body: some View {
    Button {
      AppHaptic.selection.play()
      audioManager.playNext(song: song)
    } label: {
      Label("Play Next", systemImage: "text.insert")
    }

    Button {
      AppHaptic.selection.play()
      onAddToPlaylist()
    } label: {
      Label("Add to Playlist", systemImage: "plus.circle")
    }

    Button {
      let wasFavorite = favorites.isFavorite(song.id)
      favorites.toggle(songID: song.id)
      if wasFavorite {
        AppHaptic.selection.play()
      } else {
        AppHaptic.success.play()
      }
    } label: {
      if favorites.isFavorite(song.id) {
        Label("Remove from Favorites", systemImage: "star.slash")
      } else {
        Label("Favorite", systemImage: "star")
      }
    }

    Divider()

    if downloads.isDownloaded(song.id) {
      Button(role: .destructive) {
        AppHaptic.warning.play()
        downloads.remove(songID: song.id)
      } label: {
        Label("Remove Download", systemImage: "trash")
      }
    } else if downloads.isDownloading(song.id) {
      Button {
        AppHaptic.selection.play()
        downloads.cancel(songID: song.id)
      } label: {
        Label("Cancel Download", systemImage: "xmark.circle")
      }
    } else {
      Button {
        AppHaptic.success.play()
        downloads.download(song: song)
      } label: {
        Label("Download", systemImage: "arrow.down.circle")
      }
    }
  }
}

struct SongContextPreview: View {
  let song: Song
  @EnvironmentObject private var audioManager: AudioPlayerManager

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      LoadingImage(url: audioManager.displayImageURL(for: song), cornerRadius: 10)
        .aspectRatio(1, contentMode: .fill)
        .frame(width: 220, height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      VStack(alignment: .leading, spacing: 3) {
        Text(song.title)
          .font(.system(size: 17, weight: .semibold))
          .foregroundColor(.primary)
          .lineLimit(2)
        Text(song.displayArtist)
          .font(.system(size: 14))
          .foregroundColor(.secondary)
          .lineLimit(2)
      }
    }
    .padding(16)
    .frame(width: 252, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}

private struct SongRowAccessibilityModifier: ViewModifier {
  let song: Song
  var isPending = false
  let onPlay: () -> Void
  @EnvironmentObject private var audioManager: AudioPlayerManager
  @ObservedObject private var downloads = DownloadManager.shared
  @ObservedObject private var favorites = FavoritesManager.shared

  func body(content: Content) -> some View {
    content
      .accessibilityLabel(song.title)
      .accessibilityValue(accessibilityValue)
      .accessibilityHint(accessibilityHint)
      .accessibilityAddTraits(.isButton)
      .accessibilityAction(named: "Play") {
        onPlay()
      }
      .accessibilityAction(named: "Play Next") {
        AppHaptic.selection.play()
        audioManager.playNext(song: song)
      }
      .accessibilityAction(named: favoriteActionTitle) {
        toggleFavorite()
      }
      .accessibilityAction(named: downloadActionTitle) {
        performDownloadAction()
      }
  }

  private var accessibilityValue: String {
    var values = [song.displayArtist]
    if !song.durationText.isEmpty {
      values.append(song.durationText)
    }
    if audioManager.currentSong?.id == song.id {
      values.append(audioManager.isPlaying ? "Now playing" : "Current song")
    }
    if isPending {
      values.append("Loading")
    }
    if favorites.isFavorite(song.id) {
      values.append("Favorite")
    }
    if downloads.isDownloaded(song.id) {
      values.append("Downloaded")
    } else if downloads.isDownloading(song.id) {
      values.append("Downloading")
    }
    return values.joined(separator: ", ")
  }

  private var accessibilityHint: String {
    if isPending {
      return "Preparing playback. More song actions are available from the row menu."
    }
    return "Double tap to play. Swipe up or down for playback and library actions."
  }

  private var favoriteActionTitle: String {
    favorites.isFavorite(song.id) ? "Remove from Favorites" : "Favorite"
  }

  private var downloadActionTitle: String {
    if downloads.isDownloaded(song.id) {
      return "Remove Download"
    }
    if downloads.isDownloading(song.id) {
      return "Cancel Download"
    }
    return "Download"
  }

  private func toggleFavorite() {
    let wasFavorite = favorites.isFavorite(song.id)
    favorites.toggle(songID: song.id)
    if wasFavorite {
      AppHaptic.selection.play()
    } else {
      AppHaptic.success.play()
    }
  }

  private func performDownloadAction() {
    if downloads.isDownloaded(song.id) {
      AppHaptic.warning.play()
      downloads.remove(songID: song.id)
    } else if downloads.isDownloading(song.id) {
      AppHaptic.selection.play()
      downloads.cancel(songID: song.id)
    } else {
      AppHaptic.success.play()
      downloads.download(song: song)
    }
  }
}

extension View {
  func songRowAccessibility(
    song: Song,
    isPending: Bool = false,
    onPlay: @escaping () -> Void
  ) -> some View {
    modifier(SongRowAccessibilityModifier(song: song, isPending: isPending, onPlay: onPlay))
  }
}
