import SwiftUI

struct RandomSongsView: View {
  @StateObject var viewModel = RandomSongsViewModel()
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  private var artworkURLs: [URL] {
    Array(viewModel.songs.compactMap(\.imageURL).prefix(4))
  }

  private var subtitle: String {
    if viewModel.songs.isEmpty {
      return viewModel.isLoading ? "Finding songs" : "A fresh set of karaoke songs"
    }
    return "\(viewModel.songs.count) songs"
  }

  var body: some View {
    ScrollView {
      VStack(spacing: AM.Spacing.xl) {
        hero

        if viewModel.isLoading && viewModel.songs.isEmpty {
          songSkeletonList
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
        } else if let message = viewModel.errorMessage, viewModel.songs.isEmpty {
          RandomSongsStateView(
            title: "Couldn't Load Songs",
            message: message,
            buttonTitle: "Try Again"
          ) {
            viewModel.fetch()
          }
        } else if viewModel.songs.isEmpty {
          RandomSongsStateView(
            title: "No Random Songs",
            message: "Refresh to roll a new set of karaoke songs.",
            buttonTitle: "Refresh"
          ) {
            viewModel.fetch()
          }
        } else if viewModel.isLoading {
          songActions
          songList
            .overlay(alignment: .top) {
              ProgressView()
                .controlSize(.regular)
                .padding(.top, 8)
                .transition(.opacity)
            }
        } else {
          songActions
          songList
        }
      }
      .padding(.top, 12)
      .padding(.bottom, 24)
      .animation(
        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82),
        value: viewModel.songs.map(\.id))
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: viewModel.isLoading)
    }
    .bottomChromeScrollTracking()
    .smoothScrolling()
    .scrollIndicators(.hidden)
    .musicScreenBackground()
    .navigationTitle("Random")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          AppHaptic.selection.play()
          viewModel.fetch()
        } label: {
          Image(systemName: "arrow.triangle.2.circlepath")
            .rotationEffect(.degrees(!reduceMotion && viewModel.isLoading ? 180 : 0))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: viewModel.isLoading)
        }
        .disabled(viewModel.isLoading)
        .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.72))
      }
      if !viewModel.songs.isEmpty {
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            RandomSongsActionsMenu(songs: viewModel.songs) {
              viewModel.fetch()
            }
          } label: {
            Image(systemName: "ellipsis")
              .font(.system(size: 16, weight: .semibold))
              .foregroundColor(.appAccent)
              .frame(width: 32, height: 32)
              .contentShape(Rectangle())
          }
          .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.72, haptic: .selection))
        }
      }
    }
    .refreshable {
      AppHaptic.selection.play()
      viewModel.fetch()
    }
    .onAppear {
      if viewModel.songs.isEmpty { viewModel.fetch() }
    }
  }

  private var hero: some View {
    VStack(spacing: AM.Spacing.m) {
      artworkMosaic
        .frame(width: 248, height: 248)
        .clipShape(RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous))
        .amShadow(viewModel.songs.isEmpty ? AM.Shadow.heroIdle : AM.Shadow.heroPlaying)
        .overlay(alignment: .bottomTrailing) {
          if viewModel.isLoading {
            ProgressView()
              .controlSize(.regular)
              .padding(9)
              .background(.ultraThinMaterial, in: Circle())
              .padding(10)
              .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale))
          }
        }
      VStack(spacing: 4) {
        Text("Random Songs")
          .font(.title2.bold())
          .multilineTextAlignment(.center)
        Text(subtitle)
          .font(.subheadline)
          .foregroundColor(.secondary)
      }
      .padding(.horizontal, 24)
    }
    .contextMenu {
      RandomSongsActionsMenu(songs: viewModel.songs) {
        viewModel.fetch()
      }
    }
  }

  private var songActions: some View {
    HStack(spacing: 12) {
      Button {
        guard let first = viewModel.songs.first else { return }
        AppHaptic.medium.play()
        AudioPlayerManager.shared.playInOrder(song: first, context: viewModel.songs)
      } label: {
        LibraryActionButtonLabel(
          symbol: "play.fill",
          text: "Play",
          style: .primary,
          cornerRadius: AM.Radius.card
        )
      }
      .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.82))

      Button {
        AppHaptic.selection.play()
        AudioPlayerManager.shared.playShuffled(from: viewModel.songs)
      } label: {
        LibraryActionButtonLabel(
          symbol: "shuffle",
          text: "Shuffle",
          style: .secondary,
          cornerRadius: AM.Radius.card
        )
      }
      .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.82))
    }
    .padding(.horizontal)
    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
  }

  private var songList: some View {
    LazyVStack(spacing: 0) {
      ForEach(viewModel.songs) { song in
        RandomSongRow(song: song) {
          play(song)
        }
          .padding(.horizontal)
          .padding(.vertical, 8)
          .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
        Divider().padding(.leading, 76)
      }
    }
    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
  }

  private func play(_ song: Song) {
    AppHaptic.selection.play()
    AudioPlayerManager.shared.play(song: song, context: viewModel.songs)
  }

  private var songSkeletonList: some View {
    CenteredLoadingView(label: "Loading random songs")
  }

  @ViewBuilder
  private var artworkMosaic: some View {
    ZStack {
      if artworkURLs.count == 1, let url = artworkURLs.first {
        RemoteArtworkImage(url: url, cornerRadius: 0, showsLoading: false)
      } else if artworkURLs.isEmpty {
        mosaicPlaceholder
      } else {
        VStack(spacing: 2) {
          HStack(spacing: 2) {
            mosaicCell(url: artworkURL(at: 0))
            mosaicCell(url: artworkURL(at: 1))
          }
          HStack(spacing: 2) {
            mosaicCell(url: artworkURL(at: 2))
            mosaicCell(url: artworkURL(at: 3))
          }
        }
      }
      if viewModel.isLoading && viewModel.songs.isEmpty {
        Color.black.opacity(0.12)
      }
    }
  }

  private var mosaicPlaceholder: some View {
    MusicArtworkPlaceholder(cornerRadius: 0)
  }

  private func artworkURL(at index: Int) -> URL? {
    artworkURLs.indices.contains(index) ? artworkURLs[index] : nil
  }

  @ViewBuilder
  private func mosaicCell(url: URL?) -> some View {
    if let url {
      RemoteArtworkImage(url: url, cornerRadius: 0, showsLoading: false)
    } else {
      mosaicPlaceholder
    }
  }

}

private struct RandomSongRow: View {
  let song: Song
  let onPlay: () -> Void

  var body: some View {
    SongRow(song: song, size: .regular)
      .contentShape(Rectangle())
      .onTapGesture {
        onPlay()
      }
      .songRowAccessibility(song: song) {
        onPlay()
      }
  }
}

private struct RandomSongsStateView: View {
  let title: String
  let message: String
  let buttonTitle: String
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
      MusicEmptyStateMark()
        .scaleEffect(reduceMotion ? 1 : (isPulsing ? 1.03 : 0.98))
      .scaleEffect(hasAppeared ? 1 : 0.94)
      .opacity(hasAppeared ? 1 : 0)

      VStack(spacing: AM.Spacing.s) {
        Text(title)
          .font(.system(size: 23, weight: .bold))
          .foregroundColor(.primary)
          .multilineTextAlignment(.center)
        Text(message)
          .font(.system(size: 15))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .lineLimit(3)
      }
      .frame(maxWidth: 340)

      MusicEmptyActionButton(title: buttonTitle) {
        AppHaptic.selection.play()
        onRefresh()
      }

      VStack(spacing: AM.Spacing.s) {
        RandomSongsHintRow(
          title: "Fresh set",
          message: "Refresh anytime for a different karaoke mix."
        )
        RandomSongsHintRow(
          title: "Use song menus",
          message: "Favorite, queue, or download tracks from each result."
        )
      }
      .frame(maxWidth: 360)
      .opacity(hasAppeared ? 1 : 0)
      .offset(y: hasAppeared ? 0 : 10)
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, AM.Spacing.screenMargin)
    .padding(.top, 8)
    .onAppear {
      guard !reduceMotion else {
        hasAppeared = true
        isPulsing = false
        return
      }
      withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
        hasAppeared = true
      }
      withAnimation(.easeInOut(duration: 1.45).repeatForever(autoreverses: true)) {
        isPulsing = true
      }
    }
    .onChange(of: reduceMotion) { _, reduceMotion in
      if reduceMotion {
        withAnimation(nil) {
          isPulsing = false
          hasAppeared = true
        }
      } else {
        withAnimation(.easeInOut(duration: 1.45).repeatForever(autoreverses: true)) {
          isPulsing = true
        }
      }
    }
    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
    .accessibilityElement(children: .contain)
  }
}

private struct RandomSongsHintRow: View {
  let title: String
  let message: String

  var body: some View {
    HStack(spacing: AM.Spacing.m) {
      RoundedRectangle(cornerRadius: 5, style: .continuous)
        .fill(Color.appPlaceholderPrimary)
        .frame(width: 30, height: 30)
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

private struct RandomSongsActionsMenu: View {
  let songs: [Song]
  let onRefresh: () -> Void
  private let pendingDownloads: [Song]
  private let downloadingCount: Int

  private var allDownloaded: Bool {
    !songs.isEmpty && pendingDownloads.isEmpty && downloadingCount == 0
  }

  private var downloadTitle: String {
    let downloadedCount = songs.count - pendingDownloads.count - downloadingCount
    return downloadedCount > 0 ? "Download Remaining" : "Download"
  }

  init(songs: [Song], onRefresh: @escaping () -> Void) {
    self.songs = songs
    self.onRefresh = onRefresh
    // Snapshot download state for menu stability; live progress updates belong
    // in rows, not in transparent menu content.
    let downloads = DownloadManager.shared
    self.pendingDownloads = songs.filter { !downloads.isDownloaded($0.id) && !downloads.isDownloading($0.id) }
    self.downloadingCount = songs.filter { downloads.isDownloading($0.id) }.count
  }

  var body: some View {
    Button {
      AppHaptic.selection.play()
      onRefresh()
    } label: {
      Label("Refresh Set", systemImage: "arrow.triangle.2.circlepath")
    }

    if songs.isEmpty {
      Text("No Songs")
    } else {
      Divider()

      Button {
        AppHaptic.selection.play()
        if let first = songs.first {
          AudioPlayerManager.shared.playInOrder(song: first, context: songs)
        }
      } label: {
        Label("Play", systemImage: "play.fill")
      }

      Button {
        AppHaptic.selection.play()
        AudioPlayerManager.shared.playShuffled(from: songs)
      } label: {
        Label("Shuffle", systemImage: "shuffle")
      }

      Divider()

      if downloadingCount > 0 {
        Label("Downloading \(downloadingCount)...", systemImage: "arrow.down.circle")
      } else if allDownloaded {
        Button(role: .destructive) {
          AppHaptic.warning.play()
          for song in songs {
            DownloadManager.shared.remove(songID: song.id)
          }
        } label: {
          Label("Remove Downloads", systemImage: "trash")
        }
      } else {
        Button {
          AppHaptic.success.play()
          for song in pendingDownloads {
            DownloadManager.shared.download(song: song)
          }
        } label: {
          Label(downloadTitle, systemImage: "arrow.down.circle")
        }
      }
    }
  }
}
