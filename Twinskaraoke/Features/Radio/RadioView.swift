import SwiftUI

struct RadioView: View {
  @StateObject private var radio = RadioController.shared
  @EnvironmentObject var audioManager: AudioPlayerManager
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var showingRadioSchedule = false
  var body: some View {
    NavigationStack {
      ScrollView {
        Group {
          if radio.nowPlaying == nil && radio.refreshErrorMessage != nil && !radio.isRefreshing {
            RadioUnavailableView(
              message: radio.refreshErrorMessage ?? "Radio metadata is temporarily unavailable.",
              isRefreshing: radio.isRefreshing
            ) {
              Task { await retryRadioRefresh() }
            }
            .padding(.top, 36)
            .transition(unavailableTransition)
          } else if radio.nowPlaying == nil {
            RadioSkeletonView()
              .transition(.opacity)
          } else {
            radioOverview
            .transition(.opacity)
          }
        }
        .animation(radioContentAnimation, value: radio.nowPlaying == nil)
        .padding(.top, AM.Spacing.l)
        .padding(.bottom, AM.Spacing.l)
      }
      .tabBarScrollInset()
      .musicScreenBackground()
      .navigationTitle("Radio")
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          HStack(spacing: 12) {
            ToolbarIconButton(
              systemImage: "list.bullet",
              accessibilityLabel: "Live Schedule"
            ) {
              showLiveSchedule()
            }
            .accessibilityHint("Shows live now, up next, and recently played songs.")

            AccountToolbarButton()
          }
        }
      }
      .refreshable {
        await retryRadioRefresh()
      }
      .onAppear { radio.start() }
      .sheet(isPresented: $showingRadioSchedule) {
        RadioQueueView()
          .environmentObject(audioManager)
          .presentationDetents([.medium, .large])
          .presentationDragIndicator(.visible)
      }
    }
  }

  private func retryRadioRefresh() async {
    AppHaptic.selection.play()
    await radio.refresh()
    if radio.refreshErrorMessage != nil {
      AppHaptic.error.play()
    }
  }

  private func playOrPauseLiveStation() {
    if audioManager.isRadioMode && audioManager.currentSong != nil {
      audioManager.togglePlayPause()
    } else {
      radio.playLiveStream()
    }
  }

  private func showLiveSchedule() {
    AppHaptic.selection.play()
    showingRadioSchedule = true
  }

  private var radioContentAnimation: Animation? {
    reduceMotion ? nil : .easeInOut(duration: 0.4)
  }

  private var unavailableTransition: AnyTransition {
    reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97))
  }

  private var refreshBannerTransition: AnyTransition {
    reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
  }

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  private var usesWideOverview: Bool {
    horizontalSizeClass == .regular
  }

  @ViewBuilder
  private var radioOverview: some View {
    if usesWideOverview {
      wideRadioOverview
    } else {
      compactRadioOverview
    }
  }

  private var compactRadioOverview: some View {
    VStack(spacing: AM.Spacing.shelfSpacing) {
      refreshBanner(horizontalPadding: AM.Spacing.screenMargin)
      stationCard()
      if let history = radio.nowPlaying?.songHistory, !history.isEmpty {
        historySection(history: history)
      }
    }
  }

  private var wideRadioOverview: some View {
    VStack(alignment: .leading, spacing: AM.Spacing.xxl) {
      refreshBanner(horizontalPadding: 0)

      HStack(alignment: .top, spacing: AM.Spacing.xxl) {
        stationCard(horizontalPadding: 0)
          .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)

        VStack(alignment: .leading, spacing: AM.Spacing.xxl) {
          if let history = radio.nowPlaying?.songHistory, !history.isEmpty {
            historySection(history: history, horizontalPadding: 0)
          }
        }
        .frame(minWidth: 300, idealWidth: 360, maxWidth: 420, alignment: .topLeading)
      }
    }
    .frame(maxWidth: 1120, alignment: .topLeading)
    .frame(maxWidth: .infinity, alignment: .top)
    .padding(.horizontal, AM.Spacing.screenMargin)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("Radio.WideOverview")
  }

  @ViewBuilder
  private func refreshBanner(horizontalPadding: CGFloat) -> some View {
    if let message = radio.refreshErrorMessage, !radio.isRefreshing {
      RadioRefreshBanner(message: message) {
        Task { await retryRadioRefresh() }
      }
      .padding(.horizontal, horizontalPadding)
      .transition(refreshBannerTransition)
    }
  }

  @ViewBuilder
  private var radioActions: some View {
    Button {
      AppHaptic.medium.play()
      radio.playLiveStream()
    } label: {
      Label("Play Live Station", systemImage: "dot.radiowaves.left.and.right")
    }

    Button {
      showLiveSchedule()
    } label: {
      Label("Show Live Schedule", systemImage: "list.bullet")
    }

    Button {
      Task { await retryRadioRefresh() }
    } label: {
      Label("Refresh Metadata", systemImage: "arrow.clockwise")
    }
  }

  @ViewBuilder
  private func stationCard(horizontalPadding: CGFloat = AM.Spacing.screenMargin) -> some View {
    let np = radio.nowPlaying
    let song = np?.nowPlaying?.song
    let isLivePlaying = audioManager.isRadioMode && audioManager.isPlaying
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Featured Episode")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(.secondary)
          .textCase(.uppercase)
          .accessibilityIdentifier("Radio.FeaturedEpisode.Label")
        Text(song?.displayTitle ?? np?.station.name ?? "Twinskaraoke Radio")
          .font(.system(size: 30, weight: .semibold))
          .foregroundStyle(.primary)
          .lineLimit(2)
          .accessibilityIdentifier("Radio.FeaturedEpisode.Title")
      }
      .padding(.horizontal, horizontalPadding)

      ZStack(alignment: .bottomLeading) {
        Group {
          if let art = song?.art, let url = URL(string: art) {
            LoadingImage(url: url, cornerRadius: AM.Radius.hero, contentMode: .fill)
          } else {
            artPlaceholder
          }
        }
        .frame(maxWidth: .infinity, minHeight: 236, maxHeight: 236)
        .clipShape(RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous))

        LinearGradient(
          colors: [.black.opacity(0.0), .black.opacity(0.52)],
          startPoint: .center,
          endPoint: .bottom
        )
        .clipShape(RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous))

        VStack(alignment: .leading, spacing: 8) {
          RadioLiveBadge(isActive: isLivePlaying, reduceMotion: reduceMotion)
          Text(song?.displayArtist ?? np?.station.description ?? "Live radio")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
            .lineLimit(1)
        }
        .padding(16)

        Button {
          AppHaptic.medium.play()
          playOrPauseLiveStation()
        } label: {
          ZStack {
            Circle()
              .fill(.white)
              .frame(width: 48, height: 48)
            if audioManager.isBuffering && audioManager.isRadioMode && !audioManager.isPlaying {
              LoadingIndicator(size: 28)
            } else {
              Image(systemName: isLivePlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.black)
                .offset(x: isLivePlaying ? 0 : 2)
            }
          }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .buttonStyle(PressableButtonStyle(scale: 0.9, dim: 0.85))
        .accessibilityLabel(isLivePlaying ? "Pause live station" : "Play live station")
        .accessibilityValue(song?.displayTitle ?? np?.station.name ?? "Twinskaraoke Radio")
        .accessibilityHint("Controls the live radio stream.")
      }
      .padding(.horizontal, horizontalPadding)
      .amShadow(
        audioManager.isPlaying && audioManager.isRadioMode
          ? AM.Shadow.heroPlaying : AM.Shadow.heroIdle
      )

      RadioLiveStatusStrip(
        isPlaying: isLivePlaying,
        listenerCount: np?.listeners?.unique,
        lastUpdated: radio.lastUpdated)
      .padding(.horizontal, horizontalPadding)

      if let next = np?.playingNext?.song {
        Button {
          showLiveSchedule()
        } label: {
          HStack(spacing: 12) {
            if let art = next.art, let url = URL(string: art) {
              LoadingImage(url: url, cornerRadius: 6)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
              RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 48, height: 48)
            }
            VStack(alignment: .leading, spacing: 2) {
              Text("Up Next")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
              Text(next.title ?? next.text ?? "")
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
              Text(next.artist ?? "")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
              .font(.system(size: 13, weight: .semibold))
              .foregroundColor(.secondary)
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
          .background(
            Color.appControlInactiveFill,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
          )
        }
        .padding(.horizontal, 16)
        .buttonStyle(PressableButtonStyle(scale: 0.98, dim: 0.78))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Up Next")
        .accessibilityValue("\(next.displayTitle), \(next.displayArtist)")
        .accessibilityHint("Shows the live radio schedule.")
        .padding(.horizontal, horizontalPadding)
        .contextMenu {
          radioActions
        } preview: {
          RadioSongContextPreview(song: next)
        }
      }
    }
    .contextMenu {
      radioActions
    } preview: {
      RadioStationContextPreview(
        title: song?.displayTitle ?? np?.station.name ?? "Live Radio",
        subtitle: song?.displayArtist ?? np?.station.description ?? "Twinskaraoke Radio",
        artworkURL: song?.artworkURL
      )
    }
  }
  @ViewBuilder
  private var artPlaceholder: some View {
    LinearGradient(
      colors: [Color.appAccent, Color.purple],
      startPoint: .topLeading, endPoint: .bottomTrailing
    )
    .overlay(
      Image(systemName: "dot.radiowaves.left.and.right")
        .font(.system(size: 64, weight: .medium))
        .foregroundColor(.white.opacity(0.85))
    )
  }
  private func historySection(
    history: [RadioNowPlaying.HistoryItem],
    horizontalPadding: CGFloat = AM.Spacing.screenMargin
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      RadioSectionHeader("New & Recent")
        .padding(.horizontal, horizontalPadding)
      LazyVStack(spacing: 0) {
        ForEach(Array(history.prefix(10).enumerated()), id: \.offset) { _, item in
          RadioHistoryRow(song: item.song)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Recently played")
            .accessibilityValue("\(item.song.displayTitle), \(item.song.displayArtist)")
            .contextMenu {
              radioActions
            } preview: {
              RadioSongContextPreview(song: item.song)
            }
          Divider().padding(.leading, 76)
        }
      }
    }
    .accessibilityIdentifier("Radio.HistorySection")
  }
  private func hostedStationsSection(
    horizontalPadding: CGFloat = AM.Spacing.screenMargin
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      RadioSectionHeader("Hosted Stations")
        .padding(.horizontal, horizontalPadding)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 14) {
          ForEach(RadioStationTile.hosted) { tile in
            Button {
              AppHaptic.medium.play()
              radio.playLiveStream()
            } label: {
              RadioStationTileView(tile: tile)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.82))
            .accessibilityLabel("Play \(tile.name)")
            .accessibilityValue(tile.tagline)
            .accessibilityHint("Starts the live radio station.")
            .contextMenu {
              radioActions
            }
          }
        }
        .padding(.horizontal, horizontalPadding)
      }
    }
    .accessibilityIdentifier("Radio.HostedStationsSection")
  }
  private func featuredShowsSection(
    horizontalPadding: CGFloat = AM.Spacing.screenMargin
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      RadioSectionHeader("Featured Shows")
        .padding(.horizontal, horizontalPadding)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 14) {
          ForEach(RadioShowTile.featured) { tile in
            Button {
              AppHaptic.selection.play()
              radio.playLiveStream()
            } label: {
              RadioShowTileView(tile: tile)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.82))
            .accessibilityLabel("Play \(tile.title)")
            .accessibilityValue(tile.host)
            .accessibilityHint("Starts the live radio station.")
            .contextMenu {
              radioActions
            } preview: {
              RadioStationContextPreview(
                title: tile.title,
                subtitle: tile.host,
                artworkURL: nil
              )
            }
          }
        }
        .padding(.horizontal, horizontalPadding)
      }
    }
    .accessibilityIdentifier("Radio.FeaturedShowsSection")
  }
}

private struct RadioSectionHeader: View {
  let title: String

  init(_ title: String) {
    self.title = title
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: AM.Spacing.s) {
      Text(title)
        .font(AM.Font.sectionHeader)
        .foregroundColor(.primary)
      Spacer()
    }
    .padding(.top, 2)
  }
}

private struct RadioLiveBadge: View {
  let isActive: Bool
  let reduceMotion: Bool

  var body: some View {
    HStack(spacing: 5) {
      ZStack {
        if isActive && !reduceMotion {
          TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
            Circle()
              .fill(.white.opacity(livePulseOpacity(for: context.date)))
              .scaleEffect(livePulseScale(for: context.date))
          }
          .frame(width: 12, height: 12)
          .accessibilityHidden(true)
        }
        Circle()
          .fill(.white)
          .frame(width: 5, height: 5)
      }
      .frame(width: 12, height: 12)

      Text("LIVE")
        .font(.system(size: 10, weight: .heavy))
        .foregroundColor(.white)
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 5)
    .background(Capsule().fill(Color.appAccent))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(isActive ? "Live and playing" : "Live")
  }

  private func livePulseScale(for date: Date) -> CGFloat {
    let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
    return 0.72 + CGFloat(phase) * 1.08
  }

  private func livePulseOpacity(for date: Date) -> Double {
    let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
    return max(0, 0.34 * (1 - phase))
  }
}

private struct RadioLiveStatusStrip: View {
  let isPlaying: Bool
  let listenerCount: Int?
  let lastUpdated: Date?

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) {
        statusPills
      }
      VStack(spacing: 6) {
        statusPills
      }
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private var statusPills: some View {
    RadioStatusPill(
      systemImage: isPlaying ? "speaker.wave.2.fill" : "dot.radiowaves.left.and.right",
      text: isPlaying ? "On Air" : "Live Ready",
      tint: .appAccent)
    if let listenerCount {
      RadioStatusPill(
        systemImage: "person.2.fill",
        text: listenerCount == 1 ? "1 listening" : "\(listenerCount) listening",
        tint: .secondary)
    }
    if let lastUpdated {
      RadioStatusPill(
        systemImage: "clock",
        text: "Updated \(lastUpdated.formatted(.relative(presentation: .named)))",
        tint: .secondary)
    }
  }
}

private struct RadioStatusPill: View {
  let systemImage: String
  let text: String
  let tint: Color

  var body: some View {
    Label(text, systemImage: systemImage)
      .font(.system(size: 11, weight: .semibold))
      .lineLimit(1)
      .minimumScaleFactor(0.78)
      .foregroundColor(tint)
      .padding(.horizontal, 9)
      .frame(height: 26)
      .background(
        Capsule()
          .fill(Color.appControlInactiveFill)
      )
  }
}

private struct RadioRefreshBanner: View {
  let message: String
  let onRetry: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(.appAccent)
      Text(message)
        .font(.system(size: 13, weight: .medium))
        .foregroundColor(.primary)
        .lineLimit(2)
      Spacer(minLength: 8)
      Button {
        onRetry()
      } label: {
        Image(systemName: "arrow.clockwise")
          .font(.system(size: 13, weight: .bold))
          .foregroundColor(.appAccent)
          .frame(width: 30, height: 30)
          .background(Color.appAccent.opacity(0.12), in: Circle())
      }
      .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.7))
      .accessibilityLabel("Retry")
      .accessibilityHint("Refreshes radio metadata.")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(
      Color.appControlInactiveFill,
      in: RoundedRectangle(cornerRadius: 12, style: .continuous)
    )
  }
}

private struct RadioUnavailableView: View {
  let message: String
  let isRefreshing: Bool
  let onRetry: () -> Void

  var body: some View {
    VStack(spacing: 18) {
      MusicEmptyState(
        systemImage: "dot.radiowaves.left.and.right",
        title: "Radio Unavailable",
        message: message
      )
      Button {
        onRetry()
      } label: {
        HStack(spacing: 8) {
          if isRefreshing {
            LoadingIndicator(size: 18)
          } else {
            Image(systemName: "arrow.clockwise")
              .font(.system(size: 15, weight: .semibold))
          }
          Text(isRefreshing ? "Refreshing" : "Try Again")
            .font(.system(size: 15, weight: .semibold))
        }
        .foregroundColor(.appControlActiveForeground)
        .padding(.horizontal, 18)
        .frame(height: 42)
        .background(Color.appControlActiveFill, in: Capsule())
      }
      .buttonStyle(PressableButtonStyle(scale: 0.94, dim: 0.78))
      .disabled(isRefreshing)
      .accessibilityLabel(isRefreshing ? "Refreshing radio metadata" : "Try again")
      .accessibilityHint("Refreshes the live radio station metadata.")
    }
    .frame(maxWidth: .infinity, minHeight: 420)
  }
}

private struct RadioStationContextPreview: View {
  let title: String
  let subtitle: String
  let artworkURL: URL?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Group {
        if let artworkURL {
          LoadingImage(url: artworkURL, cornerRadius: 10)
        } else {
          LinearGradient(
            colors: [Color.appAccent.opacity(0.85), Color.purple.opacity(0.85)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
          .overlay {
            Image(systemName: "dot.radiowaves.left.and.right")
              .font(.system(size: 58, weight: .semibold))
              .foregroundColor(.white.opacity(0.9))
          }
        }
      }
      .frame(width: 220, height: 220)
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      VStack(alignment: .leading, spacing: 3) {
        Text("Live Station")
          .font(.system(size: 12, weight: .bold))
          .foregroundColor(.appAccent)
          .textCase(.uppercase)
        Text(title)
          .font(.system(size: 17, weight: .semibold))
          .foregroundColor(.primary)
          .lineLimit(2)
        Text(subtitle)
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

private struct RadioSongContextPreview: View {
  let song: RadioNowPlaying.SongInfo

  var body: some View {
    RadioStationContextPreview(
      title: song.displayTitle,
      subtitle: song.displayArtist,
      artworkURL: song.artworkURL
    )
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

private struct RadioStationTile: Identifiable {
  let id = UUID()
  let name: String
  let tagline: String
  let gradient: [Color]
  static let hosted: [RadioStationTile] = [
    .init(
      name: "Twinskaraoke 1", tagline: "Worldwide",
      gradient: [
        Color(red: 0.95, green: 0.20, blue: 0.30), Color(red: 0.45, green: 0.05, blue: 0.10),
      ]),
    .init(
      name: "Twinskaraoke Hits", tagline: "Decades of hits",
      gradient: [
        Color(red: 0.20, green: 0.45, blue: 0.95), Color(red: 0.05, green: 0.15, blue: 0.45),
      ]),
    .init(
      name: "Twinskaraoke Country", tagline: "Today's country",
      gradient: [
        Color(red: 0.85, green: 0.55, blue: 0.20), Color(red: 0.40, green: 0.20, blue: 0.05),
      ]),
  ]
}

private struct RadioStationTileView: View {
  let tile: RadioStationTile
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ZStack(alignment: .topLeading) {
        LinearGradient(colors: tile.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
        HStack(spacing: 4) {
          Circle().fill(.white).frame(width: 5, height: 5)
          Text("LIVE")
            .font(.system(size: 9, weight: .heavy))
            .foregroundColor(.white)
            .tracking(0.6)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.appAccent))
        .padding(8)
      }
      .frame(width: 200, height: 200)
      .clipShape(RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
      .amShadow(AM.Shadow.card)
      Text(tile.name)
        .font(.system(size: 15, weight: .semibold))
        .lineLimit(1)
      Text(tile.tagline)
        .font(.system(size: 12))
        .foregroundColor(.secondary)
        .lineLimit(1)
    }
    .frame(width: 200)
    .accessibilityElement(children: .combine)
  }
}

private struct RadioShowTile: Identifiable {
  let id = UUID()
  let title: String
  let host: String
  let gradient: [Color]
  static let featured: [RadioShowTile] = [
    .init(
      title: "The Zane Lowe Show", host: "Zane Lowe",
      gradient: [
        Color(red: 0.55, green: 0.10, blue: 0.55), Color(red: 0.20, green: 0.05, blue: 0.30),
      ]),
    .init(
      title: "Ebro Darden", host: "Hip-Hop",
      gradient: [
        Color(red: 0.10, green: 0.55, blue: 0.55), Color(red: 0.05, green: 0.25, blue: 0.30),
      ]),
    .init(
      title: "Travis Mills", host: "The Pop Show",
      gradient: [
        Color(red: 0.95, green: 0.40, blue: 0.65), Color(red: 0.45, green: 0.10, blue: 0.30),
      ]),
    .init(
      title: "Kelleigh Bannen", host: "Today's Country",
      gradient: [
        Color(red: 0.85, green: 0.65, blue: 0.30), Color(red: 0.45, green: 0.30, blue: 0.05),
      ]),
  ]
}

private struct RadioShowTileView: View {
  let tile: RadioShowTile
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ZStack(alignment: .bottomLeading) {
        LinearGradient(colors: tile.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
        Image(systemName: "mic.fill")
          .font(.system(size: 26, weight: .medium))
          .foregroundColor(.white.opacity(0.85))
          .padding(12)
      }
      .frame(width: 160, height: 160)
      .clipShape(RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
      .amShadow(AM.Shadow.card)
      Text(tile.title)
        .font(.system(size: 14, weight: .semibold))
        .lineLimit(1)
      Text(tile.host)
        .font(.system(size: 12))
        .foregroundColor(.secondary)
        .lineLimit(1)
    }
    .frame(width: 160)
    .accessibilityElement(children: .combine)
  }
}

private struct RadioHistoryRow: View {
  let song: RadioNowPlaying.SongInfo
  var body: some View {
    HStack(spacing: 12) {
      if let art = song.art, let url = URL(string: art) {
        LoadingImage(url: url, cornerRadius: 6)
          .frame(width: 48, height: 48)
          .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
      } else {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(Color.secondary.opacity(0.15))
          .frame(width: 48, height: 48)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(song.title ?? song.text ?? "")
          .font(.system(size: 15, weight: .semibold))
          .lineLimit(1)
        Text(song.artist ?? "")
          .font(.system(size: 13))
          .foregroundColor(.secondary)
          .lineLimit(1)
      }
      Spacer()
    }
  }
}

struct RadioSkeletonView: View {
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var pulse = false

  var body: some View {
    VStack(spacing: AM.Spacing.shelfSpacing) {
      stationCardSkeleton
      historySkeleton
    }
    .opacity(reduceMotion ? 1.0 : (pulse ? 0.58 : 1.0))
    .onAppear {
      guard !reduceMotion else {
        pulse = false
        return
      }
      withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
        pulse = true
      }
    }
    .onChange(of: reduceMotion) { _, newValue in
      if newValue {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
          pulse = false
        }
      } else {
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
          pulse = true
        }
      }
    }
  }

  private var stationCardSkeleton: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
          .fill(Color.appPlaceholderSecondary)
          .frame(width: 118, height: 11)
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(Color.appPlaceholderSecondary)
          .frame(width: 220, height: 30)
      }
      .padding(.horizontal, AM.Spacing.screenMargin)

      ZStack(alignment: .bottomLeading) {
        RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous)
          .fill(Color.appPlaceholderPrimary)
          .frame(maxWidth: .infinity, minHeight: 236, maxHeight: 236)

        VStack(alignment: .leading, spacing: 10) {
          RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.appPlaceholderTertiary)
            .frame(width: 58, height: 20)

          HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous)
              .fill(Color.appPlaceholderQuaternary)
              .frame(width: 44, height: 44)
            RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous)
              .fill(Color.appPlaceholderQuaternary)
              .frame(width: 44, height: 44)
            Spacer()
          }
        }
        .padding(16)
      }
      .clipShape(RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous))
      .padding(.horizontal, AM.Spacing.screenMargin)
    }
  }

  private var historySkeleton: some View {
    VStack(alignment: .leading, spacing: AM.Spacing.s) {
      RoundedRectangle(cornerRadius: 4, style: .continuous)
        .fill(Color.appPlaceholderSecondary)
        .frame(width: 138, height: 18)
        .padding(.horizontal, AM.Spacing.screenMargin)

      VStack(spacing: 0) {
        ForEach(0..<3, id: \.self) { _ in
          HStack(spacing: AM.Spacing.m) {
            RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous)
              .fill(Color.appPlaceholderPrimary)
              .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 6) {
              RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.appPlaceholderSecondary)
                .frame(width: 180, height: 14)
              RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.appPlaceholderPrimary)
                .frame(width: 132, height: 12)
            }
            Spacer(minLength: 0)
          }
          .padding(.horizontal, AM.Spacing.screenMargin)
          .padding(.vertical, 3)
          Divider().padding(.leading, AM.Spacing.screenMargin + 48 + AM.Spacing.m)
        }
      }
    }
  }

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }
}
