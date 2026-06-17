import SwiftUI

struct DownloadedSongsView: View {
  @StateObject private var downloads = DownloadManager.shared
  @StateObject private var recentlyPlayed = RecentlyPlayedStore.shared
  @EnvironmentObject var audioManager: AudioPlayerManager
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var localSongs: [Song] = []
  @State private var scrollOffset: CGFloat = 0
  @State private var showRemoveAllConfirmation = false

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  var body: some View {
    GeometryReader { geo in
      ScrollView {
        if localSongs.isEmpty {
          DownloadedEmptyStateView {
            refresh()
          }
            .frame(width: geo.size.width, height: geo.size.height - 100)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
        } else {
          VStack(spacing: 18) {
            heroHeader(width: geo.size.width)
            VStack(spacing: 4) {
              Text("Downloaded")
                .font(.title2.bold())
              Text(downloadedSubtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            actionButtons
              .padding(.horizontal)
            LazyVStack(spacing: 0) {
              ForEach(Array(localSongs.enumerated()), id: \.element.id) { idx, song in
                SongRow(song: song, size: .regular)
                  .padding(.horizontal)
                  .padding(.vertical, 8)
                  .contentShape(Rectangle())
                  .onTapGesture {
                    play(song)
                  }
                  .songRowAccessibility(song: song) {
                    play(song)
                  }
                  .contextMenu {
                    DownloadedSongMenuItems(song: song) {
                      removeDownload(song)
                    }
                  } preview: {
                    SongContextPreview(song: song)
                      .environmentObject(audioManager)
                  }
                if idx < localSongs.count - 1 {
                  Divider().padding(.leading, 76)
                }
              }
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
          }
          .padding(.bottom, 16)
          .background(
            GeometryReader { proxy in
              Color.clear.preference(
                key: DownloadedScrollOffsetKey.self,
                value: proxy.frame(in: .named("downloadedScroll")).minY
              )
            }
          )
        }
      }
      .scrollBounceBehavior(.basedOnSize)
      .scrollDismissesKeyboard(.interactively)
      .coordinateSpace(name: "downloadedScroll")
      .bottomChromeScrollTracking()
      .onPreferenceChange(DownloadedScrollOffsetKey.self) { scrollOffset = $0 }
    }
    .navigationTitle(scrollOffset < -180 ? "Downloaded" : "")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(scrollOffset < -180 ? .visible : .hidden, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        if !localSongs.isEmpty {
          DownloadedSongsMenu(
            playInOrder: playInOrder,
            shuffle: shuffle,
            removeAll: requestRemoveAllDownloads
          )
        }
      }
    }
    .alert("Remove all downloads?", isPresented: $showRemoveAllConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Remove Downloads", role: .destructive) {
        removeAllDownloads()
      }
    } message: {
      Text("All offline songs on this device will be removed. You can download them again from song menus.")
    }
    .musicScreenBackground()
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: scrollOffset < -180)
    .animation(
      reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.84),
      value: localSongs.map(\.id)
    )
    .scrollIndicators(.hidden)
    .refreshable {
      AppHaptic.selection.play()
      refresh()
    }
    .onAppear { refresh() }
    .onChange(of: downloads.downloadedIDs) { _, _ in refresh() }
  }

  private var downloadedSubtitle: String {
    let count = localSongs.count == 1 ? "1 song" : "\(localSongs.count) songs"
    guard let duration = downloadedDurationText else { return count }
    return "\(count) • \(duration)"
  }

  private var downloadedDurationText: String? {
    let total = localSongs.reduce(0) { $0 + max(0, $1.duration) }
    guard total > 0 else { return nil }
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    if hours > 0 {
      return "\(hours) hr \(minutes) min"
    }
    return "\(minutes) min"
  }

  @ViewBuilder
  private func heroHeader(width: CGFloat) -> some View {
    let baseSize: CGFloat = 240
    let stretch = max(0, scrollOffset)
    let shrink = max(0, -scrollOffset * 0.4)
    let size = max(140, baseSize + stretch * 0.6 - shrink)
    let blur = min(8, max(0, -scrollOffset / 30))
    mosaicArtwork
      .frame(width: size, height: size)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
      .blur(radius: blur)
      .opacity(1 - min(0.7, max(0, -scrollOffset / 250)))
      .frame(width: width)
      .padding(.top, 12)
  }
  @ViewBuilder
  private var mosaicArtwork: some View {
    let arts = Array(localSongs.prefix(4).compactMap { $0.imageURL })
    if arts.count >= 4 {
      PlaylistMosaicArtwork(urls: arts, cornerRadius: 0, showsLoading: true)
    } else if let url = arts.first {
      LoadingImage(url: url, cornerRadius: 0)
    } else {
      LinearGradient(
        colors: [Color.appAccent.opacity(0.85), Color.purple.opacity(0.85)],
        startPoint: .topLeading, endPoint: .bottomTrailing
      )
      .overlay(
        Image(systemName: "arrow.down.circle.fill")
          .font(.system(size: 64, weight: .medium))
          .foregroundColor(.white.opacity(0.85))
      )
    }
  }
  private var actionButtons: some View {
    HStack(spacing: 12) {
      Button {
        playInOrder()
      } label: {
        LibraryActionButtonLabel(symbol: "play.fill", text: "Play")
      }
      .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.75, haptic: .medium))
      .accessibilityLabel("Play downloaded songs")
      Button {
        shuffle()
      } label: {
        LibraryActionButtonLabel(symbol: "shuffle", text: "Shuffle")
      }
      .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.75, haptic: .medium))
      .accessibilityLabel("Shuffle downloaded songs")
    }
  }

  private func refresh() {
    let cached = recentlyPlayed.playlists.flatMap { $0.songListDTOs ?? [] }
    let songs = downloads.downloadedSongs(knownSongs: cached)
    if reduceMotion {
      localSongs = songs
    } else {
      withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
        localSongs = songs
      }
    }
  }

  private func playInOrder() {
    guard let first = localSongs.first else { return }
    audioManager.playInOrder(song: first, context: localSongs)
  }

  private func shuffle() {
    audioManager.playShuffled(from: localSongs)
  }

  private func play(_ song: Song) {
    AppHaptic.selection.play()
    audioManager.play(song: song, context: localSongs)
  }

  private func removeDownload(_ song: Song) {
    AppHaptic.warning.play()
    downloads.remove(songID: song.id)
    refresh()
  }

  private func requestRemoveAllDownloads() {
    AppHaptic.warning.play()
    showRemoveAllConfirmation = true
  }

  private func removeAllDownloads() {
    downloads.removeAll()
    AppHaptic.success.play()
    refresh()
  }
}

private struct DownloadedEmptyStateView: View {
  let onRefresh: () -> Void
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var isPulsing = false
  @State private var hasAppeared = false

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  var body: some View {
    VStack(spacing: AM.Spacing.xl) {
      ZStack {
        RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous)
          .fill(
            LinearGradient(
              colors: [
                Color.appAccent.opacity(0.92),
                Color(red: 0.12, green: 0.15, blue: 0.22),
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .frame(width: 158, height: 158)
          .shadow(color: Color.appAccent.opacity(0.28), radius: 18, y: 10)

        Circle()
          .strokeBorder(.white.opacity(0.22), lineWidth: 1)
          .frame(width: 92, height: 92)
          .scaleEffect(isPulsing ? 1.08 : 0.94)
          .opacity(isPulsing ? 0.55 : 1)

        Image(systemName: "arrow.down.circle.fill")
          .font(.system(size: 56, weight: .semibold))
          .foregroundColor(.white)
          .symbolRenderingMode(.hierarchical)
      }
      .scaleEffect(hasAppeared ? 1 : 0.94)
      .opacity(hasAppeared ? 1 : 0)

      VStack(spacing: AM.Spacing.s) {
        Text("No Downloads")
          .font(.system(size: 23, weight: .bold))
          .foregroundColor(.primary)
        Text("Save karaoke tracks from any song menu and they will appear here for offline playback.")
          .font(.system(size: 15))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .lineLimit(3)
      }
      .frame(maxWidth: 340)

      VStack(spacing: AM.Spacing.s) {
        DownloadedEmptyHintRow(
          systemImage: "ellipsis.circle",
          title: "Open a song menu",
          message: "Use a track's context menu from Home, Search, or Library."
        )
        DownloadedEmptyHintRow(
          systemImage: "arrow.down",
          title: "Choose Download",
          message: "Downloaded songs stay playable when the network drops."
        )
      }
      .frame(maxWidth: 360)
      .opacity(hasAppeared ? 1 : 0)
      .offset(y: hasAppeared ? 0 : 10)

      Button {
        onRefresh()
      } label: {
        Label("Refresh", systemImage: "arrow.clockwise")
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.white)
          .padding(.horizontal, AM.Spacing.xl)
          .padding(.vertical, 11)
          .background(Color.appAccent, in: Capsule())
          .shadow(color: Color.appAccent.opacity(0.28), radius: 10, y: 4)
      }
      .buttonStyle(PressableButtonStyle(scale: 0.94, dim: 0.78, haptic: .selection))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, AM.Spacing.screenMargin)
    .onAppear {
      if reduceMotion {
        hasAppeared = true
        isPulsing = false
      } else {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
          hasAppeared = true
        }
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
          isPulsing = true
        }
      }
    }
    .onChange(of: reduceMotion) { _, newValue in
      if newValue {
        isPulsing = false
      } else {
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
          isPulsing = true
        }
      }
    }
    .accessibilityElement(children: .contain)
  }
}

private struct DownloadedEmptyHintRow: View {
  let systemImage: String
  let title: String
  let message: String

  var body: some View {
    HStack(spacing: AM.Spacing.m) {
      Image(systemName: systemImage)
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.appAccent)
        .frame(width: 30, height: 30)
        .background(Color.appAccent.opacity(0.12), in: Circle())
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(.primary)
        Text(message)
          .font(.system(size: 13))
          .foregroundColor(.secondary)
          .lineLimit(2)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, AM.Spacing.m)
    .padding(.vertical, AM.Spacing.s)
    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
  }
}

private struct DownloadedSongMenuItems: View {
  let song: Song
  let onRemove: () -> Void
  @EnvironmentObject private var audioManager: AudioPlayerManager
  @ObservedObject private var favorites = FavoritesManager.shared

  var body: some View {
    Button {
      AppHaptic.selection.play()
      audioManager.playNext(song: song)
    } label: {
      Label("Play Next", systemImage: "text.insert")
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

    Button(role: .destructive) {
      onRemove()
    } label: {
      Label("Remove Download", systemImage: "trash")
    }
  }
}

private struct DownloadedSongsMenu: View {
  let playInOrder: () -> Void
  let shuffle: () -> Void
  let removeAll: () -> Void

  var body: some View {
    Menu {
      Button {
        AppHaptic.selection.play()
        playInOrder()
      } label: {
        Label("Play", systemImage: "play.fill")
      }

      Button {
        AppHaptic.selection.play()
        shuffle()
      } label: {
        Label("Shuffle", systemImage: "shuffle")
      }

      Divider()

      Button(role: .destructive) {
        AppHaptic.warning.play()
        removeAll()
      } label: {
        Label("Remove Downloads", systemImage: "trash")
      }
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

private struct DownloadedScrollOffsetKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
