import Combine
import SwiftUI

struct HomeView: View {
  @StateObject var viewModel = HomeViewModel()
  @StateObject private var recentlyPlayed = RecentlyPlayedStore.shared
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true

  private var loadingAnimation: Animation? {
    reduceMotion ? nil : AppMotion.spring(response: 0.38, dampingFraction: 0.84)
  }

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  var body: some View {
    NavigationStack {
      GeometryReader { proxy in
        ScrollView {
          Group {
            if viewModel.isLoading {
              HomeSkeletonView()
                .transition(.opacity)
            } else {
              homeOverview(availableWidth: proxy.size.width)
                .transition(.opacity)
            }
          }
          .animation(loadingAnimation, value: viewModel.isLoading)
          .padding(.top, AM.Spacing.l)
          .padding(.bottom, AM.Spacing.l)
        }
        .smoothScrolling()
        .tabBarScrollInset()
        .musicScreenBackground()
      }
      .navigationTitle("Home")
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          AccountToolbarButton()
        }
      }
      .refreshable { viewModel.fetchHomeData(force: true) }
    }
  }

  @ViewBuilder
  private func homeOverview(availableWidth: CGFloat) -> some View {
    if AM.Layout.usesWideCanvas(
      horizontalSizeClass: horizontalSizeClass,
      availableWidth: availableWidth
    ) {
      wideHomeOverview
    } else {
      compactHomeOverview
    }
  }

  private var compactHomeOverview: some View {
    VStack(alignment: .leading, spacing: 18) {
      topPicksShelf()

      if !recentlyPlayed.playlists.isEmpty {
        PlaylistCarousel(title: "Recently Played", playlists: recentlyPlayed.playlists)
      }

      if !viewModel.suggestions.isEmpty {
        HomeSongSection(title: "Made for You", songs: viewModel.suggestions)
      }

      latestSingleSection()

      if !viewModel.newReleases.isEmpty {
        HomeSongSection(title: "New Releases", songs: viewModel.newReleases)
      }

      if !viewModel.trending.isEmpty {
        HomeSongSection(title: "More to Explore", songs: viewModel.trending)
      }
    }
  }

  private var wideHomeOverview: some View {
    VStack(alignment: .leading, spacing: AM.Spacing.xxl) {
      WideHomeHero(
        song: homeHeroSong,
        context: homeHeroContext,
        playlist: viewModel.recentPlaylists.first,
        secondarySong: homeSecondarySong,
        secondaryContext: viewModel.suggestions.isEmpty ? viewModel.trending : viewModel.suggestions
      )

      HStack(alignment: .top, spacing: AM.Spacing.xxl) {
        VStack(alignment: .leading, spacing: AM.Spacing.xxl) {
          topPicksShelf(horizontalPadding: 0)

          if !recentlyPlayed.playlists.isEmpty {
            PlaylistCarousel(
              title: "Recently Played",
              playlists: recentlyPlayed.playlists,
              horizontalPadding: 0
            )
          }

          if !viewModel.suggestions.isEmpty {
            HomeSongSection(title: "Made for You", songs: viewModel.suggestions, horizontalPadding: 0)
          }
        }
        .frame(minWidth: 520, maxWidth: .infinity, alignment: .topLeading)
        .layoutPriority(1)

        VStack(alignment: .leading, spacing: AM.Spacing.xxl) {
          latestSingleSection(horizontalPadding: 0)

          if !viewModel.newReleases.isEmpty {
            WideSongListPanel(title: "New Releases", songs: Array(viewModel.newReleases.prefix(6)))
          }

          if !viewModel.trending.isEmpty {
            WideSongListPanel(title: "More to Explore", songs: Array(viewModel.trending.prefix(6)))
          }
        }
        .frame(
          width: AM.Layout.wideInspectorWidth,
          alignment: .topLeading
        )
      }
    }
    .frame(maxWidth: AM.Layout.wideContentMaxWidth, alignment: .topLeading)
    .frame(maxWidth: .infinity, alignment: .top)
    .padding(.horizontal, AM.Spacing.screenMargin)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("Home.WideOverview")
  }

  private var homeHeroSong: Song? {
    viewModel.latestSingle ?? viewModel.suggestions.first ?? viewModel.newReleases.first ?? viewModel.trending.first
  }

  private var homeSecondarySong: Song? {
    viewModel.suggestions.dropFirst().first ?? viewModel.newReleases.dropFirst().first ?? viewModel.trending.first
  }

  private var homeHeroContext: [Song] {
    if !viewModel.latestSingleContext.isEmpty { return viewModel.latestSingleContext }
    if !viewModel.suggestions.isEmpty { return viewModel.suggestions }
    if !viewModel.newReleases.isEmpty { return viewModel.newReleases }
    return viewModel.trending
  }

  @ViewBuilder
  private func topPicksShelf(horizontalPadding: CGFloat = AM.Spacing.screenMargin) -> some View {
    if !viewModel.recentPlaylists.isEmpty {
      PlaylistCarousel(
        title: "Top Picks for You",
        playlists: viewModel.recentPlaylists,
        isLoadingMore: viewModel.isLoadingMoreTopPicks,
        onAppearItem: { viewModel.loadMoreTopPicksIfNeeded(current: $0) },
        apiURL: { startIndex, pageSize in
          viewModel.topPicksURLForList(startIndex: startIndex, pageSize: pageSize)
        },
        horizontalPadding: horizontalPadding
      )
    }
  }

  @ViewBuilder
  private func latestSingleSection(horizontalPadding: CGFloat = AM.Spacing.screenMargin) -> some View {
    if let latestSingle = viewModel.latestSingle {
      LatestSingleSection(
        song: latestSingle,
        context: viewModel.latestSingleContext.isEmpty ? [latestSingle] : viewModel.latestSingleContext,
        horizontalPadding: horizontalPadding
      )
    }
  }
}

struct NewView: View {
  @StateObject var viewModel = HomeViewModel()
  @StateObject private var recentlyPlayed = RecentlyPlayedStore.shared
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  private var loadingAnimation: Animation? {
    reduceMotion ? nil : AppMotion.spring(response: 0.38, dampingFraction: 0.84)
  }

  var body: some View {
    NavigationStack {
      GeometryReader { proxy in
        ScrollView {
          Group {
            if viewModel.isLoading {
              NewSkeletonView()
                .transition(.opacity)
            } else {
              newOverview(availableWidth: proxy.size.width)
                .transition(.opacity)
            }
          }
          .animation(loadingAnimation, value: viewModel.isLoading)
          .padding(.top, AM.Spacing.m)
          .padding(.bottom, AM.Spacing.l)
        }
        .smoothScrolling()
        .tabBarScrollInset()
        .musicScreenBackground()
      }
      .navigationTitle("New")
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          AccountToolbarButton()
        }
      }
      .refreshable { viewModel.fetchHomeData(force: true) }
    }
  }

  @ViewBuilder
  private func newOverview(availableWidth: CGFloat) -> some View {
    if AM.Layout.usesWideCanvas(
      horizontalSizeClass: horizontalSizeClass,
      availableWidth: availableWidth
    ) {
      wideNewOverview
    } else {
      compactNewOverview
    }
  }

  private var compactNewOverview: some View {
    VStack(alignment: .leading, spacing: 18) {
      if !viewModel.newReleases.isEmpty {
        NewFeaturedRail(
          primary: viewModel.newReleases.first,
          secondary: viewModel.trending.first,
          songs: viewModel.newReleases
        )
      }

      if !viewModel.newReleases.isEmpty {
        NewSongRail(title: "Up Next", songs: Array(viewModel.newReleases.prefix(8)))
      }

      if !viewModel.trending.isEmpty {
        NewSongListPreview(title: "Best New Songs", songs: Array(viewModel.trending.prefix(5)))
      }

      if !viewModel.recentPlaylists.isEmpty {
        NewPlaylistRail(title: "New This Week", playlists: viewModel.recentPlaylists)
      }

      if !viewModel.newReleases.isEmpty {
        NewSongRail(title: "New Releases", songs: viewModel.newReleases)
      }

      if !recentlyPlayed.playlists.isEmpty {
        NewPlaylistRail(title: "Recently Released", playlists: recentlyPlayed.playlists)
      }

      if !viewModel.trending.isEmpty {
        NewSongRail(title: "Trending Songs", songs: viewModel.trending)
      }

      NewMoreToExplore()
    }
  }

  private var wideNewOverview: some View {
    VStack(alignment: .leading, spacing: AM.Spacing.xxl) {
      WideNewHero(
        primary: viewModel.newReleases.first,
        secondary: viewModel.trending.first,
        context: viewModel.newReleases.isEmpty ? viewModel.trending : viewModel.newReleases,
        playlist: viewModel.recentPlaylists.first
      )

      if !viewModel.newReleases.isEmpty {
        NewFeaturedRail(
          primary: viewModel.newReleases.first,
          secondary: viewModel.trending.first,
          songs: viewModel.newReleases
        )
      }

      HStack(alignment: .top, spacing: AM.Spacing.xxl) {
        VStack(alignment: .leading, spacing: AM.Spacing.xxl) {
          if !viewModel.newReleases.isEmpty {
            NewSongRail(title: "Up Next", songs: Array(viewModel.newReleases.prefix(8)))
          }

          if !viewModel.recentPlaylists.isEmpty {
            NewPlaylistRail(title: "New This Week", playlists: viewModel.recentPlaylists)
          }

          if !viewModel.newReleases.isEmpty {
            NewSongRail(title: "New Releases", songs: viewModel.newReleases)
          }

          if !recentlyPlayed.playlists.isEmpty {
            NewPlaylistRail(title: "Recently Released", playlists: recentlyPlayed.playlists)
          }

          if !viewModel.trending.isEmpty {
            NewSongRail(title: "Trending Songs", songs: viewModel.trending)
          }
        }
        .frame(minWidth: 520, maxWidth: .infinity, alignment: .topLeading)
        .layoutPriority(1)

        VStack(alignment: .leading, spacing: AM.Spacing.xxl) {
          if !viewModel.trending.isEmpty {
            NewSongListPreview(
              title: "Best New Songs",
              songs: Array(viewModel.trending.prefix(5)),
              horizontalPadding: 0
            )
          }

          NewMoreToExplore(horizontalPadding: 0)
        }
        .frame(width: AM.Layout.wideInspectorWidth, alignment: .topLeading)
      }
    }
    .frame(maxWidth: AM.Layout.wideContentMaxWidth, alignment: .topLeading)
    .frame(maxWidth: .infinity, alignment: .top)
    .padding(.horizontal, AM.Spacing.screenMargin)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("New.WideOverview")
  }
}

struct PlaylistCarousel: View {
  let title: String
  let playlists: [Playlist]
  var isLoadingMore: Bool = false
  var onAppearItem: ((Playlist) -> Void)? = nil
  var apiURL: ((Int, Int) -> String)? = nil
  var horizontalPadding: CGFloat = AM.Spacing.screenMargin
  @State private var availableWidth: CGFloat = 390

  var body: some View {
    GeometryReader { proxy in
      let tileWidth = AM.Layout.shelfTileWidth(for: proxy.size.width)
      VStack(alignment: .leading, spacing: AM.Spacing.s) {
        AMSectionHeader(
          title, destination: PlaylistListView(title: title, playlists: playlists, apiURL: apiURL))
        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(alignment: .top, spacing: AM.Spacing.l) {
            ForEach(playlists) { playlist in
              NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                PlaylistGridCell(playlist: playlist, width: tileWidth)
              }
              .buttonStyle(PressableButtonStyle())
              .contextMenu {
                PlaylistActionsMenuItems(playlist: playlist, songs: playlist.songListDTOs ?? [])
              } preview: {
                PlaylistContextPreview(playlist: playlist)
              }
              .onAppear { onAppearItem?(playlist) }
            }
            if isLoadingMore {
              ProgressView()
                .controlSize(.regular)
                .frame(width: 60, height: tileWidth)
            }
          }
          .padding(.horizontal, horizontalPadding)
        }
      }
      .onAppear {
        updateAvailableWidth(proxy.size.width)
      }
      .onChange(of: proxy.size.width) { _, width in
        updateAvailableWidth(width)
      }
    }
    .frame(height: AM.Layout.mediaShelfHeight(tileWidth: AM.Layout.shelfTileWidth(for: availableWidth)))
  }

  private func updateAvailableWidth(_ width: CGFloat) {
    guard width > 0, abs(width - availableWidth) > 0.5 else { return }
    availableWidth = width
  }
}

struct PlaylistListView: View {
  let title: String
  let playlists: [Playlist]
  var apiURL: ((Int, Int) -> String)? = nil
  let cols = AM.Layout.playlistGridColumns
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @StateObject private var loader = PlaylistListLoader()
  @State private var searchText = ""
  private var allPlaylists: [Playlist] {
    loader.playlists.isEmpty ? playlists : loader.playlists
  }
  private var displayedPlaylists: [Playlist] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return allPlaylists }
    return allPlaylists.filter { playlist in
      playlist.name.localizedCaseInsensitiveContains(query)
    }
  }
  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }
  var body: some View {
    ScrollView {
      if displayedPlaylists.isEmpty {
        MusicEmptyState(
          title: searchText.isEmpty ? "No Playlists" : "No Results",
          message: searchText.isEmpty
            ? "Playlists will appear here."
            : "Try another playlist name."
        )
        .frame(maxWidth: .infinity, minHeight: 360)
      } else {
        LazyVGrid(columns: cols, spacing: AM.Spacing.l) {
          ForEach(displayedPlaylists) { playlist in
            NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
              PlaylistGridCell(playlist: playlist)
            }
            .id(playlist.id)
            .buttonStyle(PressableButtonStyle())
            .accessibilityIdentifier("PlaylistList.\(playlist.id)")
            .contextMenu {
              PlaylistActionsMenuItems(playlist: playlist, songs: playlist.songListDTOs ?? [])
            } preview: {
              PlaylistContextPreview(playlist: playlist)
            }
            .onAppear {
              if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                loader.loadMoreIfNeeded(current: playlist)
              }
            }
          }
        }
        .padding(.horizontal, AM.Spacing.screenMargin)
        .padding(.vertical, AM.Spacing.m)
      }
      if loader.isLoadingMore {
        ProgressView()
          .controlSize(.regular)
          .frame(maxWidth: .infinity, alignment: .center)
          .frame(height: 44)
          .padding(.vertical, AM.Spacing.m)
      }
    }
    .smoothScrolling()
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .searchable(
      text: $searchText,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: "Search Playlists"
    )
    .animation(
      reduceMotion ? nil : AppMotion.spring(response: 0.34, dampingFraction: 0.84),
      value: displayedPlaylists.map(\.id)
    )
    .onAppear {
      if let apiURL {
        loader.bootstrap(initial: playlists, urlBuilder: apiURL)
      }
    }
  }
}

private struct WideHomeHero: View {
  let song: Song?
  let context: [Song]
  let playlist: Playlist?
  let secondarySong: Song?
  let secondaryContext: [Song]

  var body: some View {
    HStack(alignment: .top, spacing: AM.Spacing.xxl) {
      WideSongHeroCard(
        eyebrow: "Listen Now",
        title: song?.title ?? playlist?.name ?? "Twinskaraoke",
        subtitle: song?.displayArtist.isEmpty == false ? song?.displayArtist ?? "" : "Fresh karaoke picks for your next session",
        song: song,
        context: context,
        playlist: playlist
      )
      .frame(minWidth: 0, maxWidth: .infinity)

      VStack(alignment: .leading, spacing: AM.Spacing.m) {
        WideHeroModuleTitle(title: "Start Here", subtitle: "Fast actions")
        if let song {
          WideHeroActionRow(
            systemImage: "play.fill",
            title: "Play Latest",
            subtitle: song.title
          ) {
            AppHaptic.selection.play()
            AudioPlayerManager.shared.play(song: song, context: context)
          }
        }
        if let playlist {
          NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
            WideHeroActionRowContent(
              systemImage: "music.note.list",
              title: "Open Top Pick",
              subtitle: playlist.name
            )
          }
          .buttonStyle(PressableButtonStyle(scale: 0.98, dim: 0.78, haptic: .selection))
        }
        if let secondarySong {
          WideHeroActionRow(
            systemImage: "shuffle",
            title: "Shuffle Mix",
            subtitle: secondarySong.title
          ) {
            AppHaptic.selection.play()
            AudioPlayerManager.shared.playShuffled(from: secondaryContext.isEmpty ? [secondarySong] : secondaryContext)
          }
        }
      }
      .frame(width: AM.Layout.wideInspectorWidth, alignment: .topLeading)
    }
    .frame(minHeight: 286)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("Home.WideHero")
  }
}

private struct WideNewHero: View {
  let primary: Song?
  let secondary: Song?
  let context: [Song]
  let playlist: Playlist?

  var body: some View {
    HStack(alignment: .top, spacing: AM.Spacing.xxl) {
      WideSongHeroCard(
        eyebrow: "New Music",
        title: primary?.title ?? "New",
        subtitle: primary?.displayArtist.isEmpty == false ? primary?.displayArtist ?? "" : "The newest songs and karaoke-ready releases",
        song: primary,
        context: context,
        playlist: playlist
      )
      .frame(minWidth: 0, maxWidth: .infinity)

      VStack(alignment: .leading, spacing: AM.Spacing.m) {
        WideHeroModuleTitle(title: "Fresh Picks", subtitle: "Updated for large screens")
        if let primary {
          WideHeroSongRow(song: primary, context: context, label: "Featured Release")
        }
        if let secondary {
          WideHeroSongRow(song: secondary, context: context.isEmpty ? [secondary] : context, label: "Trending Now")
        }
        if let playlist {
          NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
            WideHeroActionRowContent(
              systemImage: "square.grid.2x2.fill",
              title: "New This Week",
              subtitle: playlist.name
            )
          }
          .buttonStyle(PressableButtonStyle(scale: 0.98, dim: 0.78, haptic: .selection))
        }
      }
      .frame(width: AM.Layout.wideInspectorWidth, alignment: .topLeading)
    }
    .frame(minHeight: 286)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("New.WideHero")
  }
}

private struct WideSongHeroCard: View {
  let eyebrow: String
  let title: String
  let subtitle: String
  let song: Song?
  let context: [Song]
  let playlist: Playlist?

  var body: some View {
    Button {
      play()
    } label: {
      ZStack(alignment: .bottomLeading) {
        heroArtwork
        LinearGradient(
          colors: [
            Color.black.opacity(0.08),
            Color.black.opacity(0.18),
            Color.black.opacity(0.68)
          ],
          startPoint: .top,
          endPoint: .bottom
        )
        .allowsHitTesting(false)

        HStack(alignment: .bottom, spacing: AM.Spacing.xl) {
          VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow)
              .font(.caption.bold())
              .foregroundStyle(.white.opacity(0.72))
              .textCase(.uppercase)
            Text(title)
              .font(.largeTitle.bold())
              .foregroundStyle(.white)
              .lineLimit(2)
              .minimumScaleFactor(0.72)
            Text(subtitle)
              .font(.subheadline)
              .foregroundStyle(.white.opacity(0.82))
              .lineLimit(2)
          }
          Spacer(minLength: AM.Spacing.l)
          Image(systemName: "play.fill")
            .font(.title3.bold())
            .foregroundStyle(.black)
            .frame(width: 54, height: 54)
            .background(.white, in: Circle())
            .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
            .accessibilityHidden(true)
        }
        .padding(AM.Spacing.xl)
      }
      .frame(minHeight: 286)
      .clipShape(RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous)
          .strokeBorder(Color.appDivider, lineWidth: 0.8)
      }
      .amShadow(AM.Shadow.heroPlaying)
    }
    .buttonStyle(PressableButtonStyle(scale: 0.985, dim: 0.88, haptic: .selection))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(title)
    .accessibilityValue(subtitle)
    .accessibilityHint(song == nil ? "Featured artwork." : "Plays this song.")
  }

  @ViewBuilder
  private var heroArtwork: some View {
    if let song {
      RemoteArtworkImage(url: song.fullHDImageURL ?? song.imageURL, cornerRadius: 0, contentMode: .fill)
        .allowsHitTesting(false)
    } else if let playlist {
      PlaylistArtwork(playlist: playlist, cornerRadius: 0)
        .allowsHitTesting(false)
    } else {
      MusicArtworkPlaceholder(cornerRadius: 0)
        .allowsHitTesting(false)
    }
  }

  private func play() {
    if let song {
      AppHaptic.selection.play()
      AudioPlayerManager.shared.play(song: song, context: context.isEmpty ? [song] : context)
    }
  }
}

private struct WideHeroModuleTitle: View {
  let title: String
  let subtitle: String

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.title3.bold())
        .foregroundStyle(.primary)
      Text(subtitle)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .padding(.bottom, 2)
  }
}

private struct WideHeroSongRow: View {
  let song: Song
  let context: [Song]
  let label: String

  var body: some View {
    WideHeroActionRow(systemImage: "play.fill", title: label, subtitle: song.title) {
      AppHaptic.selection.play()
      AudioPlayerManager.shared.play(song: song, context: context.isEmpty ? [song] : context)
    }
  }
}

private struct WideHeroActionRow: View {
  let systemImage: String
  let title: String
  let subtitle: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      WideHeroActionRowContent(systemImage: systemImage, title: title, subtitle: subtitle)
    }
    .buttonStyle(PressableButtonStyle(scale: 0.98, dim: 0.78, haptic: .selection))
  }
}

private struct WideHeroActionRowContent: View {
  let systemImage: String
  let title: String
  let subtitle: String

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color.appControlInactiveFill)
        Image(systemName: systemImage)
          .font(.subheadline.bold())
          .foregroundStyle(Color.appAccent)
      }
      .frame(width: 44, height: 44)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.headline)
          .foregroundStyle(.primary)
          .lineLimit(1)
        Text(subtitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 0)
      Image(systemName: "chevron.right")
        .font(AM.Font.chevron)
        .foregroundStyle(.tertiary)
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
    .padding(10)
    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
    .contentShape(RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
  }
}

private struct WideSongListPanel: View {
  let title: String
  let songs: [Song]

  var body: some View {
    VStack(alignment: .leading, spacing: AM.Spacing.s) {
      NavigationLink(destination: BrowseSongCollectionView(title: title, songs: songs)) {
        HStack(alignment: .firstTextBaseline, spacing: AM.Spacing.s) {
          Text(title)
            .font(AM.Font.sectionHeader)
            .foregroundStyle(.primary)
          Image(systemName: "chevron.right")
            .font(AM.Font.chevron)
            .foregroundStyle(.tertiary)
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
          Spacer()
        }
      }
      .buttonStyle(.plain)
      LazyVStack(spacing: 0) {
        ForEach(songs) { song in
          Button {
            AppHaptic.selection.play()
            AudioPlayerManager.shared.play(song: song, context: songs)
          } label: {
            SongRow(song: song, size: .compact)
          }
          .buttonStyle(.plain)
          if song.id != songs.last?.id {
            Divider().padding(.leading, 56)
          }
        }
      }
    }
    .accessibilityElement(children: .contain)
  }
}

struct HomeSongSection: View {
  let title: String
  let songs: [Song]
  var horizontalPadding: CGFloat = AM.Spacing.screenMargin
  @State private var availableWidth: CGFloat = 390

  var body: some View {
    GeometryReader { proxy in
      let tileWidth = AM.Layout.shelfTileWidth(for: proxy.size.width)
      VStack(alignment: .leading, spacing: AM.Spacing.s) {
        AMSectionHeader(title, destination: BrowseSongCollectionView(title: title, songs: songs))
        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(alignment: .top, spacing: AM.Spacing.l) {
            ForEach(songs) { song in
              MusicGridCard(
                song: song,
                context: songs,
                width: tileWidth,
                accessibilityIdentifier: "HomeSongSection.\(title).\(song.id)"
              )
            }
          }
          .padding(.horizontal, horizontalPadding)
        }
      }
      .onAppear {
        updateAvailableWidth(proxy.size.width)
      }
      .onChange(of: proxy.size.width) { _, width in
        updateAvailableWidth(width)
      }
    }
    .frame(height: AM.Layout.mediaShelfHeight(tileWidth: AM.Layout.shelfTileWidth(for: availableWidth)))
  }

  private func updateAvailableWidth(_ width: CGFloat) {
    guard width > 0, abs(width - availableWidth) > 0.5 else { return }
    availableWidth = width
  }
}

private struct NewFeaturedRail: View {
  let primary: Song?
  let secondary: Song?
  let songs: [Song]

  var body: some View {
    GeometryReader { proxy in
      let cardWidth = featureCardWidth(for: proxy.size.width)
      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(alignment: .top, spacing: AM.Spacing.l) {
          if let primary {
            NewFeatureCard(
              kicker: "Updated Playlist",
              title: "New Tracks",
              subtitle: primary.displayArtist.isEmpty ? "Twinskaraoke" : primary.displayArtist,
              song: primary,
              context: songs,
              width: cardWidth,
              artworkSize: cardWidth * 0.56
            )
          }
          if let secondary {
            NewFeatureCard(
              kicker: "Featured Release",
              title: secondary.title,
              subtitle: secondary.displayArtist,
              song: secondary,
              context: songs,
              width: cardWidth,
              artworkSize: cardWidth * 0.56
            )
          }
        }
        .padding(.horizontal, AM.Spacing.screenMargin)
      }
    }
    .frame(height: 316)
  }

  private func featureCardWidth(for availableWidth: CGFloat) -> CGFloat {
    min(max(availableWidth - AM.Spacing.screenMargin * 2, 300), 420)
  }
}

private struct NewFeatureCard: View {
  let kicker: String
  let title: String
  let subtitle: String
  let song: Song
  let context: [Song]
  let width: CGFloat
  let artworkSize: CGFloat

  var body: some View {
    Button {
      AppHaptic.selection.play()
      AudioPlayerManager.shared.play(song: song, context: context)
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        VStack(alignment: .leading, spacing: 2) {
          Text(kicker)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
          Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
            .lineLimit(2)
          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        ZStack(alignment: .bottomLeading) {
          RemoteArtworkImage(url: song.imageURL, cornerRadius: AM.Radius.card, contentMode: .fill)
          LinearGradient(
            colors: [.clear, .black.opacity(0.38)],
            startPoint: .center,
            endPoint: .bottom
          )
          Image(systemName: "play.fill")
            .font(.headline.bold())
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(.black.opacity(0.32), in: Circle())
            .padding(10)
        }
        .frame(width: width, height: artworkSize)
        .clipShape(RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
      }
      .frame(width: width, alignment: .leading)
    }
    .buttonStyle(PressableButtonStyle(scale: 0.97, dim: 0.82, haptic: .selection))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(title)
    .accessibilityValue(subtitle)
    .accessibilityHint("Plays this release.")
  }
}

private struct NewSongRail: View {
  let title: String
  let songs: [Song]

  var body: some View {
    GeometryReader { proxy in
      let tileWidth = AM.Layout.shelfTileWidth(for: proxy.size.width)
      VStack(alignment: .leading, spacing: AM.Spacing.m) {
        AMSectionHeader(title, destination: BrowseSongCollectionView(title: title, songs: songs))
        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(alignment: .top, spacing: AM.Spacing.l) {
            ForEach(songs) { song in
              MusicGridCard(
                song: song,
                context: songs,
                width: tileWidth
              )
            }
          }
          .padding(.horizontal, AM.Spacing.screenMargin)
        }
      }
    }
    .frame(height: AM.Layout.mediaShelfHeight)
  }
}

private struct NewSongListPreview: View {
  let title: String
  let songs: [Song]
  var horizontalPadding: CGFloat = AM.Spacing.screenMargin

  var body: some View {
    VStack(alignment: .leading, spacing: AM.Spacing.s) {
      AMSectionHeader(title, destination: BrowseSongCollectionView(title: title, songs: songs))
      LazyVStack(spacing: 0) {
        ForEach(songs) { song in
          Button {
            AppHaptic.selection.play()
            AudioPlayerManager.shared.play(song: song, context: songs)
          } label: {
            SongRow(song: song, size: .compact)
              .padding(.horizontal, horizontalPadding)
              .padding(.vertical, 3)
          }
          .buttonStyle(.plain)
          Divider().padding(.leading, 76)
        }
      }
    }
  }
}

private struct NewPlaylistRail: View {
  let title: String
  let playlists: [Playlist]

  var body: some View {
    GeometryReader { proxy in
      let tileWidth = AM.Layout.shelfTileWidth(for: proxy.size.width)
      VStack(alignment: .leading, spacing: AM.Spacing.m) {
        AMSectionHeader(title, destination: PlaylistListView(title: title, playlists: playlists))
        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(alignment: .top, spacing: AM.Spacing.l) {
            ForEach(playlists) { playlist in
              NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                PlaylistGridCell(playlist: playlist, width: tileWidth)
              }
              .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78, haptic: .selection))
              .contextMenu {
                PlaylistActionsMenuItems(playlist: playlist, songs: playlist.songListDTOs ?? [])
              } preview: {
                PlaylistContextPreview(playlist: playlist)
              }
            }
          }
          .padding(.horizontal, AM.Spacing.screenMargin)
        }
      }
    }
    .frame(height: AM.Layout.mediaShelfHeight)
  }
}

private struct NewMoreToExplore: View {
  var horizontalPadding: CGFloat = AM.Spacing.screenMargin

  private let links = [
    "Browse by Genre",
    "Decades",
    "Moods and Activities",
    "Worldwide",
    "Charts",
    "Music Videos",
    "Spatial Audio",
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: AM.Spacing.s) {
      AMSectionHeader("More to Explore")
      VStack(spacing: 0) {
        ForEach(links, id: \.self) { title in
          NavigationLink(destination: SearchCategorySongCollectionView(title: title, query: title)) {
            HStack {
              Text(title)
                .font(.body)
                .foregroundStyle(Color.appAccent)
              Spacer()
              Image(systemName: "chevron.right")
                .font(AM.Font.chevron)
                .foregroundStyle(.tertiary)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          if title != links[links.count - 1] {
            Divider()
          }
        }
      }
      .padding(.horizontal, horizontalPadding)
    }
  }
}

private struct LatestSingleSection: View {
  let song: Song
  let context: [Song]
  var horizontalPadding: CGFloat = AM.Spacing.screenMargin
  @State private var showAddToPlaylist = false

  var body: some View {
    VStack(alignment: .leading, spacing: AM.Spacing.m) {
      AMSectionHeader("Latest Single")
      Button {
        play()
      } label: {
        HStack(spacing: AM.Spacing.m) {
          RemoteArtworkImage(url: song.imageURL, cornerRadius: AM.Radius.card)
            .frame(width: 92, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
            .amShadow(AM.Shadow.card)
          VStack(alignment: .leading, spacing: 6) {
            Text(song.title)
              .font(.headline)
              .foregroundStyle(.primary)
              .lineLimit(2)
            Text(song.displayArtist)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .lineLimit(2)
            Label("Play Latest Release", systemImage: "play.fill")
              .font(.caption.bold())
              .foregroundStyle(Color.appAccent)
              .padding(.top, 4)
          }
          Spacer(minLength: 12)
        }
        .padding(14)
        .background(
          RoundedRectangle(cornerRadius: AM.Radius.sheet, style: .continuous)
            .fill(Color.appSecondaryBackground)
        )
      }
      .buttonStyle(PressableButtonStyle())
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
      .padding(.horizontal, horizontalPadding)
    }
  }

  private func play() {
    AppHaptic.selection.play()
    AudioPlayerManager.shared.play(song: song, context: context)
  }
}

struct NewSkeletonView: View {
  var body: some View {
    CenteredLoadingView(label: "Loading New")
  }
}

struct HomeSkeletonView: View {
  var body: some View {
    CenteredLoadingView(label: "Loading Home")
  }
}

struct BrowseSongCollectionView: View {
  let title: String
  let songs: [Song]
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var scrollOffset: CGFloat = 0
  // Very large result sets skip per-row artwork to keep cell creation and image
  // decoding from dominating a fast collection scroll.
  private var showsArtwork: Bool { songs.count <= 200 }
  private func usesWideOverview(availableWidth: CGFloat) -> Bool {
    AM.Layout.usesWideCanvas(
      horizontalSizeClass: horizontalSizeClass,
      availableWidth: availableWidth
    )
  }
  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }
  init(title: String, songs: [Song]) {
    self.title = title
    self.songs = songs
  }
  var body: some View {
    GeometryReader { geo in
      ScrollView {
        collectionOverview(width: geo.size.width)
        .tabBarBottomPadding()
        .animation(
          reduceMotion ? nil : AppMotion.spring(response: 0.34, dampingFraction: 0.84),
          value: songs.count)
        .background(
          GeometryReader { proxy in
            Color.clear.preference(
              key: BrowseScrollOffsetKey.self,
              value: proxy.frame(in: .named("browseScroll")).minY
            )
          }
        )
      }
      .smoothScrolling()
      .coordinateSpace(name: "browseScroll")
      .onPreferenceChange(BrowseScrollOffsetKey.self) { scrollOffset = quantizedScrollOffset($0) }
    }
    .navigationTitle(scrollOffset < -180 ? title : "")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(scrollOffset < -180 ? .visible : .hidden, for: .navigationBar)
    .animation(
      reduceMotion ? nil : AppMotion.spring(response: 0.34, dampingFraction: 0.84),
      value: scrollOffset < -180)
  }

  @ViewBuilder
  private func collectionOverview(width: CGFloat) -> some View {
    if usesWideOverview(availableWidth: width) {
      wideCollectionOverview
    } else {
      compactCollectionOverview(width: width)
    }
  }

  private func compactCollectionOverview(width: CGFloat) -> some View {
    VStack(spacing: 18) {
      parallaxHero(width: width)
      collectionTitleBlock(alignment: .center)
      songsContent()
    }
  }

  private var wideCollectionOverview: some View {
    HStack(alignment: .top, spacing: AM.Spacing.xxl) {
      VStack(alignment: .leading, spacing: AM.Spacing.l) {
        heroArtwork
          .frame(width: 280, height: 280)
          .clipShape(RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous))
          .amShadow(AM.Shadow.heroIdle)
        collectionTitleBlock(alignment: .leading)
        if !songs.isEmpty {
          actionButtons(horizontalPadding: 0)
        }
      }
      .frame(width: 320, alignment: .topLeading)

      songsContent(isWideOverview: true, rowHorizontalPadding: 0)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .frame(maxWidth: 1120, alignment: .topLeading)
    .frame(maxWidth: .infinity, alignment: .top)
    .padding(.horizontal, AM.Spacing.screenMargin)
    .padding(.top, AM.Spacing.m)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("BrowseSongCollection.WideOverview")
  }

  private func play(_ song: Song) {
    AppHaptic.selection.play()
    AudioPlayerManager.shared.play(song: song, context: songs)
  }

  @ViewBuilder
  private func parallaxHero(width: CGFloat) -> some View {
    let baseSize: CGFloat = 240
    let stretch = reduceMotion ? 0 : max(0, scrollOffset)
    let shrink = reduceMotion ? 0 : max(0, -scrollOffset * 0.4)
    let size = max(140, baseSize + stretch * 0.6 - shrink)
    let yOffset = reduceMotion ? 0 : (scrollOffset > 0 ? -scrollOffset / 2 : 0)
    heroArtwork
      .frame(width: size, height: size)
      .clipShape(RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous))
      .amShadow(AM.Shadow.heroIdle)
      .offset(y: yOffset)
      .frame(maxWidth: .infinity)
      .frame(height: baseSize)
      .padding(.top, 8)
  }

  private func collectionTitleBlock(alignment: TextAlignment) -> some View {
    VStack(alignment: alignment == .leading ? .leading : .center, spacing: 4) {
      Text(title)
        .font(.title2.bold())
        .multilineTextAlignment(alignment)
      Text(songCountText)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
    .padding(.horizontal, alignment == .leading ? 0 : AM.Spacing.screenMargin)
  }

  private var songCountText: String {
    songs.count == 1 ? "1 song" : "\(songs.count) songs"
  }

  @ViewBuilder
  private var heroArtwork: some View {
    let artURL = songs.first(where: { $0.hasOwnArtwork })?.imageURL ?? FallbackArtProvider.shared.randomURL
    RemoteArtworkImage(url: artURL, cornerRadius: 0, contentMode: .fill)
  }

  @ViewBuilder
  private func songsContent(
    isWideOverview: Bool = false,
    rowHorizontalPadding: CGFloat = AM.Spacing.screenMargin
  ) -> some View {
    if !songs.isEmpty {
      VStack(spacing: 0) {
        if !isWideOverview {
          actionButtons()
        }
        LazyVStack(spacing: 0) {
          ForEach(songs) { song in
            Button {
              play(song)
            } label: {
              SongRow(song: song, size: .regular, showsArtwork: showsArtwork)
                .padding(.horizontal, rowHorizontalPadding)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .songRowAccessibility(song: song) {
                  play(song)
                }
            }
            .buttonStyle(PressableButtonStyle(scale: 0.985, dim: 0.78, haptic: .selection))
            .accessibilityHint("Starts playback.")
            .accessibilityIdentifier("BrowseSongCollection.song.\(song.id)")
            Divider().padding(.leading, rowHorizontalPadding + (showsArtwork ? 60 : 12))
          }
        }
      }
    } else {
      MusicEmptyState(
        title: "No Songs",
        message: "This collection does not have playable songs yet."
      )
      .padding(.top, AM.Spacing.s)
      .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
    }
  }

  private func actionButtons(horizontalPadding: CGFloat = AM.Spacing.screenMargin) -> some View {
    HStack(spacing: AM.Spacing.m) {
      Button {
        if let first = songs.first {
          AppHaptic.medium.play()
          AudioPlayerManager.shared.playInOrder(song: first, context: songs)
        }
      } label: {
        Label("Play", systemImage: "play.fill")
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 10)
          .background(Color.primary.opacity(0.08))
          .foregroundStyle(Color.appAccent)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.82))
      .accessibilityLabel("Play \(title)")
      .accessibilityValue("\(songs.count) songs")
      Button {
        AppHaptic.selection.play()
        AudioPlayerManager.shared.playShuffled(from: songs)
      } label: {
        Label("Shuffle", systemImage: "shuffle")
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 10)
          .background(Color.primary.opacity(0.08))
          .foregroundStyle(Color.appAccent)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.82))
      .accessibilityLabel("Shuffle \(title)")
      .accessibilityValue("\(songs.count) songs")
    }
    .padding(.horizontal, horizontalPadding)
  }
}

private struct BrowseScrollOffsetKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

private func quantizedScrollOffset(_ offset: CGFloat) -> CGFloat {
  // Parallax and nav chrome do not need pixel-accurate offsets; bucketing the value
  // cuts down SwiftUI invalidations while preserving the visible effect.
  (offset / 8).rounded() * 8
}

final class PlaylistListLoader: ObservableObject {
  @Published var playlists: [Playlist] = []
  @Published var isLoadingMore = false
  private var canLoadMore = true
  private let pageSize = 25
  private var urlBuilder: ((Int, Int) -> String)?

  func bootstrap(initial: [Playlist], urlBuilder: @escaping (Int, Int) -> String) {
    guard self.urlBuilder == nil else { return }
    self.urlBuilder = urlBuilder
    self.playlists = initial
    self.canLoadMore = true
  }

  func loadMoreIfNeeded(current: Playlist) {
    guard let idx = playlists.firstIndex(where: { $0.id == current.id }) else { return }
    if idx >= playlists.count - 4 && !isLoadingMore && canLoadMore {
      loadMore()
    }
  }

  private func loadMore() {
    guard let urlBuilder else { return }
    isLoadingMore = true
    let startIndex = playlists.count
    let urlString = urlBuilder(startIndex, pageSize)
    guard let url = URL(string: urlString) else {
      isLoadingMore = false
      return
    }
    var request = URLRequest(url: url)
    if let token = UserDefaults.standard.string(forKey: "nk.token") {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    GuestIdentity.applyIfNeeded(to: &request)
    URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
      DispatchQueue.main.async {
        guard let self else { return }
        let items = Self.decode(data: data)
        if !items.isEmpty {
          let existing = Set(self.playlists.map { $0.id })
          self.playlists += items.filter { !existing.contains($0.id) }
          self.canLoadMore = items.count >= self.pageSize
        } else {
          self.canLoadMore = false
        }
        self.isLoadingMore = false
      }
    }.resume()
  }

  private static func decode(data: Data?) -> [Playlist] {
    guard let data else { return [] }
    let decoder = JSONDecoder()
    if let items = (try? decoder.decode(LossyArray<PlaylistListItem>.self, from: data))?.elements {
      return items.map { $0.asPlaylist() }
    }
    if let items = try? decoder.decode([PlaylistListItem].self, from: data) {
      return items.map { $0.asPlaylist() }
    }
    return []
  }
}
