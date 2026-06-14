import SwiftUI

struct SearchView: View {
  @StateObject var viewModel = SearchViewModel()
  @EnvironmentObject var audioManager: AudioPlayerManager
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var pendingSongID: String?
  @State private var playbackTask: Task<Void, Never>?

  private var stateChangeAnimation: Animation? {
    reduceMotion ? nil : .easeInOut(duration: 0.3)
  }

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  private var resultsMaxWidth: CGFloat {
    horizontalSizeClass == .regular ? 780 : .infinity
  }

  var body: some View {
    NavigationStack {
      Group {
        if viewModel.isSearching && viewModel.results.isEmpty {
          SearchResultsLoadingView()
            .transition(.opacity)
        } else if let errorMessage = viewModel.searchErrorMessage,
          viewModel.results.isEmpty,
          !viewModel.searchText.isEmpty
        {
          SearchErrorStateView(message: errorMessage) {
            viewModel.retrySearch()
          }
          .transition(.opacity.combined(with: .scale(scale: 0.98)))
        } else if viewModel.results.isEmpty && !viewModel.searchText.isEmpty {
          SearchNoResultsStateView(query: viewModel.searchText)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else if viewModel.results.isEmpty {
          BrowseCategoriesView()
            .transition(.opacity)
        } else {
          List {
            SearchResultsSummaryHeader(
              query: viewModel.searchText,
              resultCount: viewModel.results.count
            )
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 6, trailing: 16))
            .listRowSeparator(.hidden)

            ForEach(viewModel.results) { song in
              Button {
                playSelection(song)
              } label: {
                SearchResultRow(song: song, isPending: pendingSongID == song.id) {
                  playSelection(song)
                }
              }
              .disabled(pendingSongID != nil)
              .buttonStyle(PressableButtonStyle())
              .listRowBackground(Color.clear)
              .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
          }
          .listStyle(.plain)
          .scrollContentBackground(.hidden)
          .scrollIndicators(.hidden)
          .frame(maxWidth: resultsMaxWidth)
          .frame(maxWidth: .infinity)
          .accessibilityIdentifier("SearchResults.List")
          .transition(.opacity)
        }
      }
      .musicScreenBackground()
      .animation(
        stateChangeAnimation,
        value: "\(viewModel.isSearching)-\(viewModel.results.count)-\(viewModel.searchText.isEmpty)"
      )
      .navigationTitle("Search")
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          AccountToolbarButton()
        }
      }
      .searchable(
        text: $viewModel.searchText,
        placement: .navigationBarDrawer(displayMode: .always),
        prompt: "Songs, Artists, Lyrics, and More"
      )
      .onChange(of: audioManager.currentSong?.id) { _, currentSongID in
        guard currentSongID == pendingSongID else { return }
        pendingSongID = nil
      }
      .onDisappear {
        playbackTask?.cancel()
        playbackTask = nil
        pendingSongID = nil
      }
    }
  }

  private func playSelection(_ song: Song) {
    guard pendingSongID == nil else { return }
    guard audioManager.currentSong?.id != song.id else { return }
    AppHaptic.selection.play()
    pendingSongID = song.id
    let context = viewModel.results
    playbackTask?.cancel()
    playbackTask = Task { @MainActor in
      await Task.yield()
      guard !Task.isCancelled else { return }
      audioManager.play(song: song, context: context)
      try? await Task.sleep(nanoseconds: 400_000_000)
      guard !Task.isCancelled, pendingSongID == song.id else { return }
      pendingSongID = nil
    }
  }
}

private struct SearchResultsSummaryHeader: View {
  let query: String
  let resultCount: Int

  private var trimmedQuery: String {
    query.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline) {
        Text("Songs")
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(.primary)
        Spacer(minLength: 12)
        Text(resultCountText)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      if !trimmedQuery.isEmpty {
        Text("Results for \"\(trimmedQuery)\"")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .accessibilityElement(children: .combine)
  }

  private var resultCountText: String {
    resultCount == 1 ? "1 song" : "\(resultCount) songs"
  }
}

private struct BrowseCategoriesView: View {
  @StateObject private var genresVM = GenresViewModel()
  @StateObject private var topChartVM = TopChartViewModel()
  @StateObject private var publicPlaylistsVM = PublicPlaylistsViewModel()
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  private let topPicks: [(String, [Color])] = [
    (
      "Electronic",
      [Color(red: 0.33, green: 0.74, blue: 0.50), Color(red: 0.13, green: 0.42, blue: 0.30)]
    ),
    (
      "International",
      [Color(red: 0.92, green: 0.34, blue: 0.52), Color(red: 0.62, green: 0.16, blue: 0.34)]
    ),
    (
      "Dance",
      [Color(red: 0.34, green: 0.76, blue: 0.51), Color(red: 0.12, green: 0.46, blue: 0.34)]
    ),
    (
      "C-Pop",
      [Color(red: 0.91, green: 0.36, blue: 0.56), Color(red: 0.54, green: 0.15, blue: 0.33)]
    ),
    (
      "Spatial Audio",
      [Color(red: 0.97, green: 0.18, blue: 0.28), Color(red: 0.58, green: 0.06, blue: 0.16)]
    ),
    (
      "Mandopop",
      [Color(red: 0.90, green: 0.38, blue: 0.57), Color(red: 0.55, green: 0.14, blue: 0.34)]
    ),
    (
      "DJ Mixes",
      [Color(red: 0.33, green: 0.73, blue: 0.48), Color(red: 0.12, green: 0.38, blue: 0.30)]
    ),
    (
      "Replay Monthly",
      [Color(red: 0.95, green: 0.54, blue: 0.20), Color(red: 0.45, green: 0.38, blue: 0.95)]
    ),
    (
      "Charts",
      [Color(red: 0.45, green: 0.46, blue: 0.12), Color(red: 0.22, green: 0.22, blue: 0.08)]
    ),
    (
      "Jazz",
      [Color(red: 0.31, green: 0.67, blue: 0.82), Color(red: 0.10, green: 0.32, blue: 0.48)]
    ),
  ]
  private let activitiesAndMoods: [(String, [Color])] = [
    (
      "Workout",
      [Color(red: 0.95, green: 0.20, blue: 0.20), Color(red: 0.40, green: 0.05, blue: 0.05)]
    ),
    (
      "Chill",
      [Color(red: 0.20, green: 0.55, blue: 0.65), Color(red: 0.05, green: 0.20, blue: 0.30)]
    ),
    (
      "Focus",
      [Color(red: 0.30, green: 0.30, blue: 0.55), Color(red: 0.05, green: 0.05, blue: 0.20)]
    ),
    (
      "Sleep",
      [Color(red: 0.20, green: 0.20, blue: 0.45), Color(red: 0.05, green: 0.05, blue: 0.20)]
    ),
    (
      "Party",
      [Color(red: 0.90, green: 0.30, blue: 0.75), Color(red: 0.40, green: 0.05, blue: 0.40)]
    ),
    (
      "Romance",
      [Color(red: 0.95, green: 0.40, blue: 0.55), Color(red: 0.45, green: 0.10, blue: 0.20)]
    ),
  ]
  private let genres: [(String, [Color])] = [
    (
      "Pop", [Color(red: 0.90, green: 0.20, blue: 0.55), Color(red: 0.40, green: 0.05, blue: 0.30)]
    ),
    (
      "Hip-Hop",
      [Color(red: 0.60, green: 0.30, blue: 0.95), Color(red: 0.20, green: 0.05, blue: 0.45)]
    ),
    (
      "R&B", [Color(red: 0.95, green: 0.55, blue: 0.20), Color(red: 0.45, green: 0.20, blue: 0.05)]
    ),
    (
      "Rock",
      [Color(red: 0.85, green: 0.20, blue: 0.20), Color(red: 0.30, green: 0.05, blue: 0.05)]
    ),
    (
      "Country",
      [Color(red: 0.85, green: 0.65, blue: 0.30), Color(red: 0.45, green: 0.25, blue: 0.05)]
    ),
    (
      "Electronic",
      [Color(red: 0.10, green: 0.75, blue: 0.85), Color(red: 0.05, green: 0.30, blue: 0.45)]
    ),
    (
      "Latin",
      [Color(red: 0.95, green: 0.35, blue: 0.20), Color(red: 0.45, green: 0.10, blue: 0.05)]
    ),
    (
      "K-Pop",
      [Color(red: 0.95, green: 0.45, blue: 0.75), Color(red: 0.40, green: 0.10, blue: 0.40)]
    ),
    (
      "Jazz",
      [Color(red: 0.60, green: 0.45, blue: 0.20), Color(red: 0.25, green: 0.15, blue: 0.05)]
    ),
    (
      "Classical",
      [Color(red: 0.40, green: 0.55, blue: 0.40), Color(red: 0.10, green: 0.25, blue: 0.15)]
    ),
    (
      "Reggae",
      [Color(red: 0.30, green: 0.65, blue: 0.30), Color(red: 0.10, green: 0.30, blue: 0.10)]
    ),
    (
      "Soundtracks",
      [Color(red: 0.45, green: 0.45, blue: 0.55), Color(red: 0.15, green: 0.15, blue: 0.25)]
    ),
  ]
  private var usesWideHighlights: Bool {
    horizontalSizeClass == .regular
  }

  private var contentMaxWidth: CGFloat {
    horizontalSizeClass == .regular ? 1120 : .infinity
  }

  private var sectionHorizontalPadding: CGFloat {
    AM.Spacing.screenMargin
  }

  private var categoryColumns: [GridItem] {
    AM.Layout.adaptiveGridColumns(
      minimum: horizontalSizeClass == .compact ? 160 : 178,
      spacing: AM.Spacing.m
    )
  }

  private var featuredColumns: [GridItem] {
    AM.Layout.adaptiveGridColumns(
      minimum: horizontalSizeClass == .compact ? 160 : 232,
      spacing: AM.Spacing.m
    )
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: AM.Spacing.xxl) {
        if usesWideHighlights {
          wideHighlightsSection
        } else {
          featuredSection
          topPicksSection
        }
        section(title: "Activities & Moods", items: activitiesAndMoods)
        genresSection
        if !topChartVM.weeklyTrending.isEmpty {
          moreToExploreSection
        }
      }
      .frame(maxWidth: contentMaxWidth, alignment: .leading)
      .frame(maxWidth: .infinity)
      .padding(.top, AM.Spacing.s)
      .padding(.bottom, AM.Spacing.l)
    }
    .musicScreenBackground()
    .scrollIndicators(.hidden)
    .tabBarScrollInset()
    .refreshable {
      AppHaptic.selection.play()
      genresVM.loadIfNeeded()
      topChartVM.loadIfNeeded()
      publicPlaylistsVM.loadIfNeeded()
    }
    .onAppear {
      genresVM.loadIfNeeded()
      topChartVM.loadIfNeeded()
      publicPlaylistsVM.loadIfNeeded()
    }
  }

  private var wideHighlightsSection: some View {
    HStack(alignment: .top, spacing: AM.Spacing.xxl) {
      featuredSectionContent
        .frame(maxWidth: .infinity, alignment: .topLeading)
      topPicksSectionContent
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("SearchBrowse.WideHighlights")
  }

  private var featuredSection: some View {
    featuredSectionContent
  }

  private var featuredSectionContent: some View {
    VStack(alignment: .leading, spacing: AM.Spacing.m) {
      AMSectionHeader("Featured")
      featuredGrid
    }
    .accessibilityIdentifier("SearchBrowse.Featured")
  }

  private var featuredGrid: some View {
    LazyVGrid(columns: featuredColumns, spacing: AM.Spacing.m) {
      NavigationLink(
        destination: TopChartCollectionView(viewModel: topChartVM)
      ) {
        SearchFeaturedShortcutTile(
          title: "Twinskaraoke Top 100",
          subtitle: topChartVM.songs.isEmpty ? "Top songs" : "\(topChartVM.songs.count) songs",
          systemImage: "chart.line.uptrend.xyaxis",
          gradient: [
            Color(red: 0.98, green: 0.12, blue: 0.22),
            Color(red: 0.56, green: 0.02, blue: 0.12),
          ],
          artworkURL: topChartVM.songs.first?.imageURL
        )
      }
      .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78, haptic: .selection))
      .accessibilityLabel("Twinskaraoke Top 100")
      .accessibilityIdentifier("SearchCategory.TwinskaraokeTop100")
      .accessibilityValue("\(topChartVM.songs.count) songs")
      .accessibilityHint("Opens the Top 100 songs collection")

      NavigationLink(
        destination: PublicPlaylistsCollectionView(viewModel: publicPlaylistsVM)
      ) {
        SearchFeaturedShortcutTile(
          title: "Public Playlists",
          subtitle: publicPlaylistsVM.playlists.isEmpty
            ? "Community mixes"
            : "\(publicPlaylistsVM.playlists.count) playlists",
          systemImage: "music.note.list",
          gradient: [
            Color(red: 0.19, green: 0.55, blue: 0.96),
            Color(red: 0.12, green: 0.22, blue: 0.58),
          ],
          artworkURL: publicPlaylistsVM.playlists.first?.imageURL
        )
      }
      .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78, haptic: .selection))
      .accessibilityLabel("Public Playlists")
      .accessibilityIdentifier("SearchCategory.PublicPlaylists")
      .accessibilityValue("\(publicPlaylistsVM.playlists.count) playlists")
      .accessibilityHint("Opens public karaoke playlists")
    }
    .padding(.horizontal, sectionHorizontalPadding)
  }

  private var topPicksSection: some View {
    topPicksSectionContent
  }

  private var topPicksSectionContent: some View {
    VStack(alignment: .leading, spacing: AM.Spacing.m) {
      AMSectionHeader("Browse Categories")
      LazyVGrid(columns: categoryColumns, spacing: AM.Spacing.m) {
        categoryLinks(for: topPicks)
      }
      .padding(.horizontal, sectionHorizontalPadding)
    }
    .accessibilityIdentifier("SearchBrowse.Categories")
  }

  @ViewBuilder
  private func categoryLinks(for items: [(String, [Color])]) -> some View {
    ForEach(items, id: \.0) { item in
      NavigationLink(destination: SearchCategorySongCollectionView(title: item.0, query: item.0)) {
        CategoryTile(title: item.0, gradient: item.1)
      }
      .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78, haptic: .selection))
      .accessibilityLabel(item.0)
      .accessibilityIdentifier("SearchCategory.\(item.0.accessibilitySlug)")
      .accessibilityHint("Opens \(item.0) songs")
    }
  }

  private func section(title: String, items: [(String, [Color])]) -> some View {
    VStack(alignment: .leading, spacing: AM.Spacing.m) {
      AMSectionHeader(title)
      LazyVGrid(columns: categoryColumns, spacing: AM.Spacing.m) {
        categoryLinks(for: items)
      }
      .padding(.horizontal, sectionHorizontalPadding)
    }
  }

  private var genresSection: some View {
    VStack(alignment: .leading, spacing: AM.Spacing.m) {
      AMSectionHeader("Genres")
      if genresVM.isLoading && genresVM.genres.isEmpty {
        LazyVGrid(columns: categoryColumns, spacing: AM.Spacing.m) {
          ForEach(0..<6, id: \.self) { _ in
            CategoryTileSkeleton()
          }
        }
        .padding(.horizontal, sectionHorizontalPadding)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
      } else if genresVM.genres.isEmpty {
        MusicEmptyState(
          systemImage: "square.grid.2x2",
          title: "Genres Unavailable",
          message: "Pull down to refresh browse categories."
        )
        .padding(.top, AM.Spacing.s)
        .transition(.opacity)
      } else {
        LazyVGrid(columns: categoryColumns, spacing: AM.Spacing.m) {
          ForEach(genresVM.genres) { genre in
            let palette = paletteForGenre(genre.name)
            NavigationLink(
              destination: GenreDetailView(genre: genre, viewModel: genresVM, palette: palette)
            ) {
              CategoryTile(
                title: genre.name,
                gradient: palette,
                artworkURL: genresVM.artworkURLs[genre.id]
              )
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78, haptic: .selection))
            .accessibilityLabel(genre.name)
            .accessibilityIdentifier("SearchCategory.\(genre.name.accessibilitySlug)")
            .accessibilityValue("\(genre.songCount) songs")
            .accessibilityHint("Opens \(genre.name) songs")
            .onAppear { genresVM.loadMoreIfNeeded(current: genre) }
          }
        }
        .padding(.horizontal, sectionHorizontalPadding)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
      }
      if genresVM.isLoadingMore {
        LoadingIndicator(size: 32)
          .frame(maxWidth: .infinity)
          .padding(.vertical, AM.Spacing.m)
      }
    }
  }
  private var moreToExploreSection: some View {
    VStack(alignment: .leading, spacing: AM.Spacing.m) {
      AMSectionHeader(
        "More to Explore",
        destination: BrowseSongCollectionView(
          title: "More to Explore", songs: topChartVM.weeklyTrending))
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: AM.Spacing.l) {
          ForEach(topChartVM.weeklyTrending) { song in
            MusicGridCard(song: song, context: topChartVM.weeklyTrending)
          }
        }
        .padding(.horizontal, sectionHorizontalPadding)
      }
    }
  }
  private func paletteForGenre(_ name: String) -> [Color] {
    if let match = genres.first(where: {
      $0.0.localizedCaseInsensitiveCompare(name) == .orderedSame
    }) {
      return match.1
    }
    let stable = genres[abs(name.hashValue) % genres.count]
    return stable.1
  }
}

private struct TopChartCollectionView: View {
  @ObservedObject var viewModel: TopChartViewModel

  var body: some View {
    BrowseSongCollectionView(
      title: "Twinskaraoke Top 100",
      subtitle: "\(viewModel.songs.count) songs",
      songs: viewModel.songs
    )
    .task {
      viewModel.loadIfNeeded()
    }
  }
}

private struct PublicPlaylistsCollectionView: View {
  @ObservedObject var viewModel: PublicPlaylistsViewModel

  var body: some View {
    PlaylistListView(
      title: "Public Playlists",
      playlists: viewModel.playlists,
      apiURL: { startIndex, pageSize in
        viewModel.urlForList(startIndex: startIndex, pageSize: pageSize)
      }
    )
    .task {
      viewModel.loadIfNeeded()
    }
  }
}

struct GenreDetailView: View {
  let genre: GenreSummary
  @ObservedObject var viewModel: GenresViewModel
  let palette: [Color]
  @EnvironmentObject var audioManager: AudioPlayerManager
  var body: some View {
    let songs = viewModel.allSongs[genre.id] ?? []
    BrowseSongCollectionView(
      title: genre.name,
      subtitle: "\(genre.songCount) songs",
      songs: songs
    )
  }
}

struct SearchCategorySongCollectionView: View {
  let title: String
  let query: String
  @StateObject private var loader: SearchCategorySongsViewModel
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true

  private var categoryStateAnimation: Animation? {
    reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.84)
  }

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  init(title: String, query: String) {
    self.title = title
    self.query = query
    _loader = StateObject(wrappedValue: SearchCategorySongsViewModel(query: query))
  }

  var body: some View {
    Group {
      if (!loader.hasLoaded || loader.isLoading) && loader.songs.isEmpty {
        SearchCategoryLoadingView(title: title)
          .transition(.opacity)
      } else if loader.songs.isEmpty {
        SearchCategoryEmptyView(message: loader.emptyStateMessage) {
          loader.refresh()
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
      } else {
        BrowseSongCollectionView(
          title: title,
          subtitle: "\(loader.songs.count) songs",
          songs: loader.songs
        )
      }
    }
    .musicScreenBackground()
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .refreshable {
      AppHaptic.selection.play()
      loader.refresh()
    }
    .task {
      loader.loadIfNeeded()
    }
    .animation(categoryStateAnimation, value: loader.isLoading)
    .animation(categoryStateAnimation, value: loader.songs.count)
  }
}

private struct SearchResultsLoadingView: View {
  var body: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(0..<9, id: \.self) { _ in
          SearchRowSkeleton()
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
          Divider()
            .padding(.leading, 76)
        }
      }
      .padding(.top, 8)
      .padding(.bottom, AM.Spacing.l)
    }
    .scrollIndicators(.hidden)
    .tabBarScrollInset()
    .accessibilityLabel("Searching songs")
  }
}

private struct SearchErrorStateView: View {
  let message: String
  let onRetry: () -> Void

  var body: some View {
    SearchRecoveryStateView(
      systemImage: "wifi.exclamationmark",
      title: "Search Unavailable",
      message: message,
      actionTitle: "Try Again",
      actionIcon: "arrow.clockwise",
      hints: [
        ("Network", "Check Wi-Fi or cellular data"),
        ("Backend", "The karaoke catalog may need a moment"),
      ],
      onAction: onRetry
    )
    .accessibilityLabel("Search unavailable")
    .accessibilityHint("Runs the last search again")
  }
}

private struct SearchNoResultsStateView: View {
  let query: String
  private let suggestions = [
    ("Hits", "sparkles"),
    ("New Releases", "calendar"),
    ("K-Pop", "music.mic"),
    ("Romance", "heart"),
  ]

  var body: some View {
    VStack(spacing: AM.Spacing.xl) {
      SearchStateGlyph(systemImage: "magnifyingglass")
      VStack(spacing: AM.Spacing.s) {
        Text("No Results")
          .font(.system(size: 22, weight: .bold))
          .foregroundColor(.primary)
          .multilineTextAlignment(.center)
        Text("No songs matched \"\(query.trimmingCharacters(in: .whitespacesAndNewlines))\".")
          .font(.system(size: 15))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .lineLimit(3)
      }

      VStack(alignment: .leading, spacing: AM.Spacing.m) {
        Text("Explore instead")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.secondary)
          .textCase(.uppercase)
        LazyVGrid(
          columns: AM.Layout.adaptiveGridColumns(minimum: 132, spacing: AM.Spacing.s),
          spacing: AM.Spacing.s
        ) {
          ForEach(suggestions, id: \.0) { suggestion in
            NavigationLink(
              destination: SearchCategorySongCollectionView(
                title: suggestion.0,
                query: suggestion.0
              )
            ) {
              Label(suggestion.0, systemImage: suggestion.1)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.appSecondaryBackground, in: Capsule())
                .overlay {
                  Capsule()
                    .stroke(Color.appDivider, lineWidth: 0.6)
                }
            }
            .buttonStyle(PressableButtonStyle(scale: 0.94, dim: 0.78, haptic: .selection))
          }
        }
      }
      .frame(maxWidth: 340)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, AM.Spacing.screenMargin)
    .accessibilityElement(children: .contain)
  }
}

private struct SearchRecoveryStateView: View {
  let systemImage: String
  let title: String
  let message: String
  let actionTitle: String
  let actionIcon: String
  let hints: [(String, String)]
  let onAction: () -> Void
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var hasAppeared = false

  private var entranceAnimation: Animation? {
    reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82)
  }

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  var body: some View {
    VStack(spacing: AM.Spacing.xl) {
      SearchStateGlyph(systemImage: systemImage)
        .scaleEffect(hasAppeared ? 1 : 0.94)
        .opacity(hasAppeared ? 1 : 0)

      VStack(spacing: AM.Spacing.s) {
        Text(title)
          .font(.system(size: 22, weight: .bold))
          .foregroundColor(.primary)
          .multilineTextAlignment(.center)
        Text(message)
          .font(.system(size: 15))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .lineLimit(3)
      }
      .frame(maxWidth: 330)

      Button {
        AppHaptic.selection.play()
        onAction()
      } label: {
        Label(actionTitle, systemImage: actionIcon)
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.white)
          .padding(.horizontal, AM.Spacing.xl)
          .padding(.vertical, 11)
          .background(Color.appAccent, in: Capsule())
          .shadow(color: Color.appAccent.opacity(0.28), radius: 10, y: 4)
      }
      .buttonStyle(PressableButtonStyle(scale: 0.94, dim: 0.78, haptic: .selection))

      VStack(spacing: AM.Spacing.s) {
        ForEach(hints, id: \.0) { hint in
          HStack(spacing: AM.Spacing.s) {
            Circle()
              .fill(Color.appAccent.opacity(0.22))
              .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
              Text(hint.0)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
              Text(hint.1)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
          }
          .padding(.horizontal, AM.Spacing.m)
          .padding(.vertical, AM.Spacing.s)
          .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
        }
      }
      .frame(maxWidth: 340)
      .opacity(hasAppeared ? 1 : 0)
      .offset(y: hasAppeared ? 0 : 10)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, AM.Spacing.screenMargin)
    .onAppear {
      withAnimation(entranceAnimation) {
        hasAppeared = true
      }
    }
  }
}

private struct SearchStateGlyph: View {
  let systemImage: String
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var isPulsing = false

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  var body: some View {
    ZStack {
      Circle()
        .fill(Color.appAccent.opacity(isPulsing ? 0.16 : 0.08))
        .frame(width: 104, height: 104)
        .scaleEffect(isPulsing ? 1.08 : 0.96)
      Circle()
        .fill(Color.appAccent.opacity(0.12))
        .frame(width: 76, height: 76)
      Image(systemName: systemImage)
        .font(.system(size: 31, weight: .semibold))
        .foregroundColor(.appAccent)
    }
    .onAppear {
      guard !reduceMotion else {
        isPulsing = false
        return
      }
      withAnimation(.easeInOut(duration: 1.45).repeatForever(autoreverses: true)) {
        isPulsing = true
      }
    }
    .onChange(of: reduceMotion) { _, reduceMotion in
      if reduceMotion {
        withAnimation(nil) {
          isPulsing = false
        }
      } else {
        withAnimation(.easeInOut(duration: 1.45).repeatForever(autoreverses: true)) {
          isPulsing = true
        }
      }
    }
    .accessibilityHidden(true)
  }
}

private struct SearchCategoryLoadingView: View {
  let title: String
  var body: some View {
    ScrollView {
      VStack(spacing: 18) {
        RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous)
          .fill(Color.appPlaceholderPrimary)
          .frame(width: 228, height: 228)
          .overlay {
            LoadingIndicator(size: 34)
          }
          .amShadow(AM.Shadow.heroIdle)
          .padding(.top, 8)

        VStack(spacing: 8) {
          Text(title)
            .font(.title2.bold())
            .multilineTextAlignment(.center)
          Text("Loading songs")
            .font(.subheadline)
            .foregroundColor(.secondary)
        }

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
                  .frame(width: 124, height: 9)
              }
              Spacer()
            }
            .padding(.horizontal, AM.Spacing.screenMargin)
            .padding(.vertical, 10)
            Divider().padding(.leading, 76)
          }
        }
      }
      .padding(.bottom, AM.Spacing.l)
    }
    .tabBarScrollInset()
    .accessibilityLabel("Loading \(title) songs")
  }
}

private struct SearchCategoryEmptyView: View {
  let message: String
  let onRetry: () -> Void
  var body: some View {
    SearchRecoveryStateView(
      systemImage: "music.note.list",
      title: "No Songs",
      message: message,
      actionTitle: "Refresh",
      actionIcon: "arrow.clockwise",
      hints: [
        ("Category", "Try a broader style or mood"),
        ("Catalog", "New songs appear as the library updates"),
      ],
      onAction: onRetry
    )
    .accessibilityLabel("No songs")
    .accessibilityHint("Refreshes this category")
  }
}

private struct SearchFeaturedShortcutTile: View {
  let title: String
  let subtitle: String
  let systemImage: String
  let gradient: [Color]
  var artworkURL: URL? = nil
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  private var isCompactWidth: Bool {
    horizontalSizeClass == .compact
  }

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      background
      LinearGradient(
        colors: [Color.black.opacity(0.02), Color.black.opacity(0.38)],
        startPoint: .top,
        endPoint: .bottom
      )
      .allowsHitTesting(false)

      Image(systemName: systemImage)
        .font(.system(size: isCompactWidth ? 52 : 60, weight: .bold))
        .foregroundStyle(.white.opacity(0.20))
        .offset(x: isCompactWidth ? 96 : 128, y: isCompactWidth ? -42 : -50)
        .allowsHitTesting(false)

      VStack(alignment: .leading, spacing: 5) {
        Text(title)
          .font(.system(size: isCompactWidth ? 20 : 22, weight: .bold))
          .foregroundColor(.white)
          .lineLimit(2)
          .minimumScaleFactor(0.82)
        Text(subtitle)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.white.opacity(0.82))
          .lineLimit(1)
      }
      .shadow(color: .black.opacity(0.34), radius: 4, x: 0, y: 1)
      .padding(AM.Spacing.l)
      .allowsHitTesting(false)
    }
    .frame(height: isCompactWidth ? 124 : 144)
    .clipShape(RoundedRectangle(cornerRadius: AM.Radius.tile, style: .continuous))
    .amShadow(AM.Shadow.card)
    .contentShape(RoundedRectangle(cornerRadius: AM.Radius.tile, style: .continuous))
  }

  @ViewBuilder
  private var background: some View {
    if let artworkURL {
      LoadingImage(url: artworkURL, cornerRadius: 0, contentMode: .fill)
        .allowsHitTesting(false)
      LinearGradient(
        colors: gradient.map { $0.opacity(0.76) },
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .allowsHitTesting(false)
    } else {
      LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
        .allowsHitTesting(false)
    }
  }
}

private struct CategoryTile: View {
  let title: String
  let gradient: [Color]
  var artworkURL: URL? = nil
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  private var isCompactWidth: Bool {
    horizontalSizeClass == .compact
  }

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      if let artworkURL {
        LoadingImage(url: artworkURL, cornerRadius: 0, contentMode: .fill)
          .allowsHitTesting(false)
        LinearGradient(
          colors: gradient.map { $0.opacity(0.70) },
          startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .allowsHitTesting(false)
      } else {
        LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
          .allowsHitTesting(false)
      }
      LinearGradient(
        colors: [Color.black.opacity(0.0), Color.black.opacity(0.24)],
        startPoint: .top,
        endPoint: .bottom
      )
      .allowsHitTesting(false)
      Image(systemName: symbol)
        .font(.system(size: isCompactWidth ? 48 : 54, weight: .bold))
        .foregroundStyle(.white.opacity(0.18))
        .offset(x: isCompactWidth ? 64 : 70, y: isCompactWidth ? -18 : -22)
        .allowsHitTesting(false)
      Text(title)
        .font(.system(size: isCompactWidth ? 19 : 20, weight: .bold))
        .foregroundColor(.white)
        .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 1)
        .padding(AM.Spacing.m)
        .lineLimit(2)
        .minimumScaleFactor(0.82)
        .allowsHitTesting(false)
    }
    .frame(height: isCompactWidth ? 92 : 102)
    .clipShape(RoundedRectangle(cornerRadius: AM.Radius.tile, style: .continuous))
    .amShadow(AM.Shadow.card)
    .contentShape(RoundedRectangle(cornerRadius: AM.Radius.tile, style: .continuous))
  }

  private var symbol: String {
    switch title {
    case "Charts": return "chart.bar.fill"
    case "Public Playlists": return "music.note.list"
    case "Jazz": return "music.quarternote.3"
    case "Replay Monthly": return "clock.arrow.circlepath"
    case "Spatial Audio": return "airpodspro"
    case "Twinskaraoke Top 100": return "chart.line.uptrend.xyaxis"
    case "Behind the Songs": return "slider.horizontal.3"
    default: return "music.note"
    }
  }
}

private extension String {
  var accessibilitySlug: String {
    String(unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
  }
}

private struct CategoryTileSkeleton: View {
  var body: some View {
    RoundedRectangle(cornerRadius: AM.Radius.tile, style: .continuous)
      .fill(Color.appPlaceholderPrimary)
      .frame(height: 98)
      .overlay(alignment: .topLeading) {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(Color.appPlaceholderSecondary)
          .frame(width: 112, height: 16)
          .padding(AM.Spacing.m)
      }
      .overlay(alignment: .bottomTrailing) {
        Circle()
          .fill(Color.appPlaceholderSecondary)
          .frame(width: 26, height: 26)
          .padding(8)
      }
      .redacted(reason: .placeholder)
      .accessibilityLabel("Loading category")
  }
}

struct SearchResultRow: View {
  let song: Song
  var isPending: Bool = false
  let onPlay: () -> Void

  var body: some View {
    SongRow(
      song: song,
      size: .regular,
      trailing: isPending ? AnyView(LoadingIndicator(size: 18)) : nil
    )
    .songRowAccessibility(song: song, isPending: isPending, onPlay: onPlay)
  }
}

struct SearchRowSkeleton: View {
  var body: some View {
    SongRowSkeleton(size: .regular)
  }
}
