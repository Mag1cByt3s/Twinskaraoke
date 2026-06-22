import SwiftUI

struct RadioQueueView: View {
  @ObservedObject var radio = RadioController.shared
  @EnvironmentObject var audioManager: AudioPlayerManager
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true

  private var currentSong: RadioNowPlaying.SongInfo? {
    radio.nowPlaying?.nowPlaying?.song
  }

  private var nextSong: RadioNowPlaying.SongInfo? {
    radio.nowPlaying?.playingNext?.song
  }

  private var history: [RadioNowPlaying.HistoryItem] {
    Array((radio.nowPlaying?.songHistory ?? []).prefix(20))
  }

  private var hasSchedule: Bool {
    currentSong != nil || nextSong != nil || !history.isEmpty
  }

  private var isLivePlaying: Bool {
    audioManager.isRadioMode && audioManager.isPlaying
  }

  private var isOnLiveStation: Bool {
    audioManager.isRadioMode && audioManager.currentSong != nil
  }

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [.appSheetGradientTop, .appSheetGradientBottom],
        startPoint: .top, endPoint: .bottom
      )
      .ignoresSafeArea()
      VStack(spacing: 0) {
        header
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 18) {
            if let current = currentSong {
              RadioQueueHero(
                song: current,
                stationName: radio.nowPlaying?.station.name ?? "Twinskaraoke Radio",
                listenerCount: radio.nowPlaying?.listeners?.unique,
                lastUpdated: radio.lastUpdated,
                isPlaying: isLivePlaying,
                reduceMotion: reduceMotion
              ) {
                playOrPauseLiveStation()
              }
              .transition(heroTransition)
            }
            stationControls
            if let next = nextSong {
              section(title: "Up Next") {
                row(song: next, isCurrent: false)
              }
            }
            if !history.isEmpty {
              section(title: "Recently Played") {
                VStack(spacing: 0) {
                  ForEach(Array(history.enumerated()), id: \.offset) { _, item in
                    row(song: item.song, isCurrent: false)
                    Rectangle()
                      .fill(Color.appDivider)
                      .frame(height: 0.5)
                      .padding(.leading, 72)
                  }
                }
              }
            }
            if !hasSchedule {
              MusicEmptyState(
                title: "Radio Schedule Unavailable",
                message: "Pull down to refresh live station metadata."
              )
              .padding(.top, 36)
              .transition(emptyStateTransition)
            }
          }
          .padding(.horizontal, 20)
          .padding(.bottom, 20)
          .animation(scheduleAnimation(response: 0.28), value: currentSong?.displayTitle)
          .animation(scheduleAnimation(response: 0.24), value: history.count)
        }
        .smoothScrolling()
        .refreshable { await radio.refresh() }
      }
    }
  }

  private var header: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(radio.nowPlaying?.station.name ?? "Radio")
          .font(.headline)
          .foregroundStyle(.primary)
        if let listeners = radio.nowPlaying?.listeners {
          Text("\(listeners.unique) listening")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer()
      Button {
        AppHaptic.light.play()
        dismiss()
      } label: {
        Label("Close", systemImage: "xmark")
          .labelStyle(.iconOnly)
          .font(.headline)
          .foregroundStyle(Color.appGlassForeground)
          .frame(width: 44, height: 44)
      }
      .modifier(GlassCircle())
      .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6))
      .accessibilityLabel("Close")
      .accessibilityHint("Dismisses the radio queue.")
    }
    .padding(.horizontal, 20)
    .padding(.top, 26)
    .padding(.bottom, 12)
  }

  private var stationControls: some View {
    HStack(spacing: 12) {
      Button {
        AppHaptic.medium.play()
        playOrPauseLiveStation()
      } label: {
        controlLabel(
          symbol: isLivePlaying ? "pause.fill" : "play.fill",
          text: isLivePlaying ? "Pause Live" : "Play Live",
          isPrimary: true
        )
      }
      .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.82))
      .accessibilityLabel(isLivePlaying ? "Pause live station" : "Play live station")
      .accessibilityValue(radio.nowPlaying?.station.name ?? "Twinskaraoke Radio")
      .accessibilityHint("Controls the live radio stream.")

      Button {
        AppHaptic.selection.play()
        Task { await radio.refresh() }
      } label: {
        controlLabel(symbol: "arrow.clockwise", text: "Refresh", isPrimary: false)
      }
      .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.82))
      .accessibilityLabel("Refresh radio metadata")
      .accessibilityHint("Updates live now, up next, and recently played.")
    }
    .transition(stationControlsTransition)
  }

  private func playOrPauseLiveStation() {
    if isOnLiveStation {
      audioManager.togglePlayPause()
    } else {
      radio.playLiveStream()
    }
  }

  private func controlLabel(symbol: String, text: String, isPrimary: Bool) -> some View {
    HStack(spacing: 7) {
      Image(systemName: symbol)
        .font(.subheadline.bold())
      Text(text)
        .font(.subheadline.bold())
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
    .foregroundStyle(isPrimary ? Color.appControlActiveForeground : Color.primary)
    .background(
      RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous)
        .fill(isPrimary ? Color.appControlActiveFill : Color.appControlInactiveFill)
    )
  }

  @ViewBuilder
  private func section<Content: View>(title: String, @ViewBuilder content: () -> Content)
    -> some View
  {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
      content()
    }
  }

  private func row(song: RadioNowPlaying.SongInfo, isCurrent: Bool) -> some View {
    RadioQueueTrackRow(
      song: song,
      isCurrent: isCurrent,
      isPlaying: isCurrent && isLivePlaying
    )
    .contentShape(Rectangle())
    .contextMenu {
      Button {
        AppHaptic.medium.play()
        radio.playLiveStream()
      } label: {
        Label("Play Live Station", systemImage: "dot.radiowaves.left.and.right")
      }

      Button {
        AppHaptic.selection.play()
        Task { await radio.refresh() }
      } label: {
        Label("Refresh Metadata", systemImage: "arrow.clockwise")
      }
    } preview: {
      RadioQueuePreview(song: song, isCurrent: isCurrent)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(isCurrent ? "Live now" : "Radio track")
    .accessibilityValue("\(song.displayTitle), \(song.displayArtist)")
    .accessibilityHint("Shows actions for the live radio station.")
    .accessibilityAction(named: "Play Live Station") {
      AppHaptic.medium.play()
      radio.playLiveStream()
    }
    .transition(rowTransition)
  }

  private func scheduleAnimation(response: Double) -> Animation? {
    reduceMotion ? nil : AppMotion.spring(response: response, dampingFraction: 0.84)
  }

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  private var heroTransition: AnyTransition {
    reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98))
  }

  private var emptyStateTransition: AnyTransition {
    reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96))
  }

  private var stationControlsTransition: AnyTransition {
    reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
  }

  private var rowTransition: AnyTransition {
    reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom))
  }
}

private struct RadioQueueHero: View {
  let song: RadioNowPlaying.SongInfo
  let stationName: String
  let listenerCount: Int?
  let lastUpdated: Date?
  let isPlaying: Bool
  let reduceMotion: Bool
  let onPlayPause: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 11) {
      ZStack(alignment: .bottomLeading) {
        RadioQueueArtwork(song: song, cornerRadius: 10)
          .frame(width: 72, height: 72)
          .amShadow(isPlaying ? AM.Shadow.heroPlaying : AM.Shadow.heroIdle)

        RadioQueueLivePill(isPlaying: isPlaying, reduceMotion: reduceMotion)
          .padding(5)
      }

      VStack(alignment: .leading, spacing: 4) {
        Text(stationName)
          .font(.caption.bold())
          .foregroundStyle(Color.appAccent)
          .textCase(.uppercase)
          .lineLimit(1)
        Text(song.displayTitle)
          .font(.headline)
          .foregroundStyle(.primary)
          .lineLimit(2)
          .minimumScaleFactor(0.84)
        Text(song.displayArtist)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)

        RadioQueueHeroStatusRow(
          listenerCount: listenerCount,
          lastUpdated: lastUpdated,
          isPlaying: isPlaying
        )
      }

      Spacer(minLength: 4)

      Button {
        AppHaptic.medium.play()
        onPlayPause()
      } label: {
        Label(isPlaying ? "Pause live station" : "Play live station", systemImage: isPlaying ? "pause.fill" : "play.fill")
          .labelStyle(.iconOnly)
          .font(.headline.bold())
          .foregroundStyle(Color.appControlActiveForeground)
          .frame(width: 44, height: 44)
          .background(Color.appControlActiveFill, in: Circle())
          .offset(x: isPlaying ? 0 : 1)
      }
      .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.76))
      .accessibilityLabel(isPlaying ? "Pause live station" : "Play live station")
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(.regularMaterial)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(Color.appDivider.opacity(0.8), lineWidth: 0.5)
    )
    .accessibilityElement(children: .combine)
    .accessibilityLabel(isPlaying ? "Live now, on air" : "Live now")
    .accessibilityValue("\(song.displayTitle), \(song.displayArtist)")
  }
}

private struct RadioQueueLivePill: View {
  let isPlaying: Bool
  let reduceMotion: Bool

  var body: some View {
    HStack(spacing: 5) {
      ZStack {
        if isPlaying && !reduceMotion {

          Circle()
            .fill(Color.white.opacity(0.28))
            .frame(width: 11, height: 11)
        }
        Circle()
          .fill(.white)
          .frame(width: 5, height: 5)
      }
      .frame(width: 11, height: 11)

      Text(isPlaying ? "ON AIR" : "LIVE")
        .font(.caption.bold())
        .foregroundStyle(.white)
    }
    .padding(.horizontal, 7)
    .padding(.vertical, 4)
    .background(Capsule().fill(Color.appAccent))
    .accessibilityHidden(true)
  }
}

private struct RadioQueueHeroStatusRow: View {
  let listenerCount: Int?
  let lastUpdated: Date?
  let isPlaying: Bool

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 7) {
        statusItems
      }
      VStack(alignment: .leading, spacing: 2) {
        statusItems
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private var statusItems: some View {
    Label(isPlaying ? "Broadcasting" : "Ready", systemImage: isPlaying ? "waveform" : "antenna.radiowaves.left.and.right")
      .lineLimit(1)
    if let listenerCount {
      Label(listenerCount == 1 ? "1 listener" : "\(listenerCount) listeners", systemImage: "person.2.fill")
        .lineLimit(1)
    }
    if let lastUpdated {
      Label("Updated \(lastUpdated.formatted(.relative(presentation: .named)))", systemImage: "clock")
        .lineLimit(1)
    }
  }
}

private struct RadioQueueTrackRow: View {
  let song: RadioNowPlaying.SongInfo
  let isCurrent: Bool
  let isPlaying: Bool

  var body: some View {
    HStack(spacing: 12) {
      RadioQueueArtwork(song: song, cornerRadius: 7)
        .frame(width: 54, height: 54)
        .overlay(alignment: .topLeading) {
          if isCurrent {
            Text("LIVE")
              .font(.caption.bold())
              .foregroundStyle(.white)
              .padding(.horizontal, 5)
              .padding(.vertical, 2)
              .background(Capsule().fill(Color.appAccent))
              .padding(5)
          }
        }
      VStack(alignment: .leading, spacing: 3) {
        Text(song.displayTitle)
          .font(.subheadline.bold())
          .foregroundStyle(isCurrent ? Color.appAccent : Color.primary)
          .lineLimit(1)
        Text(song.displayArtist)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        if isCurrent {
          Text(isPlaying ? "On air now" : "Live station")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      Spacer()
      if isCurrent {

        EqualizerBars(isAnimating: false)
          .frame(width: 18, height: 18)
          .foregroundStyle(Color.appAccent)
      }
    }
    .padding(.vertical, 7)
    .accessibilityElement(children: .combine)
  }
}

private struct RadioQueuePreview: View {
  let song: RadioNowPlaying.SongInfo
  let isCurrent: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      RadioQueueArtwork(song: song, cornerRadius: 10)
        .frame(width: 220, height: 220)
      VStack(alignment: .leading, spacing: 3) {
        if isCurrent {
          Text("Live Now")
            .font(.caption.bold())
            .foregroundStyle(Color.appAccent)
            .textCase(.uppercase)
        }
        Text(song.displayTitle)
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

private struct RadioQueueArtwork: View {
  let song: RadioNowPlaying.SongInfo
  let cornerRadius: CGFloat

  var body: some View {
    Group {
      if let url = song.artworkURL {
        RemoteArtworkImage(url: url, cornerRadius: cornerRadius)
      } else {
        LinearGradient(
          colors: [Color.appAccent.opacity(0.85), Color.purple.opacity(0.85)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        .overlay {
          Image(systemName: "dot.radiowaves.left.and.right")
            .font(.title3.bold())
            .foregroundStyle(.white.secondary)
        }
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }
}

private extension RadioNowPlaying.SongInfo {
  var displayTitle: String {
    title ?? text ?? "Live Radio"
  }

  var displayArtist: String {
    artist ?? "Twinskaraoke Radio"
  }

  var artworkURL: URL? {
    art.flatMap { URL(string: $0) }
  }
}
