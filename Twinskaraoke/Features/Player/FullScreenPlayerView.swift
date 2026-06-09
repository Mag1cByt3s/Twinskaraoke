import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

struct FullScreenPlayerView: View {
  @EnvironmentObject var audioManager: AudioPlayerManager
  @ObservedObject private var favorites = FavoritesManager.shared
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var showingQueue = false
  @State private var showLyrics = false
  @State private var showKaraokeControls = false
  @State private var showTranslatedLyrics = false
  @State private var showCoverArt = false
  @State private var showAddToPlaylist = false
  @State private var coverArtSaveStatus: ArtworkSaveStatus = .idle
  @State private var easterEggImageURL: URL?
  @State private var easterEggArtistName: String?
  @State private var easterEggArtistLink: String?
  @State private var coverArtArtistName: String?
  @State private var coverArtArtistLink: String?
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
    .fullScreenCover(isPresented: $showCoverArt) {
      if let song {
        let isEasterEgg = easterEggImageURL != nil
        let hdURL = easterEggImageURL ?? song.fullHDImageURL ?? audioManager.displayImageURL(for: song)
        let thumbURL = isEasterEgg ? nil : audioManager.displayImageURL(for: song)
        ZoomableImageViewer(
          url: hdURL,
          lowResURL: thumbURL,
          saveStatus: $coverArtSaveStatus,
          onSave: { saveCoverArt(url: hdURL) },
          title: isEasterEgg ? easterEggArtistName : coverArtArtistName,
          subtitle: isEasterEgg ? easterEggArtistLink : coverArtArtistLink
        )
        .onDisappear {
          easterEggImageURL = nil
          easterEggArtistName = nil
          easterEggArtistLink = nil
          coverArtSaveStatus = .idle
        }
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
    .sheet(isPresented: $showAddToPlaylist) {
      if let song {
        AddToPlaylistSheet(song: song)
      }
    }
    .onChange(of: audioManager.currentSong?.id) { _, newId in
      showTranslatedLyrics = false
      showKaraokeControls = false
      showAddToPlaylist = false
      coverArtArtistName = nil
      coverArtArtistLink = nil
      if let id = newId {
        fetchCoverArtArtist(songID: id)
      }
      if showLyrics, !audioManager.isRadioMode, let id = newId {
        if upcomingLyricsViewModel.loadedSongID == id,
          !upcomingLyricsViewModel.didFail,
          !upcomingLyricsViewModel.isLoading,
          (!upcomingLyricsViewModel.lyrics.isEmpty || upcomingLyricsViewModel.hasNoLyrics)
        {
          lyricsViewModel.adopt(
            songID: id,
            lyrics: upcomingLyricsViewModel.lyrics,
            hasNoLyrics: upcomingLyricsViewModel.hasNoLyrics
          )
        } else {
          lyricsViewModel.fetch(songID: id)
        }
      }
    }
    .onChange(of: audioManager.upcomingSong?.id) { _, upcomingId in
      if showLyrics, !audioManager.isRadioMode, let id = upcomingId {
        upcomingLyricsViewModel.fetch(songID: id)
      }
    }
    .onChange(of: audioManager.isRadioMode) { _, isRadio in
      if isRadio { showLyrics = false }
    }
    .onChange(of: audioManager.showFullScreen) { _, isShown in
      if !isShown { dismiss() }
    }
    .onChange(of: audioManager.aiEnabled) { _, enabled in
      if !enabled {
        showKaraokeControls = false
      }
    }
    .onAppear {
      favorites.loadIfNeeded()
      if let id = audioManager.currentSong?.id {
        fetchCoverArtArtist(songID: id)
      }
    }
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
              currentTime: audioManager.playbackTime,
              showTranslations: showTranslatedLyrics,
              isLoading: lyricsViewModel.isLoading,
              didFail: lyricsViewModel.didFail,
              hasNoLyrics: lyricsViewModel.hasNoLyrics,
              onSeek: { time in
                let duration = audioManager.playbackDuration
                guard duration > 0 else { return }
                audioManager.seek(to: (time + 0.1) / duration)
              },
              onRetry: { lyricsViewModel.retry() }
            )
          }
          .overlay(alignment: .bottomLeading) {
            lyricsTranslationButton
              .padding(.leading, 16)
              .padding(.bottom, 32)
          }
          .overlay(alignment: .bottomTrailing) {
            if DeviceCapability.supportsKaraoke && audioManager.aiEnabled {
              KaraokeRightDock(showKaraokeControls: $showKaraokeControls)
                .padding(.trailing, 16)
                .padding(.bottom, 32)
            }
          }
          .transition(lyricsSurfaceTransition)
        } else {
          VStack(spacing: 0) {
            Spacer(minLength: 20)
            PlayerArtworkView(song: song, size: artSize, onTap: { handleCoverArtTap(song: song) })
              .contextMenu {
                songActions(song: song)
              } preview: {
                SongContextPreview(song: song)
                  .environmentObject(audioManager)
              }
            Spacer(minLength: 28)
            titleRow(song: song)
          }
          .transition(artworkSurfaceTransition)
        }
      }
      .frame(maxHeight: .infinity)
      .clipped()
      .animation(playerSurfaceAnimation, value: showLyrics)
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
          withAnimation(playerSurfaceAnimation) {
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
        AppHaptic.light.play()
        audioManager.showFullScreen = false
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Dismiss player")
      .accessibilityHint("Collapses the full-screen player.")
      .accessibilityAddTraits(.isButton)
      .accessibilityAction {
        AppHaptic.light.play()
        audioManager.showFullScreen = false
      }
  }
  @ViewBuilder
  private func lyricsHeader(song: Song) -> some View {
    Button {
      withAnimation(playerSurfaceAnimation) {
        showLyrics = false
      }
    } label: {
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
    }
    .buttonStyle(PressableButtonStyle(scale: 0.97, dim: 0.7, haptic: .selection))
    .accessibilityLabel("Hide lyrics")
    .accessibilityValue("\(song.title), \(song.displayArtist)")
    .accessibilityHint("Returns to the player controls.")
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
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Now playing")
      .accessibilityValue("\(song.title), \(song.displayArtist)")
      Spacer(minLength: 8)
      Button {
        let wasFavorite = favorites.isFavorite(song.id)
        favorites.toggle(songID: song.id)
        if wasFavorite {
          AppHaptic.selection.play()
        } else {
          AppHaptic.success.play()
        }
      } label: {
        Group {
          let isFav = favorites.isFavorite(song.id)
          if #available(iOS 17.0, *), !reduceMotion {
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
      .accessibilityLabel(
        favorites.isFavorite(song.id) ? "Remove from Favorites" : "Add to Favorites"
      )
      .accessibilityValue(song.title)
      .accessibilityHint("Updates favorites for the current song.")
    }
    .padding(.horizontal, 32)
    .contextMenu {
      songActions(song: song)
    } preview: {
      SongContextPreview(song: song)
        .environmentObject(audioManager)
    }
  }
  @ViewBuilder
  private func progressSection(song: Song) -> some View {
    let duration = max(audioManager.playbackDuration, 0)
    let elapsed = min(max(audioManager.playbackTime, 0), duration)
    AppleMusicProgressBar(
      progress: $audioManager.progress,
      isScrubbing: $audioManager.isEditingProgress,
      onSeekEnd: { fraction in audioManager.seek(to: fraction) },
      accessibilityLabel: "Playback position",
      accessibilityValueText:
        "\(formattedTime(elapsed)) elapsed, \(formattedTime(max(0, duration - elapsed))) remaining",
      accessibilityHint: "Drag or swipe up and down to seek.",
      scrubValueText: formattedTime(duration * audioManager.progress)
    )
    .padding(.horizontal, 32)
    .padding(.top, showLyrics ? 0 : 16)
    HStack {
      Text(formattedTime(elapsed))
      Spacer()
      Text(formattedTime(max(0, duration - elapsed)))
    }
    .font(.system(size: 12, weight: .medium, design: .monospaced))
    .foregroundColor(audioManager.isEditingProgress ? .primary : .secondary)
    .scaleEffect(audioManager.isEditingProgress ? 1.12 : 1.0, anchor: .center)
    .animation(
      reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85),
      value: audioManager.isEditingProgress
    )
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
      .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6, haptic: .light))
      .accessibilityLabel("Previous track")
      .accessibilityHint("Skips to the previous song.")
      Button {
        audioManager.togglePlayPause()
      } label: {
        Group {
          if #available(iOS 17.0, *), !reduceMotion {
            Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
              .contentTransition(.symbolEffect(.replace))
          } else {
            Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
          }
        }
        .font(.system(size: 48))
        .foregroundColor(.primary)
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6, haptic: .medium))
      .accessibilityLabel(audioManager.isPlaying ? "Pause" : "Play")
      .accessibilityValue(audioManager.currentSong?.title ?? "Current song")
      Button {
        audioManager.playNextOrRandom()
      } label: {
        Image(systemName: "forward.fill")
          .font(.system(size: 32))
          .foregroundColor(.primary)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6, haptic: .light))
      .accessibilityLabel("Next track")
      .accessibilityHint("Skips to the next song.")
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

  @ViewBuilder
  private func songActions(song: Song) -> some View {
    SongActionsMenuItems(song: song) {
      showAddToPlaylist = true
    }
  }

  private var playerSurfaceAnimation: Animation? {
    reduceMotion ? nil : .spring(response: 0.46, dampingFraction: 0.86, blendDuration: 0.08)
  }

  private var lyricsSurfaceTransition: AnyTransition {
    guard !reduceMotion else { return .opacity }
    return AnyTransition.asymmetric(
      insertion: .move(edge: .bottom)
        .combined(with: .opacity)
        .combined(with: .scale(scale: 0.98, anchor: .center)),
      removal: .move(edge: .top)
        .combined(with: .opacity)
        .combined(with: .scale(scale: 0.98, anchor: .center))
    )
  }

  private var artworkSurfaceTransition: AnyTransition {
    guard !reduceMotion else { return .opacity }
    return AnyTransition.asymmetric(
      insertion: .move(edge: .top)
        .combined(with: .opacity)
        .combined(with: .scale(scale: 0.985, anchor: .center)),
      removal: .move(edge: .bottom)
        .combined(with: .opacity)
        .combined(with: .scale(scale: 0.985, anchor: .center))
    )
  }

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  private var lyricsTranslationButton: some View {
    Button {
      if lyricsViewModel.hasTranslatedLyrics {
        AppHaptic.selection.play()
        showTranslatedLyrics.toggle()
      } else {
        AppHaptic.light.play()
        lyricsViewModel.requestTranslation()
      }
    } label: {
      ZStack {
        if lyricsViewModel.translationState == .translating {
          if reduceMotion {
            Circle()
              .stroke(Color.appAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
              .padding(3)
              .transition(.opacity)
          } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
              Circle()
                .trim(from: 0, to: 0.82)
                .stroke(Color.appAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(translationSpinnerDegrees(for: context.date)))
                .padding(3)
            }
            .transition(.scale(scale: 0.82).combined(with: .opacity))
          }
        }
        Image(systemName: showTranslatedLyrics ? "globe.badge.chevron.backward" : "globe")
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(showTranslatedLyrics ? .appAccent : .primary.opacity(0.85))
      }
      .frame(width: 36, height: 36)
      .modifier(GlassCircle())
    }
    .buttonStyle(PressableButtonStyle(scale: 0.9, dim: 0.7))
    .disabled(lyricsViewModel.isLoading || lyricsViewModel.hasNoLyrics)
    .accessibilityLabel(lyricsTranslationAccessibilityLabel)
    .accessibilityValue(lyricsTranslationAccessibilityValue)
    .accessibilityHint(lyricsTranslationAccessibilityHint)
    .animation(
      reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86),
      value: lyricsViewModel.translationState
    )
  }

  private func translationSpinnerDegrees(for date: Date) -> Double {
    let cycle = 1.12
    let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
    return phase * 360 - 90
  }

  private var lyricsTranslationAccessibilityLabel: String {
    if showTranslatedLyrics { return "Hide Translated Lyrics" }
    if lyricsViewModel.hasTranslatedLyrics { return "Show Translated Lyrics" }
    return "Translate Lyrics"
  }

  private var lyricsTranslationAccessibilityValue: String {
    if showTranslatedLyrics { return "On" }
    switch lyricsViewModel.translationState {
    case .idle: return "Off"
    case .translating: return "Translating"
    case .ready: return "Available"
    case .unavailable: return "Unavailable"
    case .failed: return "Failed"
    }
  }

  private var lyricsTranslationAccessibilityHint: String {
    if lyricsViewModel.hasNoLyrics { return "Lyrics are not available for this song." }
    if lyricsViewModel.hasTranslatedLyrics {
      return "Toggles translated lyrics."
    }
    return "Requests translated lyrics."
  }

  private func saveCoverArt(url: URL?) {
    guard !coverArtSaveStatus.isSaving else { return }
    guard let url else { return }
    coverArtSaveStatus = .saving
    URLSession.shared.dataTask(with: url) { data, _, error in
      DispatchQueue.main.async {
        #if canImport(UIKit)
          if let data, let image = UIImage(data: data) {
            ImageSaver.shared.save(image: image) { result in
              DispatchQueue.main.async {
                switch result {
                case .success:
                  coverArtSaveStatus = .success
                case .failure(let err):
                  coverArtSaveStatus = .failed(err.localizedDescription)
                }
                resetCoverArtSaveStatusLater()
              }
            }
            return
          }
        #endif
        coverArtSaveStatus = .failed(error?.localizedDescription ?? "Couldn't save")
        resetCoverArtSaveStatusLater()
      }
    }.resume()
  }

  private func resetCoverArtSaveStatusLater() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      coverArtSaveStatus = .idle
    }
  }

  private func handleCoverArtTap(song: Song) {
    guard DeveloperMode.shouldTriggerEasterEgg() else {
      showCoverArt = true
      return
    }
    let pageSize = 48
    let urlString =
      "\(StorageHost.api)/api/media/gallery?page=1&pageSize=\(pageSize)&search=&tag=Twins&sort=newest&hideWebM=false"
    guard let apiURL = URL(string: urlString) else {
      showCoverArt = true
      return
    }
    var request = URLRequest(url: apiURL)
    GuestIdentity.applyIfNeeded(to: &request)
    URLSession.shared.dataTask(with: request) { data, _, _ in
      DispatchQueue.main.async {
        guard let data,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let items = json["items"] as? [[String: Any]],
          !items.isEmpty
        else {
          showCoverArt = true
          return
        }
        let item = items.randomElement()!
        if let path = item["absolutePath"] as? String {
          easterEggImageURL = URL(string: StorageHost.images + path + "/quality=95")
        } else if let urlStr = item["url"] as? String {
          easterEggImageURL = URL(string: urlStr)
        }
        if let artist = item["artist"] as? [String: Any] {
          easterEggArtistName = artist["name"] as? String
          easterEggArtistLink = artist["socialLink"] as? String
        }
        showCoverArt = true
      }
    }.resume()
  }

  private func fetchCoverArtArtist(songID: String) {
    if let song = audioManager.currentSong, song.fallbackArtCredit != nil {
      let fallback = FallbackArtProvider.shared.art(for: song.id)
      coverArtArtistName = fallback?.artistName
      coverArtArtistLink = fallback?.artistLink
      return
    }
    guard let url = URL(string: "\(StorageHost.api)/api/songs/\(songID)") else { return }
    var request = URLRequest(url: url)
    GuestIdentity.applyIfNeeded(to: &request)
    URLSession.shared.dataTask(with: request) { data, _, _ in
      guard let data,
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let coverArt = json["coverArt"] as? [String: Any],
        let artist = coverArt["artist"] as? [String: Any]
      else { return }
      DispatchQueue.main.async {
        coverArtArtistName = artist["name"] as? String
        coverArtArtistLink = artist["socialLink"] as? String
      }
    }.resume()
  }
}
