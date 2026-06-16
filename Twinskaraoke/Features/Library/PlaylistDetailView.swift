import Combine
import SwiftUI

struct PlaylistDetailView: View {
  let playlist: Playlist
  @EnvironmentObject var audioManager: AudioPlayerManager
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @StateObject private var loader = PlaylistDetailViewModel()
  @ObservedObject private var favorites = FavoritesManager.shared
  @State private var scrollOffset: CGFloat = 0
  private var usesWideOverview: Bool {
    horizontalSizeClass == .regular
  }
  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }
  var body: some View {
    let songs: [Song] = loader.songs ?? playlist.songListDTOs ?? []
    GeometryReader { geo in
      ScrollView {
        playlistOverview(songs: songs, width: geo.size.width)
        .padding(.bottom, 16)
        .background(
          GeometryReader { proxy in
            Color.clear.preference(
              key: ScrollOffsetKey.self,
              value: proxy.frame(in: .named("playlistScroll")).minY
            )
          }
        )
      }
      .coordinateSpace(name: "playlistScroll")
      .bottomChromeScrollTracking()
      .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = $0 }
    }
    .navigationTitle(scrollOffset < -180 ? playlist.name : "")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(scrollOffset < -180 ? .visible : .hidden, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        PlaylistMoreMenu(
          playlist: playlist,
          songs: songs
        )
      }
    }
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: scrollOffset < -180)
    .animation(
      reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.84),
      value: songs.count)
    .animation(
      reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.84),
      value: loader.isLoading)
    .scrollIndicators(.hidden)
    .musicScreenBackground()
    .refreshable {
      AppHaptic.selection.play()
      loader.reload(playlistID: playlist.id, fallback: playlist.songListDTOs)
    }
    .onAppear {
      loader.reload(playlistID: playlist.id, fallback: playlist.songListDTOs)
      RecentlyPlayedStore.shared.record(playlist)
    }
    .onChange(of: favorites.favoriteIDs) { _, _ in
      guard playlist.isFavorites else { return }
      loader.reload(playlistID: playlist.id, fallback: playlist.songListDTOs)
    }
  }

  @ViewBuilder
  private func playlistOverview(songs: [Song], width: CGFloat) -> some View {
    if usesWideOverview {
      widePlaylistOverview(songs: songs)
    } else {
      compactPlaylistOverview(songs: songs, width: width)
    }
  }

  private func compactPlaylistOverview(songs: [Song], width: CGFloat) -> some View {
    VStack(spacing: 18) {
      parallaxHero(width: width)
        .contextMenu {
          PlaylistActionsMenuItems(playlist: playlist, songs: songs)
        } preview: {
          PlaylistDetailContextPreview(
            playlist: playlist,
            songs: songs,
            coverURL: playlistCoverURL
          )
        }
      playlistTitleBlock(alignment: .center)
      playlistSongsContent(songs: songs)
    }
  }

  private func widePlaylistOverview(songs: [Song]) -> some View {
    HStack(alignment: .top, spacing: AM.Spacing.xxl) {
      VStack(alignment: .leading, spacing: AM.Spacing.l) {
        playlistArtwork(size: 280)
          .contextMenu {
            PlaylistActionsMenuItems(playlist: playlist, songs: songs)
          } preview: {
            PlaylistDetailContextPreview(
              playlist: playlist,
              songs: songs,
              coverURL: playlistCoverURL
            )
          }
        playlistTitleBlock(alignment: .leading)
        if !songs.isEmpty {
          actionButtons(songs: songs, horizontalPadding: 0)
        }
      }
      .frame(width: 320, alignment: .topLeading)

      playlistSongsContent(songs: songs, rowHorizontalPadding: 0)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .frame(maxWidth: 1120, alignment: .topLeading)
    .frame(maxWidth: .infinity, alignment: .top)
    .padding(.horizontal, AM.Spacing.screenMargin)
    .padding(.top, AM.Spacing.m)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("PlaylistDetail.WideOverview")
  }

  private var playlistCoverURL: URL? {
    playlist.imageURL ?? loader.songs?.first?.imageURL
  }

  private func parallaxHero(width: CGFloat) -> some View {
    let baseSize: CGFloat = 240
    let stretch = reduceMotion ? 0 : max(0, scrollOffset)
    let shrink = reduceMotion ? 0 : max(0, -scrollOffset * 0.4)
    let size = max(140, baseSize + stretch * 0.6 - shrink)
    let blur = reduceMotion ? 0 : min(8, max(0, -scrollOffset / 30))
    let yOffset = reduceMotion ? 0 : (scrollOffset > 0 ? -scrollOffset / 2 : 0)
    let artworkOpacity = reduceMotion ? 1 : 1 - min(0.7, max(0, -scrollOffset / 250))
    return playlistArtwork(size: size)
    .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
    .blur(radius: blur)
    .opacity(artworkOpacity)
    .frame(width: width)
    .offset(y: yOffset)
    .padding(.top, 12)
  }

  private func playlistArtwork(size: CGFloat) -> some View {
    Group {
      if playlist.isFavorites {
        FavoritesArtworkTile()
      } else if let url = playlistCoverURL {
        LoadingImage(url: url, cornerRadius: 14)
      } else {
        PlaylistPlaceholderArtwork(seed: playlist.id)
      }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
  }

  private func playlistTitleBlock(alignment: TextAlignment) -> some View {
    VStack(alignment: alignment == .leading ? .leading : .center, spacing: 4) {
      Text(playlist.name)
        .font(.title2.bold())
        .multilineTextAlignment(alignment)
      Text("\(songCountText) songs")
        .font(.subheadline)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
    .padding(.horizontal, alignment == .leading ? 0 : AM.Spacing.screenMargin)
  }

  private var songCountText: String {
    let songs = loader.songs ?? playlist.songListDTOs ?? []
    return "\(songs.isEmpty ? playlist.songCount : songs.count)"
  }

  @ViewBuilder
  private func playlistSongsContent(songs: [Song], rowHorizontalPadding: CGFloat = AM.Spacing.screenMargin) -> some View {
    if !songs.isEmpty {
      VStack(spacing: 0) {
        if !usesWideOverview {
          actionButtons(songs: songs)
        }
        LazyVStack(spacing: 0) {
          ForEach(songs) { song in
            PlaylistRow(song: song, horizontalPadding: rowHorizontalPadding)
              .contentShape(Rectangle())
              .onTapGesture {
                play(song, context: songs)
              }
              .songRowAccessibility(song: song) {
                play(song, context: songs)
              }
              .accessibilityIdentifier("PlaylistDetail.song.\(song.id)")
            Divider().padding(.leading, rowHorizontalPadding + 60)
          }
        }
      }
      .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
    } else if loader.isLoading {
      PlaylistLoadingRows(horizontalPadding: rowHorizontalPadding)
        .transition(.opacity)
    } else {
      PlaylistEmptyStateView(
        isFavorites: playlist.isFavorites,
        message: loader.emptyStateMessage
      ) {
        loader.reload(playlistID: playlist.id, fallback: playlist.songListDTOs)
      }
      .padding(.top, 14)
      .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
    }
  }

  @ViewBuilder
  private func actionButtons(
    songs: [Song],
    horizontalPadding: CGFloat = AM.Spacing.screenMargin
  ) -> some View {
    HStack(spacing: 12) {
      Button {
        if let first = songs.first {
          AppHaptic.selection.play()
          audioManager.playInOrder(song: first, context: songs)
        }
      } label: {
        actionLabel(symbol: "play.fill", text: "Play")
      }
      .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.82))
      .accessibilityLabel("Play playlist")
      Button {
        AppHaptic.selection.play()
        audioManager.playShuffled(from: songs)
      } label: {
        actionLabel(symbol: "shuffle", text: "Shuffle")
      }
      .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.82))
      .accessibilityLabel("Shuffle playlist")
    }
    .padding(.horizontal, horizontalPadding)
  }
  private func actionLabel(symbol: String, text: String) -> some View {
    HStack(spacing: 6) {
      Image(systemName: symbol)
        .font(.system(size: 15, weight: .semibold))
      Text(text).fontWeight(.semibold)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
    .foregroundColor(.appAccent)
    .background(Color.appControlInactiveFill)
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
  private func play(_ song: Song, context: [Song]) {
    AppHaptic.selection.play()
    audioManager.play(song: song, context: context)
  }
}

private struct PlaylistLoadingRows: View {
  var horizontalPadding: CGFloat = AM.Spacing.screenMargin

  var body: some View {
    LazyVStack(spacing: 0) {
      ForEach(0..<7, id: \.self) { _ in
        HStack(spacing: 12) {
          RoundedRectangle(cornerRadius: AM.Radius.thumb, style: .continuous)
            .fill(Color.appPlaceholderPrimary)
            .frame(width: 48, height: 48)
          VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
              .fill(Color.appPlaceholderSecondary)
              .frame(width: 180, height: 11)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
              .fill(Color.appPlaceholderPrimary)
              .frame(width: 126, height: 9)
          }
          Spacer()
          LoadingIndicator(size: 16)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 10)
        Divider().padding(.leading, horizontalPadding + 60)
      }
    }
    .accessibilityLabel("Loading playlist songs")
  }
}

private struct PlaylistEmptyStateView: View {
  let isFavorites: Bool
  let message: String
  let onRefresh: () -> Void
  private var title: String {
    isFavorites ? "No Favorites Yet" : "No Songs"
  }
  private var icon: String {
    isFavorites ? "star" : "music.note.list"
  }
  private var resolvedMessage: String {
    guard !message.hasPrefix("The playlist") else { return message }
    if isFavorites {
      return "Favorite songs to build this playlist automatically."
    }
    return message
  }
  var body: some View {
    VStack(spacing: 16) {
      MusicEmptyState(systemImage: icon, title: title, message: resolvedMessage)
      Button {
        onRefresh()
      } label: {
        Label("Refresh", systemImage: "arrow.clockwise")
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.appAccent)
          .padding(.horizontal, 18)
          .padding(.vertical, 10)
          .background(Color.appAccent.opacity(0.12), in: Capsule())
      }
      .buttonStyle(PressableButtonStyle(scale: 0.94, dim: 0.78, haptic: .selection))
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 24)
  }
}

private struct PlaylistDetailContextPreview: View {
  let playlist: Playlist
  let songs: [Song]
  let coverURL: URL?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Group {
        if playlist.isFavorites {
          FavoritesArtworkTile()
        } else if let coverURL {
          LoadingImage(url: coverURL, cornerRadius: 10)
        } else {
          PlaylistPlaceholderArtwork(seed: playlist.id)
        }
      }
      .frame(width: 220, height: 220)
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

      VStack(alignment: .leading, spacing: 3) {
        Text(playlist.isFavorites ? "Favorites" : "Playlist")
          .font(.system(size: 12, weight: .bold))
          .foregroundColor(.appAccent)
          .textCase(.uppercase)
        Text(playlist.name)
          .font(.system(size: 17, weight: .semibold))
          .foregroundColor(.primary)
          .lineLimit(2)
        Text("\(songs.isEmpty ? playlist.songCount : songs.count) songs")
          .font(.system(size: 14))
          .foregroundColor(.secondary)
          .lineLimit(1)
      }
    }
    .padding(16)
    .frame(width: 252, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}

private struct PlaylistMoreMenu: View {
  let playlist: Playlist
  let songs: [Song]
  var body: some View {
    Menu {
      PlaylistActionsMenuItems(playlist: playlist, songs: songs)
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(.appAccent)
        .frame(width: 32, height: 32)
        .contentShape(Rectangle())
    }
    .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.65, haptic: .selection))
  }
}

struct PlaylistActionsMenuItems: View {
  let playlist: Playlist
  let songs: [Song]
  @EnvironmentObject private var audioManager: AudioPlayerManager
  @StateObject private var downloads = DownloadManager.shared
  @ObservedObject private var savedStore: SavedPlaylistsStore = .shared
  private var pendingCount: Int {
    songs.filter { !downloads.isDownloaded($0.id) && !downloads.isDownloading($0.id) }.count
  }
  private var inFlightCount: Int {
    songs.filter { downloads.isDownloading($0.id) }.count
  }
  private var allDownloaded: Bool {
    !songs.isEmpty && pendingCount == 0 && inFlightCount == 0
  }
  private var canSaveToLibrary: Bool { !playlist.isFavorites && !playlist.isPersonal }
  private var isSaved: Bool { savedStore.isSaved(playlist) }
  var body: some View {
    if !songs.isEmpty {
      Button {
        AppHaptic.selection.play()
        if let first = songs.first {
          audioManager.playInOrder(song: first, context: songs)
        }
      } label: {
        Label("Play", systemImage: "play.fill")
      }

      Button {
        AppHaptic.selection.play()
        audioManager.playShuffled(from: songs)
      } label: {
        Label("Shuffle", systemImage: "shuffle")
      }

      Divider()
    }

    if canSaveToLibrary {
      Button {
        AppHaptic.selection.play()
        savedStore.toggle(playlist)
      } label: {
        if isSaved {
          Label("Remove from Library", systemImage: "checkmark.circle.fill")
        } else {
          Label("Add to Library", systemImage: "plus.circle")
        }
      }
    }

    if !songs.isEmpty {
      if inFlightCount > 0 {
        Label("Downloading \(inFlightCount)…", systemImage: "arrow.down.circle")
      } else if allDownloaded {
        Button(role: .destructive) {
          AppHaptic.warning.play()
          for s in songs { downloads.remove(songID: s.id) }
        } label: {
          Label("Remove Downloads", systemImage: "trash")
        }
      } else {
        Button {
          AppHaptic.success.play()
          for s in songs where !downloads.isDownloaded(s.id) && !downloads.isDownloading(s.id) {
            downloads.download(song: s)
          }
        } label: {
          let label = pendingCount < songs.count ? "Download Remaining" : "Download"
          Label(label, systemImage: "arrow.down.circle")
        }
      }
    }
  }
}

private struct ScrollOffsetKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct PlaylistRow: View {
  let song: Song
  var horizontalPadding: CGFloat = AM.Spacing.screenMargin

  var body: some View {
    SongRow(song: song, size: .regular, showsArtwork: true)
      .padding(.horizontal, horizontalPadding)
      .padding(.vertical, 8)
  }
}

class PlaylistDetailViewModel: ObservableObject {
  @Published var songs: [Song]?
  @Published var isLoading = false
  @Published private var loadFailed = false
  private var loadedID: String?
  var emptyStateMessage: String {
    if loadFailed {
      return "The playlist couldn’t be loaded. Check your connection and try again."
    }
    return "Pull down or tap refresh to check for new songs."
  }
  func reload(playlistID: String, fallback: [Song]? = nil) {
    loadedID = nil
    loadFailed = false
    load(playlistID: playlistID, fallback: fallback)
  }
  func load(playlistID: String, fallback: [Song]?) {
    let alreadyLoaded = (loadedID == playlistID) && songs != nil && !isLoading
    if alreadyLoaded { return }
    loadedID = playlistID
    if songs?.isEmpty ?? true, let fallback = fallback, !fallback.isEmpty {
      self.songs = fallback
    }
    if ProcessInfo.processInfo.arguments.contains("-UITestMode"),
      let fallback = fallback, !fallback.isEmpty
    {
      songs = fallback
      isLoading = false
      loadFailed = false
      return
    }
    let isFavorites = playlistID == Playlist.favoritesID
    let urlString =
      isFavorites
      ? "\(StorageHost.api)/api/favorites/type?type=0"
      : "\(StorageHost.api)/api/playlist/\(playlistID)"
    guard let url = URL(string: urlString) else { return }
    isLoading = true
    var r = URLRequest(url: url)
    if let token = UserDefaults.standard.string(forKey: "nk.token"), !token.isEmpty {
      r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    GuestIdentity.applyIfNeeded(to: &r)
    URLSession.shared.dataTask(with: r) { [weak self] data, response, error in
      guard let self = self else { return }
      let list = Self.decodeSongs(from: data)
      let statusCode = (response as? HTTPURLResponse)?.statusCode
      let requestFailed = error != nil || statusCode.map { !(200..<300).contains($0) } == true
      DispatchQueue.main.async {
        if let list = list {
          self.songs = list
        }
        self.loadFailed = requestFailed && (self.songs?.isEmpty ?? true)
        self.isLoading = false
      }
    }.resume()
  }
  private static func decodeSongs(from data: Data?) -> [Song]? {
    SongPayloadDecoder.decodeSongs(from: data)
  }
}
