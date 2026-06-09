import Combine
import SwiftUI

struct HomeView: View {
  @StateObject var viewModel = HomeViewModel()
  @StateObject private var recentlyPlayed = RecentlyPlayedStore.shared
  @EnvironmentObject var audioManager: AudioPlayerManager
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true

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
            VStack(alignment: .leading, spacing: AM.Spacing.shelfSpacing) {
              if !viewModel.recentPlaylists.isEmpty {
                PlaylistCarousel(
                  title: "Top Picks",
                  playlists: viewModel.recentPlaylists,
                  isLoadingMore: viewModel.isLoadingMoreTopPicks,
                  onAppearItem: { viewModel.loadMoreTopPicksIfNeeded(current: $0) },
                  apiURL: { startIndex, pageSize in
                    viewModel.topPicksURLForList(startIndex: startIndex, pageSize: pageSize)
                  }
                )
              }
              if !recentlyPlayed.playlists.isEmpty {
                PlaylistCarousel(title: "Recently Played", playlists: recentlyPlayed.playlists)
              }
              if !viewModel.suggestions.isEmpty {
                HomeSongSection(title: "Made for You", songs: viewModel.suggestions)
              }
              if let latestSingle = viewModel.latestSingle {
                LatestSingleSection(
                  song: latestSingle,
                  context: viewModel.latestSingleContext.isEmpty
                    ? [latestSingle] : viewModel.latestSingleContext
                )
              }
              if !viewModel.newReleases.isEmpty {
                HomeSongSection(title: "New Releases", songs: viewModel.newReleases)
              }
              if !viewModel.trending.isEmpty {
                HomeSongSection(title: "More to Explore", songs: viewModel.trending)
              }
            }
            .transition(.opacity)
          }
        }
        .animation(loadingAnimation, value: viewModel.isLoading)
        .padding(.top, AM.Spacing.l)
        .padding(.bottom, AM.Spacing.l)
      }
      .musicScreenBackground()
      .navigationTitle("Home")
      .navigationBarTitleDisplayMode(.large)
      .refreshable { viewModel.fetchHomeData(force: true) }
    }
  }
}

struct PlaylistCarousel: View {
  let title: String
  let playlists: [Playlist]
  var isLoadingMore: Bool = false
  var onAppearItem: ((Playlist) -> Void)? = nil
  var apiURL: ((Int, Int) -> String)? = nil
  var body: some View {
    VStack(alignment: .leading, spacing: AM.Spacing.m) {
      AMSectionHeader(
        title, destination: PlaylistListView(title: title, playlists: playlists, apiURL: apiURL))
      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(alignment: .top, spacing: AM.Spacing.l) {
          ForEach(playlists) { playlist in
            NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
              PlaylistGridCell(playlist: playlist, width: AM.Spacing.shelfTile)
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
              .frame(width: 60, height: AM.Spacing.shelfTile)
          }
        }
        .padding(.horizontal, AM.Spacing.screenMargin)
      }
    }
  }
}

struct PlaylistListView: View {
  let title: String
  let playlists: [Playlist]
  var apiURL: ((Int, Int) -> String)? = nil
  let cols = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
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
            .buttonStyle(PressableButtonStyle())
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
          .padding(.vertical, AM.Spacing.m)
      }
    }
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
  var body: some View {
    VStack(alignment: .leading, spacing: AM.Spacing.m) {
      AMSectionHeader(title, destination: BrowseSongCollectionView(title: title, songs: songs))
      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(alignment: .top, spacing: AM.Spacing.l) {
          ForEach(songs) { song in
            HomeSongCard(song: song, context: songs)
          }
        }
        .padding(.horizontal, AM.Spacing.screenMargin)
      }
    }
  }
}

struct HomeSongCard: View {
  let song: Song
  let context: [Song]
  @EnvironmentObject var audioManager: AudioPlayerManager
  @State private var showAddToPlaylist = false
  var body: some View {
    Button {
      play()
    } label: {
      VStack(alignment: .leading, spacing: AM.Spacing.s) {
        LoadingImage(url: song.imageURL, cornerRadius: AM.Radius.card)
          .frame(width: AM.Spacing.shelfTile, height: AM.Spacing.shelfTile)
          .clipShape(RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
          .amShadow(AM.Shadow.card)
        Text(song.title)
          .font(AM.Font.tileTitle)
          .foregroundColor(.primary)
          .lineLimit(1)
        Text(song.displayArtist)
          .font(AM.Font.tileCaption)
          .foregroundColor(.secondary)
          .lineLimit(1)
      }
      .frame(width: AM.Spacing.shelfTile)
    }
    .buttonStyle(PressableButtonStyle())
    .contextMenu {
      SongActionsMenuItems(song: song) {
        showAddToPlaylist = true
      }
    } preview: {
      SongContextPreview(song: song)
        .environmentObject(audioManager)
    }
    .sheet(isPresented: $showAddToPlaylist) {
      AddToPlaylistSheet(song: song)
    }
  }

  private func play() {
    AppHaptic.selection.play()
    audioManager.play(song: song, context: context)
  }
}

private struct LatestSingleSection: View {
  let song: Song
  let context: [Song]
  @EnvironmentObject var audioManager: AudioPlayerManager
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
          .environmentObject(audioManager)
      }
      .sheet(isPresented: $showAddToPlaylist) {
        AddToPlaylistSheet(song: song)
      }
      .padding(.horizontal, AM.Spacing.screenMargin)
    }
  }

  private func play() {
    AppHaptic.selection.play()
    audioManager.play(song: song, context: context)
  }
}

struct HomeSkeletonView: View {
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
    VStack(alignment: .leading, spacing: AM.Spacing.shelfSpacing) {
      skeletonShelf(titleWidth: 96, tileSize: AM.Spacing.shelfTile, count: 3)
      skeletonShelf(titleWidth: 138, tileSize: AM.Spacing.shelfTile, count: 3)
      skeletonShelf(titleWidth: 118, tileSize: AM.Spacing.shelfTile, count: 3)
      latestSingleSkeleton
      skeletonShelf(titleWidth: 126, tileSize: AM.Spacing.shelfTile, count: 3)
    }
    .opacity(!reduceMotion && pulse ? 0.58 : 1.0)
    .redacted(reason: .placeholder)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Loading Home")
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

  private func skeletonShelf(titleWidth: CGFloat, tileSize: CGFloat, count: Int) -> some View {
    VStack(alignment: .leading, spacing: AM.Spacing.m) {
      RoundedRectangle(cornerRadius: 4, style: .continuous)
        .fill(Color.appPlaceholderSecondary)
        .frame(width: titleWidth, height: 18)
        .padding(.horizontal, AM.Spacing.screenMargin)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: AM.Spacing.l) {
          ForEach(0..<count, id: \.self) { index in
            VStack(alignment: .leading, spacing: AM.Spacing.s) {
              RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous)
                .fill(Color.appPlaceholderPrimary)
                .frame(width: tileSize, height: tileSize)
              RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.appPlaceholderSecondary)
                .frame(width: tileSize * (index == 1 ? 0.78 : 0.62), height: 13)
              RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.appPlaceholderPrimary)
                .frame(width: tileSize * (index == 2 ? 0.52 : 0.44), height: 11)
            }
            .frame(width: tileSize)
          }
        }
        .padding(.horizontal, AM.Spacing.screenMargin)
      }
    }
  }

  private var latestSingleSkeleton: some View {
    VStack(alignment: .leading, spacing: AM.Spacing.m) {
      RoundedRectangle(cornerRadius: 4, style: .continuous)
        .fill(Color.appPlaceholderSecondary)
        .frame(width: 112, height: 18)
        .padding(.horizontal, AM.Spacing.screenMargin)

      HStack(spacing: AM.Spacing.m) {
        RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous)
          .fill(Color.appPlaceholderPrimary)
          .frame(width: 92, height: 92)

        VStack(alignment: .leading, spacing: 8) {
          RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.appPlaceholderSecondary)
            .frame(width: 190, height: 18)
          RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color.appPlaceholderPrimary)
            .frame(width: 132, height: 12)
          RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color.appPlaceholderSecondary)
            .frame(width: 118, height: 12)
        }

        Spacer(minLength: 0)
      }
      .padding(14)
      .background(
        Color.appSecondaryBackground,
        in: RoundedRectangle(cornerRadius: AM.Radius.sheet, style: .continuous)
      )
      .padding(.horizontal, AM.Spacing.screenMargin)
    }
  }
}

struct BrowseSongCollectionView: View {
  let title: String
  let subtitle: String?
  let songs: [Song]
  @EnvironmentObject var audioManager: AudioPlayerManager
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var scrollOffset: CGFloat = 0
  private var showsArtwork: Bool { songs.count <= 200 }
  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }
  init(title: String, subtitle: String? = nil, songs: [Song]) {
    self.title = title
    self.subtitle = subtitle
    self.songs = songs
  }
  var body: some View {
    GeometryReader { geo in
      ScrollView {
        VStack(spacing: 18) {
          parallaxHero(width: geo.size.width)
          VStack(spacing: 4) {
            Text(title)
              .font(.title2.bold())
              .multilineTextAlignment(.center)
            Text(subtitle ?? "\(songs.count) songs")
              .font(.subheadline)
              .foregroundColor(.secondary)
          }
          .padding(.horizontal)
          if !songs.isEmpty {
            actionButtons
            LazyVStack(spacing: 0) {
              ForEach(songs) { song in
                SongRow(song: song, size: .regular, showsArtwork: showsArtwork)
                  .padding(.horizontal, AM.Spacing.screenMargin)
                  .padding(.vertical, 6)
                  .contentShape(Rectangle())
                  .onTapGesture {
                    play(song)
                  }
                  .songRowAccessibility(song: song) {
                    play(song)
                  }
                Divider().padding(.leading, showsArtwork ? 76 : 28)
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
        .padding(.bottom, AM.Spacing.l)
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
      .coordinateSpace(name: "browseScroll")
      .onPreferenceChange(BrowseScrollOffsetKey.self) { scrollOffset = $0 }
    }
    .navigationTitle(scrollOffset < -180 ? title : "")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(scrollOffset < -180 ? .visible : .hidden, for: .navigationBar)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: scrollOffset < -180)
  }

  private func play(_ song: Song) {
    AppHaptic.selection.play()
    audioManager.play(song: song, context: songs)
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
  private static let neuroFallbackURL: URL? = FallbackArtProvider.shared.randomURL
  @ViewBuilder
  private var heroArtwork: some View {
    let artURL = songs.first(where: { $0.hasOwnArtwork })?.imageURL ?? Self.neuroFallbackURL
    LoadingImage(url: artURL, cornerRadius: 0, contentMode: .fill)
  }
  private var actionButtons: some View {
    HStack(spacing: AM.Spacing.m) {
      Button {
        if let first = songs.first {
          AppHaptic.medium.play()
          audioManager.playInOrder(song: first, context: songs)
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
      .accessibilityValue(subtitle ?? "\(songs.count) songs")
      Button {
        AppHaptic.selection.play()
        audioManager.playShuffled(from: songs)
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
      .accessibilityValue(subtitle ?? "\(songs.count) songs")
    }
    .padding(.horizontal, AM.Spacing.screenMargin)
  }
}

private struct BrowseScrollOffsetKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
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
