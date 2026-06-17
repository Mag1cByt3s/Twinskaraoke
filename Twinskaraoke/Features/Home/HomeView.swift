import Combine
import SwiftUI

struct HomeView: View {
  @StateObject var viewModel = HomeViewModel()
  @StateObject private var recentlyPlayed = RecentlyPlayedStore.shared
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true

  private var usesWideOverview: Bool {
    horizontalSizeClass == .regular
  }

  private var loadingAnimation: Animation? {
    reduceMotion ? nil : .easeInOut(duration: 0.35)
  }

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        Group {
          if viewModel.isLoading {
            HomeSkeletonView()
              .transition(.opacity)
          } else {
            homeOverview
              .transition(.opacity)
          }
        }
        .animation(loadingAnimation, value: viewModel.isLoading)
        .padding(.top, AM.Spacing.l)
        .padding(.bottom, AM.Spacing.l)
      }
      .scrollDismissesKeyboard(.interactively)
      .tabBarScrollInset()
      .musicScreenBackground()
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
  private var homeOverview: some View {
    if usesWideOverview {
      wideHomeOverview
    } else {
      compactHomeOverview
    }
  }

  private var compactHomeOverview: some View {
    VStack(alignment: .leading, spacing: AM.Spacing.shelfSpacing) {
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
      .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)

      VStack(alignment: .leading, spacing: AM.Spacing.xxl) {
        latestSingleSection(horizontalPadding: 0)

        if !viewModel.newReleases.isEmpty {
          HomeSongSection(title: "New Releases", songs: viewModel.newReleases, horizontalPadding: 0)
        }

        if !viewModel.trending.isEmpty {
          HomeSongSection(title: "More to Explore", songs: viewModel.trending, horizontalPadding: 0)
        }
      }
      .frame(minWidth: 300, idealWidth: 360, maxWidth: 420, alignment: .topLeading)
    }
    .frame(maxWidth: 1120, alignment: .topLeading)
    .frame(maxWidth: .infinity, alignment: .top)
    .padding(.horizontal, AM.Spacing.screenMargin)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("Home.WideOverview")
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

  private var usesWideOverview: Bool {
    horizontalSizeClass == .regular
  }

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  private var loadingAnimation: Animation? {
    reduceMotion ? nil : .easeInOut(duration: 0.35)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        Group {
          if viewModel.isLoading {
            NewSkeletonView()
              .transition(.opacity)
          } else {
            newOverview
              .transition(.opacity)
          }
        }
        .animation(loadingAnimation, value: viewModel.isLoading)
        .padding(.top, AM.Spacing.m)
        .padding(.bottom, AM.Spacing.l)
      }
      .scrollDismissesKeyboard(.interactively)
      .tabBarScrollInset()
      .musicScreenBackground()
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
  private var newOverview: some View {
    if usesWideOverview {
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
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)

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
        .frame(minWidth: 300, idealWidth: 360, maxWidth: 420, alignment: .topLeading)
      }
    }
    .frame(maxWidth: 1120, alignment: .topLeading)
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
  var body: some View {
    GeometryReader { proxy in
      let tileWidth = AM.Layout.shelfTileWidth(for: proxy.size.width)
      VStack(alignment: .leading, spacing: AM.Spacing.m) {
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
              LoadingIndicator(size: 32)
                .frame(width: 60, height: tileWidth)
            }
          }
          .padding(.horizontal, horizontalPadding)
        }
      }
    }
    .frame(height: AM.Layout.mediaShelfHeight)
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
          systemImage: "music.note.list",
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
        LoadingIndicator(size: 32)
          .frame(maxWidth: .infinity, alignment: .center)
          .frame(height: 44)
          .padding(.vertical, AM.Spacing.m)
      }
    }
    .scrollDismissesKeyboard(.interactively)
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .searchable(
      text: $searchText,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: "Search Playlists"
    )
    .animation(
      reduceMotion ? nil : .easeInOut(duration: 0.22),
      value: displayedPlaylists.map(\.id)
    )
    .onAppear {
      if let apiURL {
        loader.bootstrap(initial: playlists, urlBuilder: apiURL)
      }
    }
  }
}

struct HomeSongSection: View {
  let title: String
  let songs: [Song]
  var horizontalPadding: CGFloat = AM.Spacing.screenMargin
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
                width: tileWidth,
                accessibilityIdentifier: "HomeSongSection.\(title).\(song.id)"
              )
            }
          }
          .padding(.horizontal, horizontalPadding)
        }
      }
    }
    .frame(height: AM.Layout.mediaShelfHeight)
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
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
          Text(title)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(2)
          Text(subtitle)
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        ZStack(alignment: .bottomLeading) {
          LoadingImage(url: song.imageURL, cornerRadius: AM.Radius.card, contentMode: .fill)
          LinearGradient(
            colors: [.clear, .black.opacity(0.38)],
            startPoint: .center,
            endPoint: .bottom
          )
          Image(systemName: "play.fill")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
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
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.appAccent)
              Spacer()
              Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            }
            .frame(height: 42)
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
          LoadingImage(url: song.imageURL, cornerRadius: AM.Radius.card)
            .frame(width: 92, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
            .amShadow(AM.Shadow.card)
          VStack(alignment: .leading, spacing: 6) {
            Text(song.title)
              .font(.system(size: 18, weight: .bold))
              .foregroundStyle(.primary)
              .lineLimit(2)
            Text(song.displayArtist)
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(.secondary)
              .lineLimit(2)
            Label("Play Latest Release", systemImage: "play.fill")
              .font(.system(size: 12, weight: .semibold))
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
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var pulse = false

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      featuredRailSkeleton
      shelfSkeleton(titleWidth: 78, count: 4)
      listPreviewSkeleton
      shelfSkeleton(titleWidth: 122, count: 4)
    }
    .opacity(!reduceMotion && pulse ? 0.58 : 1.0)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Loading New")
    .onAppear {
      guard !reduceMotion else {
        pulse = false
        return
      }
      withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
        pulse = true
      }
    }
    .onChange(of: reduceMotion) { _, reduceMotion in
      if reduceMotion {
        withAnimation(nil) {
          pulse = false
        }
      } else {
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
          pulse = true
        }
      }
    }
  }

  private var featuredRailSkeleton: some View {
    GeometryReader { geo in
      let cardWidth = min(max(geo.size.width - AM.Spacing.screenMargin * 2, 300), 420)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: AM.Spacing.l) {
          ForEach(0..<2, id: \.self) { index in
            featuredCardSkeleton(width: cardWidth, index: index)
          }
        }
        .padding(.horizontal, AM.Spacing.screenMargin)
      }
    }
    .frame(height: 316)
  }

  private func featuredCardSkeleton(width: CGFloat, index: Int) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
          .fill(Color.appPlaceholderSecondary)
          .frame(width: index == 0 ? 112 : 128, height: 11)

        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(Color.appPlaceholderTertiary)
          .frame(width: width * (index == 0 ? 0.48 : 0.72), height: 22)

        RoundedRectangle(cornerRadius: 3, style: .continuous)
          .fill(Color.appPlaceholderSecondary)
          .frame(width: width * (index == 0 ? 0.34 : 0.46), height: 14)
      }

      RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous)
        .fill(Color.appPlaceholderPrimary)
        .frame(width: width, height: width * 0.56)
        .overlay(alignment: .bottomLeading) {
          Circle()
            .fill(Color.appPlaceholderSecondary)
            .frame(width: 34, height: 34)
            .padding(10)
        }
    }
    .frame(width: width, alignment: .leading)
  }

  private func shelfSkeleton(titleWidth: CGFloat, count: Int) -> some View {
    GeometryReader { proxy in
      let tileWidth = AM.Layout.shelfTileWidth(for: proxy.size.width)
      VStack(alignment: .leading, spacing: AM.Spacing.m) {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(Color.appPlaceholderTertiary)
          .frame(width: titleWidth, height: 18)
          .padding(.horizontal, AM.Spacing.screenMargin)

        ScrollView(.horizontal, showsIndicators: false) {
          HStack(alignment: .top, spacing: AM.Spacing.l) {
            ForEach(0..<count, id: \.self) { index in
              VStack(alignment: .leading, spacing: AM.Spacing.s) {
                RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous)
                  .fill(Color.appPlaceholderPrimary)
                  .frame(width: tileWidth, height: tileWidth)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                  .fill(Color.appPlaceholderSecondary)
                  .frame(width: tileWidth * (index.isMultiple(of: 2) ? 0.72 : 0.58), height: 15)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                  .fill(Color.appPlaceholderPrimary)
                  .frame(width: tileWidth * (index == 1 ? 0.48 : 0.38), height: 13)
              }
              .frame(width: tileWidth, alignment: .leading)
            }
          }
          .padding(.horizontal, AM.Spacing.screenMargin)
        }
      }
    }
    .frame(height: AM.Layout.mediaShelfHeight)
  }

  private var listPreviewSkeleton: some View {
    VStack(alignment: .leading, spacing: AM.Spacing.s) {
      RoundedRectangle(cornerRadius: 4, style: .continuous)
        .fill(Color.appPlaceholderTertiary)
        .frame(width: 132, height: 18)
        .padding(.horizontal, AM.Spacing.screenMargin)

      VStack(spacing: 0) {
        ForEach(0..<5, id: \.self) { index in
          SongRowSkeleton(size: .compact)
            .padding(.horizontal, AM.Spacing.screenMargin)
            .padding(.vertical, 3)

          if index != 4 {
            Divider()
              .padding(.leading, AM.Spacing.screenMargin + 58)
          }
        }
      }
    }
  }
}

struct HomeSkeletonView: View {
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: AM.Spacing.shelfSpacing) {
      shelfSkeleton(titleWidth: 138, count: 3)
      shelfSkeleton(titleWidth: 118, count: 3)
      latestSingleSkeleton
      shelfSkeleton(titleWidth: 126, count: 3)
    }
    .musicSkeletonShimmer(active: !reduceMotion)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Loading Home")
  }

  private func shelfSkeleton(titleWidth: CGFloat, count: Int) -> some View {
    GeometryReader { proxy in
      let tileSize = AM.Layout.shelfTileWidth(for: proxy.size.width)
      VStack(alignment: .leading, spacing: AM.Spacing.m) {
        headerPill(width: titleWidth, height: 18)
          .padding(.horizontal, AM.Spacing.screenMargin)

        ScrollView(.horizontal, showsIndicators: false) {
          HStack(alignment: .top, spacing: AM.Spacing.l) {
            ForEach(0..<count, id: \.self) { index in
              VStack(alignment: .leading, spacing: AM.Spacing.s) {
                RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous)
                  .fill(artworkFill(index: index))
                  .frame(width: tileSize, height: tileSize)
                  .overlay {
                    RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous)
                      .stroke(Color.primary.opacity(0.035), lineWidth: 0.6)
                  }

                textPill(width: tileSize * (index.isMultiple(of: 2) ? 0.72 : 0.58), height: 15)
                textPill(width: tileSize * (index == 1 ? 0.48 : 0.38), height: 13, tone: .primary)
              }
              .frame(width: tileSize, alignment: .leading)
            }
          }
          .padding(.horizontal, AM.Spacing.screenMargin)
        }
      }
    }
    .frame(height: AM.Layout.mediaShelfHeight)
  }

  private var latestSingleSkeleton: some View {
    VStack(alignment: .leading, spacing: AM.Spacing.s) {
      headerPill(width: 112, height: 18)
        .padding(.horizontal, AM.Spacing.screenMargin)

      HStack(spacing: AM.Spacing.m) {
        RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous)
          .fill(artworkFill(index: 1))
          .frame(width: 92, height: 92)
          .overlay {
            RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous)
              .stroke(Color.primary.opacity(0.035), lineWidth: 0.6)
          }

        VStack(alignment: .leading, spacing: 8) {
          headerPill(width: 190, height: 18)
          textPill(width: 132, height: 13, tone: .primary)
          Capsule(style: .continuous)
            .fill(Color.appPlaceholderSecondary)
            .frame(width: 118, height: 18)
        }

        Spacer(minLength: 12)
      }
      .padding(14)
      .background(
        Color.appSecondaryBackground,
        in: RoundedRectangle(cornerRadius: AM.Radius.sheet, style: .continuous)
      )
      .padding(.horizontal, AM.Spacing.screenMargin)
    }
  }

  private func headerPill(width: CGFloat, height: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: 4, style: .continuous)
      .fill(Color.appPlaceholderTertiary)
      .frame(width: width, height: height)
  }

  private enum TextPillTone {
    case primary, secondary
  }

  private func textPill(width: CGFloat, height: CGFloat, tone: TextPillTone = .secondary) -> some View {
    RoundedRectangle(cornerRadius: 3, style: .continuous)
      .fill(tone == .secondary ? Color.appPlaceholderSecondary : Color.appPlaceholderPrimary)
      .frame(width: width, height: height)
  }

  private func artworkFill(index: Int) -> LinearGradient {
    LinearGradient(
      colors: [
        Color.appPlaceholderSecondary,
        Color.appPlaceholderPrimary,
        index.isMultiple(of: 2)
          ? Color.appPlaceholderSecondary.opacity(0.72)
          : Color.appPlaceholderTertiary.opacity(0.56),
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
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
  private var usesWideOverview: Bool {
    horizontalSizeClass == .regular
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
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: songs.count)
        .background(
          GeometryReader { proxy in
            Color.clear.preference(
              key: BrowseScrollOffsetKey.self,
              value: proxy.frame(in: .named("browseScroll")).minY
            )
          }
        )
      }
      .scrollDismissesKeyboard(.interactively)
      .coordinateSpace(name: "browseScroll")
      .onPreferenceChange(BrowseScrollOffsetKey.self) { scrollOffset = quantizedScrollOffset($0) }
    }
    .navigationTitle(scrollOffset < -180 ? title : "")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(scrollOffset < -180 ? .visible : .hidden, for: .navigationBar)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: scrollOffset < -180)
  }

  @ViewBuilder
  private func collectionOverview(width: CGFloat) -> some View {
    if usesWideOverview {
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

      songsContent(rowHorizontalPadding: 0)
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
        .foregroundColor(.secondary)
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
    LoadingImage(url: artURL, cornerRadius: 0, contentMode: .fill)
  }

  @ViewBuilder
  private func songsContent(rowHorizontalPadding: CGFloat = AM.Spacing.screenMargin) -> some View {
    if !songs.isEmpty {
      VStack(spacing: 0) {
        if !usesWideOverview {
          actionButtons()
        }
        LazyVStack(spacing: 0) {
          ForEach(songs) { song in
            SongRow(song: song, size: .regular, showsArtwork: showsArtwork)
              .padding(.horizontal, rowHorizontalPadding)
              .padding(.vertical, 6)
              .contentShape(Rectangle())
              .onTapGesture {
                play(song)
              }
              .songRowAccessibility(song: song) {
                play(song)
              }
              .accessibilityIdentifier("BrowseSongCollection.song.\(song.id)")
            Divider().padding(.leading, rowHorizontalPadding + (showsArtwork ? 60 : 12))
          }
        }
      }
    } else {
      MusicEmptyState(
        systemImage: "music.note.list",
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
          .font(.system(size: 17, weight: .semibold))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 10)
          .background(Color.primary.opacity(0.08))
          .foregroundColor(.appAccent)
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
          .font(.system(size: 17, weight: .semibold))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 10)
          .background(Color.primary.opacity(0.08))
          .foregroundColor(.appAccent)
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
