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
    case .compact: return .subheadline
    case .regular: return AM.Font.rowTitle
    }
  }
  var subtitleFont: Font {
    switch self {
    case .compact: return .caption
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
  @ObservedObject private var playback = PlaybackRowState.shared
  @StateObject private var downloads = DownloadManager.shared
  @State private var showAddToPlaylist = false
  private var isCurrentSong: Bool { playback.currentSongID == song.id }
  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        if showsArtwork {
          RemoteArtworkImage(
            url: playback.displayImageURL(for: song),
            cornerRadius: size.cornerRadius,
            fixedDisplaySize: CGSize(width: size.artSize, height: size.artSize)
          )
          .frame(width: size.artSize, height: size.artSize)
          .clipShape(RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous))
        } else {
          MusicArtworkPlaceholder(cornerRadius: size.cornerRadius)
            .frame(width: size.artSize, height: size.artSize)
        }
        if isCurrentSong {
          RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
            .fill(Color.appArtworkOverlay)
            .frame(width: size.artSize, height: size.artSize)

          EqualizerBars(isAnimating: false)
            .frame(width: size.indicatorSize, height: size.indicatorSize)
            .foregroundStyle(.primary)
        }
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(song.title)
          .font(size.titleFont)
          .foregroundStyle(isCurrentSong ? Color.appAccent : Color.primary)
          .lineLimit(1)
        Text(song.displayArtist)
          .font(size.subtitleFont)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer()
      if downloads.isDownloaded(song.id) {
        Image(systemName: "arrow.down.circle.fill")
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityLabel("Downloaded")
      } else if downloads.isDownloading(song.id) {
        ProgressView()
          .controlSize(.small)
      }
      if !song.durationText.isEmpty {
        Text(song.durationText)
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      if let trailing {
        trailing
      } else {
        Menu {
          songActions
        } label: {
          Image(systemName: "ellipsis")
            .font(.headline)
            .foregroundStyle(.secondary)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.65, haptic: .selection))
        .accessibilityLabel("More Actions")
        .accessibilityHint("Shows actions for \(song.title).")
      }
    }
    .padding(.vertical, size == .regular ? 5 : 3)
    .contentShape(Rectangle())
    .contextMenu {
      songActions
    } preview: {
      SongContextPreview(song: song)
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

enum MusicGridCardSize: Equatable {
  case regular
  case compact

  var defaultWidth: CGFloat {
    switch self {
    case .regular: return AM.Spacing.shelfTile
    case .compact: return AM.Spacing.compactShelfTile
    }
  }

  var titleFont: Font {
    switch self {
    case .regular: return AM.Font.tileTitle
    case .compact: return .subheadline
    }
  }

  var artistFont: Font {
    switch self {
    case .regular: return AM.Font.tileCaption
    case .compact: return .caption
    }
  }

  var textSpacing: CGFloat {
    switch self {
    case .regular: return AM.Spacing.s
    case .compact: return 6
    }
  }

  var usesShadow: Bool {
    switch self {
    case .regular: return true
    case .compact: return false
    }
  }
}

struct MusicGridCard: View {
  let song: Song
  let context: [Song]
  var size: MusicGridCardSize = .regular
  var width: CGFloat?
  var accessibilityIdentifier: String?
  @ObservedObject private var playback = PlaybackRowState.shared
  @State private var showAddToPlaylist = false

  init(
    song: Song,
    context: [Song],
    size: MusicGridCardSize = .regular,
    width: CGFloat? = nil,
    fillsWidth: Bool = false,
    accessibilityIdentifier: String? = nil
  ) {
    self.song = song
    self.context = context
    self.size = size
    self.width = fillsWidth ? nil : (width ?? size.defaultWidth)
    self.accessibilityIdentifier = accessibilityIdentifier
  }

  private var artistText: String {
    song.displayArtist.isEmpty ? "Unknown Artist" : song.displayArtist
  }

  var body: some View {
    Button {
      AppHaptic.selection.play()
      AudioPlayerManager.shared.play(song: song, context: context)
    } label: {
      VStack(alignment: .leading, spacing: size.textSpacing) {
        artwork
        Text(song.title)
          .font(size.titleFont)
          .foregroundStyle(.primary)
          .lineLimit(1)
        Text(artistText)
          .font(size.artistFont)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      .frame(width: width, alignment: .leading)
      .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
    .buttonStyle(PressableButtonStyle(scale: size == .regular ? 0.97 : 0.96, dim: 0.78, haptic: .selection))
    .contextMenu {
      SongActionsMenuItems(song: song) {
        showAddToPlaylist = true
      }
    } preview: {
      SongContextPreview(song: song)
    }
    .sheet(isPresented: $showAddToPlaylist) {
      AddToPlaylistSheet(song: song)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(song.title)
    .accessibilityValue(artistText)
    .accessibilityIdentifier(accessibilityIdentifier ?? "MusicGridCard.\(song.id)")
  }

  @ViewBuilder
  private var artwork: some View {
    if let width {
      artworkContent
        .frame(width: width, height: width)
        .clipShape(RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
        .modifier(MusicGridCardShadow(enabled: size.usesShadow))
    } else {
      artworkContent
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
        .modifier(MusicGridCardShadow(enabled: size.usesShadow))
    }
  }

  @ViewBuilder
  private var artworkContent: some View {
    if let imageURL = playback.displayImageURL(for: song) {

      RemoteArtworkImage(
        url: imageURL,
        cornerRadius: AM.Radius.card,
        fixedDisplaySize: width.map { CGSize(width: $0, height: $0) }
      )
    } else {
      MusicArtworkPlaceholder(cornerRadius: AM.Radius.card)
    }
  }
}

private struct MusicGridCardShadow: ViewModifier {
  let enabled: Bool

  func body(content: Content) -> some View {
    content.shadow(
      color: enabled ? AM.Shadow.card.color : .clear,
      radius: enabled ? AM.Shadow.card.radius : 0,
      y: enabled ? AM.Shadow.card.y : 0
    )
  }
}

struct SongActionsMenuItems: View {
  let song: Song
  let onAddToPlaylist: () -> Void
  private let isDownloaded: Bool
  private let isDownloading: Bool
  @ObservedObject private var favorites = FavoritesManager.shared

  init(song: Song, onAddToPlaylist: @escaping () -> Void) {
    self.song = song
    self.onAddToPlaylist = onAddToPlaylist

    let downloads = DownloadManager.shared
    self.isDownloaded = downloads.isDownloaded(song.id)
    self.isDownloading = downloads.isDownloading(song.id)
  }

  var body: some View {
    Button {
      AppHaptic.selection.play()
      AudioPlayerManager.shared.playNext(song: song)
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

    if isDownloaded {
      Button(role: .destructive) {
        AppHaptic.warning.play()
        DownloadManager.shared.remove(songID: song.id)
      } label: {
        Label("Remove Download", systemImage: "trash")
      }
    } else if isDownloading {
      Button {
        AppHaptic.selection.play()
        DownloadManager.shared.cancel(songID: song.id)
      } label: {
        Label("Cancel Download", systemImage: "xmark.circle")
      }
    } else {
      Button {
        AppHaptic.success.play()
        DownloadManager.shared.download(song: song)
      } label: {
        Label("Download", systemImage: "arrow.down.circle")
      }
    }
  }
}

struct SongContextPreview: View {
  let song: Song

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      RemoteArtworkImage(
        url: song.imageURL,
        cornerRadius: 10,
        fixedDisplaySize: CGSize(width: 220, height: 220)
      )
        .aspectRatio(1, contentMode: .fill)
        .frame(width: 220, height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      VStack(alignment: .leading, spacing: 3) {
        Text(song.title)
          .font(.headline)
          .foregroundStyle(.primary)
          .lineLimit(2)
        Text(song.displayArtist)
          .font(.subheadline)
          .foregroundStyle(.secondary)
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
  @ObservedObject private var playback = PlaybackRowState.shared
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
        AudioPlayerManager.shared.playNext(song: song)
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
    if playback.currentSongID == song.id {
      values.append(playback.isPlaying ? "Now playing" : "Current song")
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
