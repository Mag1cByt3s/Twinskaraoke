import SwiftUI

struct SearchView: View {
  @StateObject var viewModel = SearchViewModel()
  @EnvironmentObject var audioManager: AudioPlayerManager
  @State private var pendingSongID: String?
  @State private var playbackTask: Task<Void, Never>?
  var body: some View {
    NavigationStack {
      Group {
        if viewModel.isSearching {
          LoadingIndicator(size: 64)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 80)
            .transition(.opacity)
        } else if viewModel.results.isEmpty && !viewModel.searchText.isEmpty {
          VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
              .font(.system(size: 42))
              .foregroundColor(.secondary)
            Text("No results for \"\(viewModel.searchText)\"")
              .foregroundColor(.secondary)
              .multilineTextAlignment(.center)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .transition(.opacity)
        } else if viewModel.results.isEmpty {
          BrowseCategoriesView()
            .transition(.opacity)
        } else {
          List(viewModel.results) { song in
            Button {
              playSelection(song)
            } label: {
              SearchResultRow(song: song, isPending: pendingSongID == song.id)
            }
            .disabled(pendingSongID != nil)
            .buttonStyle(PressableButtonStyle())
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
          }
          .listStyle(.plain)
          .transition(.opacity)
        }
      }
      .animation(
        .easeInOut(duration: 0.3),
        value: "\(viewModel.isSearching)-\(viewModel.results.count)-\(viewModel.searchText.isEmpty)"
      )
      .navigationTitle("Search")
      .searchable(
        text: $viewModel.searchText,
        placement: .navigationBarDrawer(displayMode: .always),
        prompt: "Songs, Artists, Lyrics, and More"
      )
      .onChange(of: audioManager.currentSong?.id) { currentSongID in
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

private struct BrowseCategoriesView: View {
  @StateObject private var genresVM = GenresViewModel()
  @StateObject private var topChartVM = TopChartViewModel()
  private let topPicks: [(String, [Color])] = [
    (
      "Twinskaraoke Top 100",
      [Color(red: 0.96, green: 0.30, blue: 0.45), Color(red: 0.55, green: 0.10, blue: 0.30)]
    ),
    (
      "Charts",
      [Color(red: 0.20, green: 0.55, blue: 0.95), Color(red: 0.10, green: 0.20, blue: 0.55)]
    ),
    (
      "Hits",
      [Color(red: 0.95, green: 0.45, blue: 0.10), Color(red: 0.55, green: 0.15, blue: 0.05)]
    ),
    (
      "New Releases",
      [Color(red: 0.10, green: 0.75, blue: 0.85), Color(red: 0.05, green: 0.30, blue: 0.45)]
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
  let columns = [
    GridItem(.flexible(), spacing: AM.Spacing.m), GridItem(.flexible(), spacing: AM.Spacing.m),
  ]
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: AM.Spacing.xxl) {
        topPicksSection
        section(title: "Activities & Moods", items: activitiesAndMoods)
        genresSection
        if !topChartVM.weeklyTrending.isEmpty {
          moreToExploreSection
        }
      }
      .padding(.top, AM.Spacing.s)
      .padding(.bottom, AM.Spacing.l)
    }
    .onAppear {
      genresVM.loadIfNeeded()
      topChartVM.loadIfNeeded()
    }
  }
  private var topPicksSection: some View {
    VStack(alignment: .leading, spacing: AM.Spacing.m) {
      AMSectionHeader("Browse Categories")
      LazyVGrid(columns: columns, spacing: AM.Spacing.m) {
        ForEach(topPicks, id: \.0) { item in
          if item.0 == "Twinskaraoke Top 100" {
            NavigationLink(
              destination: BrowseSongCollectionView(
                title: "Twinskaraoke Top 100",
                subtitle: "\(topChartVM.songs.count) songs",
                songs: topChartVM.songs
              )
            ) {
              CategoryTile(
                title: item.0,
                gradient: item.1,
                artworkURL: topChartVM.songs.first?.imageURL
              )
            }
            .buttonStyle(PressableButtonStyle())
          } else {
            CategoryTile(title: item.0, gradient: item.1)
          }
        }
      }
      .padding(.horizontal, AM.Spacing.screenMargin)
    }
  }
  private func section(title: String, items: [(String, [Color])]) -> some View {
    VStack(alignment: .leading, spacing: AM.Spacing.m) {
      AMSectionHeader(title)
      LazyVGrid(columns: columns, spacing: AM.Spacing.m) {
        ForEach(items, id: \.0) { item in
          CategoryTile(title: item.0, gradient: item.1)
        }
      }
      .padding(.horizontal, AM.Spacing.screenMargin)
    }
  }
  private var genresSection: some View {
    VStack(alignment: .leading, spacing: AM.Spacing.m) {
      AMSectionHeader("Genres")
      LazyVGrid(columns: columns, spacing: AM.Spacing.m) {
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
          .buttonStyle(PressableButtonStyle())
          .onAppear { genresVM.loadMoreIfNeeded(current: genre) }
        }
      }
      .padding(.horizontal, AM.Spacing.screenMargin)
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
            HomeSongCard(song: song, context: topChartVM.weeklyTrending)
          }
        }
        .padding(.horizontal, AM.Spacing.screenMargin)
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

private struct CategoryTile: View {
  let title: String
  let gradient: [Color]
  var artworkURL: URL? = nil
  var body: some View {
    ZStack(alignment: .topLeading) {
      if let artworkURL {
        LoadingImage(url: artworkURL, cornerRadius: 0, contentMode: .fill)
          .allowsHitTesting(false)
        LinearGradient(
          colors: gradient.map { $0.opacity(0.55) },
          startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .allowsHitTesting(false)
      } else {
        LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
          .allowsHitTesting(false)
      }
      LinearGradient(
        colors: [Color.white.opacity(0.18), Color.white.opacity(0.0)],
        startPoint: .topLeading,
        endPoint: .center
      )
      .allowsHitTesting(false)
      Text(title)
        .font(.system(size: 17, weight: .bold))
        .foregroundColor(.white)
        .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 1)
        .padding(AM.Spacing.m)
        .allowsHitTesting(false)
    }
    .frame(height: 96)
    .clipShape(RoundedRectangle(cornerRadius: AM.Radius.tile, style: .continuous))
    .contentShape(RoundedRectangle(cornerRadius: AM.Radius.tile, style: .continuous))
  }
}

struct SearchResultRow: View {
  let song: Song
  var isPending: Bool = false
  var body: some View {
    SongRow(
      song: song,
      size: .regular,
      trailing: isPending ? AnyView(LoadingIndicator(size: 18)) : nil
    )
  }
}

struct SearchRowSkeleton: View {
  var body: some View {
    SongRowSkeleton(size: .regular)
  }
}
