import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

struct FullScreenPlayerView: View {
  @EnvironmentObject var audioManager: AudioPlayerManager
  @ObservedObject private var favorites = FavoritesManager.shared
  @ObservedObject private var vocalSeparator = VocalSeparator.shared
  @Environment(\.dismiss) private var dismiss
  @State private var showingQueue = false
  @State private var showLyrics = false
  @State private var showKaraokeControls = false
  @StateObject private var lyricsViewModel = LyricsViewModel()
  @StateObject private var upcomingLyricsViewModel = LyricsViewModel()
  var body: some View {
    let song = audioManager.currentSong
    Group {
      if let song {
        GeometryReader { geo in
          let safeTop = geo.safeAreaInsets.top
          let safeBottom = geo.safeAreaInsets.bottom
          let contentHeight = geo.size.height - safeTop - safeBottom
          let artSize = min(geo.size.width - 64, contentHeight * 0.45, 360)
          ZStack(alignment: .top) {
            Group {
              if audioManager.isRadioMode {
                RadioPlayerLayout(
                  favorites: favorites,
                  showingQueue: $showingQueue,
                  song: song,
                  artSize: artSize
                )
              } else {
                musicLayout(song: song, artSize: artSize)
              }
            }
            .padding(.top, safeTop + 6)
            .padding(.bottom, max(0, safeBottom - 8))
            dismissBar
              .padding(.top, 6)
          }
          .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(backgroundView(song: song))
      }
    }
    .sheet(isPresented: $showingQueue) {
      Group {
        if audioManager.isRadioMode {
          RadioQueueView()
            .environmentObject(audioManager)
        } else {
          QueueView()
            .environmentObject(audioManager)
        }
      }
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
    }
    .onChange(of: audioManager.currentSong?.id) { newId in
      if showLyrics, !audioManager.isRadioMode, let id = newId {
        if let prefetched = upcomingLyricsViewModel.lyrics.isEmpty
          ? nil : upcomingLyricsViewModel.lyrics,
          upcomingLyricsViewModel.loadedSongID == id
        {
          lyricsViewModel.adopt(songID: id, lyrics: prefetched)
        } else {
          lyricsViewModel.fetch(songID: id)
        }
      }
    }
    .onChange(of: audioManager.upcomingSong?.id) { upcomingId in
      if showLyrics, !audioManager.isRadioMode, let id = upcomingId {
        upcomingLyricsViewModel.fetch(songID: id)
      }
    }
    .onChange(of: audioManager.isRadioMode) { isRadio in
      if isRadio { showLyrics = false }
    }
    .onChange(of: audioManager.showFullScreen) { isShown in
      if !isShown { dismiss() }
    }
    .onChange(of: audioManager.aiEnabled) { enabled in
      if !enabled {
        showKaraokeControls = false
      }
    }
    .onAppear { favorites.loadIfNeeded() }
  }
  @ViewBuilder
  private func musicLayout(song: Song, artSize: CGFloat) -> some View {
    VStack(spacing: 0) {
      ZStack {
        if showLyrics {
          VStack(spacing: 0) {
            lyricsHeader(song: song)
            LyricsView(
              lyrics: lyricsViewModel.lyrics,
              currentTime: audioManager.progress * Double(song.duration),
              isLoading: lyricsViewModel.isLoading,
              didFail: lyricsViewModel.didFail,
              hasNoLyrics: lyricsViewModel.hasNoLyrics,
              onSeek: { time in
                guard song.duration > 0 else { return }
                audioManager.seek(to: (time + 0.1) / Double(song.duration))
              },
              onRetry: { lyricsViewModel.retry() }
            )
          }
          .overlay(alignment: .bottomTrailing) {
            if DeviceCapability.supportsKaraoke && audioManager.aiEnabled {
              VStack(spacing: 8) {
                // Processing indicator
                if vocalSeparator.processingSongID != nil {
                  aiProcessingIndicator
                }
                KaraokeRightDock(showKaraokeControls: $showKaraokeControls)
              }
              .padding(.trailing, 16)
              .padding(.bottom, 32)
            }
          }
          .transition(.opacity)
        } else {
          VStack(spacing: 0) {
            Spacer(minLength: 20)
            PlayerArtworkView(song: song, size: artSize)
            Spacer(minLength: 28)
            titleRow(song: song)
          }
          .transition(.opacity)
        }
      }
      .frame(maxHeight: .infinity)
      progressSection(song: song)
      controlsRow
        .padding(.horizontal, 12)
        .padding(.top, 40)
      Spacer(minLength: 36)
      PlayerVolumeRow()
      PlayerBottomToolbar(
        showingQueue: $showingQueue,
        song: song,
        onLyricsToggle: {
          withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            showLyrics.toggle()
          }
          if showLyrics { lyricsViewModel.fetch(songID: song.id) }
        },
        showLyrics: showLyrics
      )
      Spacer(minLength: 8)
    }
  }
  private var dismissBar: some View {
    Capsule()
      .fill(Color.primary.opacity(0.35))
      .frame(width: 40, height: 5)
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
      .onTapGesture {
        audioManager.showFullScreen = false
      }
  }
  @ViewBuilder
  private func lyricsHeader(song: Song) -> some View {
    HStack(spacing: 12) {
      LoadingImage(
        url: audioManager.displayImageURL(for: song), cornerRadius: 8, contentMode: .fill
      )
      .frame(width: 52, height: 52)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .id(song.id)
      VStack(alignment: .leading, spacing: 2) {
        Text(song.title)
          .font(.system(size: 16, weight: .bold))
          .foregroundColor(.primary)
          .lineLimit(1)
        Text(song.displayArtist)
          .font(.system(size: 13))
          .foregroundColor(.secondary)
          .lineLimit(1)
      }
      Spacer()
    }
    .padding(.horizontal, 32)
    .padding(.top, 0)
    .padding(.bottom, 0)
  }
  @ViewBuilder
  private func titleRow(song: Song) -> some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(song.title)
          .font(.system(size: 22, weight: .bold))
          .foregroundColor(.primary)
          .lineLimit(1)
          .truncationMode(.tail)
        Text(song.displayArtist)
          .font(.system(size: 17))
          .foregroundColor(.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 8)
      Button {
        favorites.toggle(songID: song.id)
      } label: {
        Group {
          let isFav = favorites.isFavorite(song.id)
          if #available(iOS 17.0, *) {
            Image(systemName: isFav ? "star.fill" : "star")
              .contentTransition(.symbolEffect(.replace))
          } else {
            Image(systemName: isFav ? "star.fill" : "star")
          }
        }
        .font(.system(size: 24, weight: .regular))
        .foregroundColor(favorites.isFavorite(song.id) ? .appAccent : .primary)
        .frame(width: 36, height: 36)
        .contentShape(Rectangle())
      }
      .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6))
    }
    .padding(.horizontal, 32)
  }
  @ViewBuilder
  private func progressSection(song: Song) -> some View {
    AppleMusicProgressBar(
      progress: $audioManager.progress,
      isScrubbing: $audioManager.isEditingProgress,
      onSeekEnd: { fraction in audioManager.seek(to: fraction) }
    )
    .padding(.horizontal, 32)
    .padding(.top, showLyrics ? 0 : 16)
    HStack {
      Text(formattedTime(audioManager.progress * Double(song.duration)))
      Spacer()
      Text(
        formattedTime(
          max(0, Double(song.duration) - audioManager.progress * Double(song.duration))))
    }
    .font(.system(size: 12, weight: .medium, design: .monospaced))
    .foregroundColor(audioManager.isEditingProgress ? .primary : .secondary)
    .scaleEffect(audioManager.isEditingProgress ? 1.12 : 1.0, anchor: .center)
    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: audioManager.isEditingProgress)
    .padding(.horizontal, 32)
    .padding(.top, 2)
  }
  private var controlsRow: some View {
    HStack(spacing: 0) {
      Button {
        audioManager.playPrevious()
      } label: {
        Image(systemName: "backward.fill")
          .font(.system(size: 32))
          .foregroundColor(.primary)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6))
      Button {
        audioManager.togglePlayPause()
      } label: {
        Group {
          if #available(iOS 17.0, *) {
            Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
              .contentTransition(.symbolEffect(.replace))
          } else {
            Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
              .contentTransition(.opacity)
          }
        }
        .font(.system(size: 48))
        .foregroundColor(.primary)
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6))
      Button {
        audioManager.playNextOrRandom()
      } label: {
        Image(systemName: "forward.fill")
          .font(.system(size: 32))
          .foregroundColor(.primary)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6))
    }
  }
  private func backgroundView(song: Song) -> some View {
    PlayerAmbientBackground(
      artworkURL: audioManager.displayImageURL(for: song),
      isPlaying: audioManager.isPlaying
    )
    .id(song.id)
  }
  private func formattedTime(_ seconds: Double) -> String {
    let s = Int(seconds)
    return String(format: "%d:%02d", s / 60, s % 60)
  }

  // MARK: - AI Processing Indicator

  private var aiProcessingIndicator: some View {
    VStack(spacing: 4) {
      ZStack {
        Circle()
          .stroke(Color.primary.opacity(0.15), lineWidth: 2)
        Circle()
          .trim(from: 0, to: CGFloat(vocalSeparator.progressFraction))
          .stroke(Color.appAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
          .rotationEffect(.degrees(-90))
        Image(systemName: "waveform")
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(.appAccent)
      }
      .frame(width: 28, height: 28)
      .background(
        Circle()
          .fill(.ultraThinMaterial)
      )
      Text("\(Int(vocalSeparator.progressFraction * 100))%")
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .foregroundColor(.secondary)
    }
    .transition(.scale.combined(with: .opacity))
    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: vocalSeparator.progressFraction)
  }
}
