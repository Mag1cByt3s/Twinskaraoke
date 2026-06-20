import Combine
import Foundation
import SwiftUI

@MainActor
final class PlaylistSongCountStore: ObservableObject {
  static let shared = PlaylistSongCountStore()

  @Published private var resolvedCounts: [String: Int] = [:]
  private var loadingIDs: Set<String> = []

  func displayedCount(for playlist: Playlist) -> Int? {
    if let resolved = resolvedCounts[playlist.id], resolved > 0 {
      return resolved
    }
    let embeddedCount = playlist.songListDTOs?.count ?? 0
    if embeddedCount > 0 {
      return max(playlist.songCount, embeddedCount)
    }
    return playlist.songCount > 0 ? playlist.songCount : nil
  }

  func loadIfNeeded(for playlist: Playlist) {
    guard !playlist.isFavorites, !playlist.isPersonal else { return }
    guard playlist.songCount == 0 else { return }
    guard resolvedCounts[playlist.id] == nil else { return }
    guard !loadingIDs.contains(playlist.id) else { return }

    Task {
      loadingIDs.insert(playlist.id)
      let count: Int?
      do {
        count = try await KaraokeAPIClient.playlistSongCount(id: playlist.id)
      } catch {
        count = nil
      }

      loadingIDs.remove(playlist.id)
      if let count, count > 0 {
        resolvedCounts[playlist.id] = count
      }
    }
  }
}

struct PlaylistSongCountLabel: View {
  let playlist: Playlist
  var fallbackText: String? = nil

  @ObservedObject private var countStore = PlaylistSongCountStore.shared

  private var labelText: String? {
    if let count = countStore.displayedCount(for: playlist) {
      return SongCountText.songs(count)
    }
    return fallbackText
  }

  var body: some View {
    Group {
      if let labelText {
        Text(labelText)
      }
    }
    .task(id: playlist.id) {
      countStore.loadIfNeeded(for: playlist)
    }
  }
}

struct LibraryView: View {
  @StateObject var viewModel = PlaylistsViewModel()
  @StateObject private var recentSongsViewModel = LibrarySongsViewModel()
  @ObservedObject private var savedStore = SavedPlaylistsStore.shared
  @ObservedObject private var addedTracker = RecentlyAddedTracker.shared
  @ObservedObject private var favorites = FavoritesManager.shared
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var showCreateSheet = false
  @State private var path = NavigationPath()
  let cols = AM.Layout.playlistGridColumns

  private var usesCompactToolbar: Bool {
    horizontalSizeClass == .compact
  }

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  var body: some View {
    let recentlyAddedSongs = Array(recentSongsViewModel.songs.prefix(12))
    NavigationStack(path: $path) {
      GeometryReader { proxy in
        ScrollView {
          libraryOverview(recentlyAddedSongs: recentlyAddedSongs, availableWidth: proxy.size.width)
          .padding(.top, AM.Spacing.s)
          .padding(.bottom, AM.Spacing.l)
        }
        .scrollIndicators(.hidden)
        .smoothScrolling()
        .tabBarScrollInset()
        .musicScreenBackground()
      }
      .navigationTitle("Library")
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          HStack(spacing: usesCompactToolbar ? 4 : 6) {
            LibraryToolbarActions(
              compact: usesCompactToolbar,
              onCreatePlaylist: {
                AppHaptic.selection.play()
                showCreateSheet = true
              },
              onRefresh: refreshLibrary
            )
            AccountToolbarButton()
          }
        }
      }
      .refreshable {
        refreshLibrary()
      }
      .navigationDestination(for: Playlist.self) { playlist in
        PlaylistDetailView(playlist: playlist)
      }
      .onAppear {
        favorites.loadIfNeeded()
        viewModel.fetchPlaylists()
        viewModel.fetchFavoriteSongs()
        recentSongsViewModel.loadIfNeeded()
      }
      .onChange(of: favorites.favoriteIDs) { _, _ in
        viewModel.fetchFavoriteSongs()
      }
      .animation(
        reduceMotion ? nil : AppMotion.spring(response: 0.34, dampingFraction: 0.84),
        value: recentlyAddedSongs.map(\.id))
      .sheet(isPresented: $showCreateSheet) {
        CreatePlaylistSheet()
      }
    }
  }

  @ViewBuilder
  private func libraryOverview(recentlyAddedSongs: [Song], availableWidth: CGFloat) -> some View {
    if AM.Layout.usesWideCanvas(
      horizontalSizeClass: horizontalSizeClass,
      availableWidth: availableWidth
    ) {
      wideLibraryOverview(recentlyAddedSongs: recentlyAddedSongs)
    } else {
      compactLibraryOverview(recentlyAddedSongs: recentlyAddedSongs)
    }
  }

  private func compactLibraryOverview(recentlyAddedSongs: [Song]) -> some View {
    VStack(alignment: .leading, spacing: AM.Spacing.xxl) {
      libraryPrimaryLinks

      if !recentlyAddedSongs.isEmpty {
        RecentlyAddedSection(songs: recentlyAddedSongs)
      }
    }
  }

  private func wideLibraryOverview(recentlyAddedSongs: [Song]) -> some View {
    VStack(alignment: .leading, spacing: AM.Spacing.xxl) {
      if let featuredPlaylist = featuredWidePlaylist {
        WideLibraryHero(
          playlist: featuredPlaylist,
          songs: featuredPlaylist.songListDTOs ?? viewModel.favoriteSongs
        )
      }

      HStack(alignment: .top, spacing: AM.Spacing.xxl) {
        VStack(alignment: .leading, spacing: AM.Spacing.xxl) {
          LibraryOverviewGroup(title: "Library") {
            libraryPrimaryLinksContent
          }
        }
        .frame(
          minWidth: AM.Layout.wideInspectorWidth,
          idealWidth: AM.Layout.wideInspectorWidth,
          maxWidth: 400
        )

        if !recentlyAddedSongs.isEmpty {
          RecentlyAddedSection(songs: recentlyAddedSongs, horizontalPadding: 0, headerHorizontalPadding: 0)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
      }
      .frame(maxWidth: AM.Layout.wideContentMaxWidth, alignment: .topLeading)
      .padding(.horizontal, AM.Spacing.screenMargin)
      .accessibilityIdentifier("Library.WideOverview")
    }
    .frame(maxWidth: .infinity, alignment: .top)
  }

  private var featuredWidePlaylist: Playlist? {
    let all = viewModel.allPlaylists(saved: savedStore.playlists)
    if let favoritesPlaylist = all.first(where: { $0.isFavorites }) {
      return favoritesPlaylist
    }
    if let saved = savedStore.playlists.first {
      return saved
    }
    return all.first
  }

  private var libraryPrimaryLinks: some View {
    libraryPrimaryLinksContent
      .padding(.horizontal, AM.Spacing.screenMargin)
  }

  private var libraryPrimaryLinksContent: some View {
    VStack(spacing: 0) {
      libraryLink(
        icon: "music.note.list",
        title: "Playlists",
        destination: PlaylistsGridScreen(viewModel: viewModel)
      )
      libraryLink(icon: "music.mic", title: "Artists", destination: ArtistsView())
      libraryLink(
        icon: "square.stack",
        title: "Albums",
        destination: LibraryCollectionListView(kind: .albums)
      )
      libraryLink(icon: "music.note", title: "Songs", destination: LibrarySongsView())
      libraryLink(
        icon: "arrow.down.circle",
        title: "Downloaded",
        destination: DownloadedSongsView()
      )
      libraryLink(icon: "play.rectangle", title: "Video Gallery", destination: VideoGalleryView())
      libraryLink(icon: "paintpalette", title: "Art Gallery", destination: ArtGalleryView())
      libraryLink(
        icon: "music.quarternote.3",
        title: "Composers",
        destination: LibraryCollectionListView(kind: .composers)
      )
      libraryLink(
        icon: "rectangle.stack",
        title: "Compilations",
        destination: LibraryCollectionListView(kind: .compilations)
      )
      libraryLink(
        icon: "shuffle",
        title: "Random Songs",
        destination: RandomSongsView(),
        showsDivider: false
      )
    }
  }

  private var librarySecondaryLinks: some View {
    EmptyView()
  }

  private var librarySecondaryLinksContent: some View {
    EmptyView()
  }

  @ViewBuilder
  private func libraryLink<Destination: View>(
    icon: String,
    title: String,
    subtitle: String? = nil,
    destination: Destination,
    showsDivider: Bool = true
  ) -> some View {
    NavigationLink {
      destination
    } label: {
      LibraryRow(icon: icon, color: .appAccent, title: title, subtitle: subtitle)
        .contentShape(Rectangle())
    }
    .buttonStyle(PressableButtonStyle(scale: 0.985, dim: 0.78, haptic: .selection))

    if showsDivider {
      LibraryLinkSeparator()
    }
  }

  private func refreshLibrary() {
    AppHaptic.selection.play()
    favorites.loadIfNeeded()
    viewModel.fetchPlaylists()
    viewModel.fetchFavoriteSongs()
    recentSongsViewModel.refresh()
  }
}

private struct LibraryToolbarActions: View {
  var compact = false
  let onCreatePlaylist: () -> Void
  let onRefresh: () -> Void

  var body: some View {
    ToolbarCapsuleMenu(accessibilityLabel: "Library Actions") {
      Button(action: onCreatePlaylist) {
        Label("New Playlist", systemImage: "text.badge.plus")
      }
      Button(action: onRefresh) {
        Label("Refresh Library", systemImage: "arrow.clockwise")
      }
    }
  }
}

private struct LibraryLinkSeparator: View {
  var body: some View {
    Rectangle()
      .fill(Color.appDivider.opacity(0.6))
      .frame(height: 0.5)
      .padding(.leading, 44)
  }
}

private struct LibraryOverviewGroup<Content: View>: View {
  let title: String
  let content: Content

  init(title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: AM.Spacing.s) {
      Text(title)
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .padding(.horizontal, AM.Spacing.s)

      content
        .padding(.horizontal, 0)
    }
  }
}

private struct WideLibraryHero: View {
  let playlist: Playlist
  let songs: [Song]

  var body: some View {
    HStack(alignment: .center, spacing: AM.Spacing.xxl) {
      PlaylistArtwork(playlist: playlist, cornerRadius: AM.Radius.hero)
        .frame(width: 220, height: 220)
        .clipShape(RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous))
        .amShadow(AM.Shadow.heroPlaying)

      VStack(alignment: .leading, spacing: AM.Spacing.l) {
        VStack(alignment: .leading, spacing: 5) {
          Text(playlist.isFavorites ? "Favourite Songs" : "Featured Playlist")
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
          Text(playlist.name)
            .font(.largeTitle.bold())
            .foregroundStyle(.primary)
            .lineLimit(2)
            .minimumScaleFactor(0.74)
          PlaylistSongCountLabel(playlist: playlist, fallbackText: "Playlist")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        HStack(spacing: AM.Spacing.m) {
          Button {
            if let first = playableSongs.first {
              AppHaptic.selection.play()
              AudioPlayerManager.shared.playInOrder(song: first, context: playableSongs)
            }
          } label: {
            LibraryActionButtonLabel(symbol: "play.fill", text: "Play", style: .primary)
          }
          .disabled(playableSongs.isEmpty)
          .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.82))

          Button {
            AppHaptic.selection.play()
            AudioPlayerManager.shared.playShuffled(from: playableSongs)
          } label: {
            LibraryActionButtonLabel(symbol: "shuffle", text: "Shuffle")
          }
          .disabled(playableSongs.isEmpty)
          .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.82))

          NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
            Image(systemName: "chevron.right")
              .font(AM.Font.chevron)
              .foregroundStyle(Color.appAccent)
              .frame(width: 46, height: 46)
              .background(Color.appControlInactiveFill, in: Circle())
          }
          .buttonStyle(PressableButtonStyle(scale: 0.94, dim: 0.78, haptic: .selection))
          .accessibilityLabel("Open \(playlist.name)")
          .accessibilityHint("Shows playlist details.")
        }
      }
      .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }
    .padding(AM.Spacing.xl)
    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous)
        .strokeBorder(Color.appDivider.opacity(0.7), lineWidth: 0.7)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("Library.WideHero")
  }

  private var playableSongs: [Song] {
    let direct = playlist.songListDTOs ?? []
    return direct.isEmpty ? songs : direct
  }
}

enum LibrarySongSort: String, CaseIterable, Identifiable {
  case recentlyAdded
  case title
  case artist
  case duration

  var id: String { rawValue }

  var title: String {
    switch self {
    case .recentlyAdded: return "Recently Added"
    case .title: return "Title"
    case .artist: return "Artist"
    case .duration: return "Duration"
    }
  }

  var symbol: String {
    switch self {
    case .recentlyAdded: return "clock"
    case .title: return "textformat"
    case .artist: return "person"
    case .duration: return "timer"
    }
  }
}

@MainActor
final class LibrarySongsViewModel: ObservableObject {
  @Published var songs: [Song] = []
  @Published var isLoading = false
  @Published var isLoadingMore = false
  @Published var sort: LibrarySongSort = .recentlyAdded
  @Published var searchText = ""
  private var hasLoaded = false
  private var canLoadMore = true
  private var page = 1
  private var requestToken = 0
  private let pageSize = 40

  var displayedSongs: [Song] {
    let sorted: [Song]
    switch sort {
    case .recentlyAdded:
      sorted = songs
    case .title:
      sorted = songs.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    case .artist:
      sorted = songs.sorted {
        $0.displayArtist.localizedStandardCompare($1.displayArtist) == .orderedAscending
      }
    case .duration:
      sorted = songs.sorted { $0.duration < $1.duration }
    }

    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return sorted }
    return sorted.filter { song in
      song.title.localizedCaseInsensitiveContains(query)
        || song.displayArtist.localizedCaseInsensitiveContains(query)
        || song.displayTitle.localizedCaseInsensitiveContains(query)
    }
  }

  func loadIfNeeded() {
    guard !hasLoaded else { return }
    hasLoaded = true
    fetch(page: 1, replace: true)
  }

  func refresh() {
    canLoadMore = true
    fetch(page: 1, replace: true)
  }

  func loadMoreIfNeeded(current: Song) {
    guard canLoadMore, !isLoading, !isLoadingMore else { return }
    guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    let visible = displayedSongs
    guard let index = visible.firstIndex(where: { $0.id == current.id }) else { return }
    guard index >= visible.count - 8 else { return }
    fetch(page: page + 1, replace: false)
  }

  func loadMore() {
    guard canLoadMore, !isLoading, !isLoadingMore else { return }
    guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    fetch(page: page + 1, replace: false)
  }

  private func fetch(page: Int, replace: Bool) {
    guard canLoadMore || replace else { return }
    guard !isLoading && !isLoadingMore else { return }
    guard let url = URL(string: "\(StorageHost.api)/api/songs") else { return }

    requestToken += 1
    let token = requestToken
    if replace {
      isLoading = songs.isEmpty
    } else {
      isLoadingMore = true
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token = UserDefaults.standard.string(forKey: "nk.token") {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    GuestIdentity.applyIfNeeded(to: &request)
    request.httpBody = try? JSONSerialization.data(withJSONObject: [
      "page": page,
      "pageSize": pageSize,
      "search": "",
      "sortBy": "CreatedAt",
      "sortDescending": true,
    ])

    URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      Task { @MainActor [weak self, data, response, error, page, replace, token] in
        self?.applyResponse(
          data,
          response: response,
          error: error,
          page: page,
          replace: replace,
          token: token
        )
      }
    }.resume()
  }

  private func applyResponse(
    _ data: Data?,
    response: URLResponse?,
    error: Error?,
    page: Int,
    replace: Bool,
    token: Int
  ) {
    guard token == requestToken else { return }
    defer {
      isLoading = false
      isLoadingMore = false
    }

    if let error {
      DebugLogger.log("Library songs fetch failed: \(error.localizedDescription)", category: .network)
      return
    }
    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
      DebugLogger.log("Library songs HTTP \(http.statusCode)", category: .network)
      return
    }

    let decoded = Self.decodeSongs(from: data)
    let filtered = decoded.filter {
      !$0.title.localizedCaseInsensitiveContains("Temporary Stream Audio")
    }
    let pageSongs = filtered.isEmpty ? decoded : filtered

    if replace {
      songs = pageSongs
    } else {
      let existing = Set(songs.map(\.id))
      songs += pageSongs.filter { !existing.contains($0.id) }
    }

    canLoadMore = pageSongs.count == pageSize
    if !pageSongs.isEmpty || replace {
      self.page = page
    }
  }

  private static func decodeSongs(from data: Data?) -> [Song] {
    guard let data else { return [] }
    if let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data) {
      return decoded.items
    }
    return SongPayloadDecoder.decodeSongs(from: data) ?? []
  }
}

struct LibrarySongsView: View {
  @StateObject private var viewModel = LibrarySongsViewModel()
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  private var listAnimation: Animation? {
    reduceMotion ? nil : AppMotion.spring(response: 0.34, dampingFraction: 0.84)
  }

  var body: some View {
    let songs = viewModel.displayedSongs
    let isSearching = !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    // Once the library list gets large, omitting thumbnails removes a major source
    // of row work: image decode, cache lookup, and extra view composition per cell.
    let showsRowArtwork = songs.count <= 200
    List {
      if viewModel.isLoading && songs.isEmpty {
        skeletonRows
      } else if songs.isEmpty {
        emptyState(isSearching: isSearching)
          .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
      } else {
        Section {
          actionButtons(songs: songs)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        Section {
          ForEach(songs) { song in
            Button {
              play(song, context: songs)
            } label: {
              SongRow(song: song, size: .regular, showsArtwork: showsRowArtwork)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .songRowAccessibility(song: song) {
                  play(song, context: songs)
                }
            }
            .id(song.id)
            .buttonStyle(PressableButtonStyle(scale: 0.985, dim: 0.78, haptic: .selection))
            .accessibilityHint("Starts playback.")
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Color.clear)
            .onAppear {
              viewModel.loadMoreIfNeeded(current: song)
            }
          }
          if viewModel.isLoadingMore {
            HStack {
              Spacer()
              ProgressView()
                .controlSize(.regular)
              Spacer()
            }
            .frame(height: 44)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
          }
        }
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .smoothScrolling()
    .musicScreenBackground()
    .navigationTitle("Songs")
    .navigationBarTitleDisplayMode(.large)
    .searchable(
      text: $viewModel.searchText,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: "Search Songs"
    )
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        sortMenu
      }
    }
    .refreshable {
      AppHaptic.selection.play()
      viewModel.refresh()
    }
    .task {
      viewModel.loadIfNeeded()
    }
    .animation(listAnimation, value: songs.map(\.id))
    .animation(listAnimation, value: viewModel.sort)
  }

  private func play(_ song: Song, context: [Song]) {
    AppHaptic.selection.play()
    AudioPlayerManager.shared.play(song: song, context: context)
  }

  private var sortMenu: some View {
    Menu {
      ForEach(LibrarySongSort.allCases) { sort in
        Button {
          AppHaptic.selection.play()
          viewModel.sort = sort
        } label: {
          Label(sort.title, systemImage: viewModel.sort == sort ? "checkmark" : sort.symbol)
        }
      }
    } label: {
      Label("Sort Songs", systemImage: "arrow.up.arrow.down")
        .font(.headline)
        .foregroundStyle(Color.appAccent)
        .frame(width: 44, height: 44)
        .labelStyle(.iconOnly)
        .contentShape(Circle())
    }
    .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.72, haptic: .selection))
  }

  @ViewBuilder
  private func actionButtons(songs: [Song]) -> some View {
    HStack(spacing: 12) {
      Button {
        if let first = songs.first {
          AudioPlayerManager.shared.playInOrder(song: first, context: songs)
        }
      } label: {
        LibraryActionButtonLabel(symbol: "play.fill", text: "Play", style: .tertiary)
      }
      .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.75, haptic: .medium))
      Button {
        AudioPlayerManager.shared.playShuffled(from: songs)
      } label: {
        LibraryActionButtonLabel(symbol: "shuffle", text: "Shuffle", style: .tertiary)
      }
      .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.75, haptic: .medium))
    }
  }


  private func emptyState(isSearching: Bool) -> some View {
    MusicEmptyState(
      title: isSearching ? "No Results" : "No Songs",
      message: isSearching
        ? "Try another song or artist."
        : "Songs you load from Twins Karaoke will appear here."
    )
    .frame(maxWidth: .infinity, minHeight: 360)
  }

  private var skeletonRows: some View {
    CenteredLoadingView()
      .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
  }
}

enum LibraryCollectionKind: String, CaseIterable, Identifiable {
  case albums
  case composers
  case compilations

  var id: String { rawValue }

  var title: String {
    switch self {
    case .albums: return "Albums"
    case .composers: return "Composers"
    case .compilations: return "Compilations"
    }
  }

  var symbol: String {
    switch self {
    case .albums: return "square.stack"
    case .composers: return "music.quarternote.3"
    case .compilations: return "rectangle.stack"
    }
  }

  var searchPrompt: String {
    switch self {
    case .albums: return "Search Albums"
    case .composers: return "Search Composers"
    case .compilations: return "Search Compilations"
    }
  }

  var emptyTitle: String {
    switch self {
    case .albums: return "No Albums"
    case .composers: return "No Composers"
    case .compilations: return "No Compilations"
    }
  }

  func collections(from songs: [Song]) -> [LibrarySongCollection] {
    switch self {
    case .albums:
      return groupedCollections(
        from: songs,
        prefix: rawValue,
        fallbackTitle: "Unknown Album"
      ) { song in
        let names = song.libraryOriginalArtistNames
        if let first = names.first { return [first] }
        if let first = song.libraryCoverArtistNames.first { return [first] }
        return ["Unknown Album"]
      }
    case .composers:
      return groupedCollections(
        from: songs,
        prefix: rawValue,
        fallbackTitle: "Unknown Composer"
      ) { song in
        song.libraryCoverArtistNames.isEmpty ? ["Unknown Composer"] : song.libraryCoverArtistNames
      }
    case .compilations:
      return smartCompilationCollections(from: songs)
    }
  }

  private func groupedCollections(
    from songs: [Song],
    prefix: String,
    fallbackTitle: String,
    labels: (Song) -> [String]
  ) -> [LibrarySongCollection] {
    var buckets: [String: (title: String, songs: [Song])] = [:]

    for song in songs {
      let names = labels(song).map(Self.normalizedName).filter { !$0.isEmpty }
      let uniqueNames = names.isEmpty ? [fallbackTitle] : Array(Set(names)).sorted()
      for name in uniqueNames {
        let key = "\(prefix)::\(name.lowercased())"
        if buckets[key] == nil {
          buckets[key] = (title: name, songs: [])
        }
        buckets[key]?.songs.append(song)
      }
    }

    return buckets.map { key, value in
      LibrarySongCollection(
        id: key,
        title: value.title,
        subtitle: SongCountText.songs(value.songs.count),
        songs: value.songs.sorted {
          $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
      )
    }
    .sorted { lhs, rhs in
      lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
  }

  private func smartCompilationCollections(from songs: [Song]) -> [LibrarySongCollection] {
    let definitions: [(id: String, title: String, matches: (Song) -> Bool)] = [
      (
        "neuro-covers", "Neuro Covers",
        { song in
          song.libraryCoverArtistNames.contains { $0 == "Neuro" || $0.hasPrefix("Neuro ") }
        }
      ),
      (
        "community-uploads", "Community Uploads",
        { song in song.userUploaded == true }
      ),
      (
        "collaborations", "Collaborations",
        { song in song.libraryOriginalArtistNames.count > 1 }
      ),
      (
        "cover-artist-collaborations", "Cover Artist Collaborations",
        { song in song.libraryCoverArtistNames.count > 1 }
      ),
      (
        "long-plays", "Long Plays",
        { song in song.duration >= 300 }
      ),
    ]

    return definitions.compactMap { definition in
      let matching = songs.filter(definition.matches)
      guard !matching.isEmpty else { return nil }
      return LibrarySongCollection(
        id: "\(rawValue)::\(definition.id)",
        title: definition.title,
        subtitle: SongCountText.songs(matching.count),
        songs: matching.sorted {
          $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
      )
    }
  }

  nonisolated private static func normalizedName(_ raw: String) -> String {
    raw.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

struct LibrarySongCollection: Identifiable {
  let id: String
  let title: String
  let subtitle: String
  let songs: [Song]

  var artworkURL: URL? {
    songs.first(where: { $0.hasOwnArtwork })?.imageURL ?? songs.first?.imageURL
  }

  var durationText: String? {
    let total = songs.reduce(0) { $0 + max(0, $1.duration) }
    guard total > 0 else { return nil }
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    if hours > 0 {
      return "\(hours) hr \(minutes) min"
    }
    return "\(minutes) min"
  }

}

struct LibraryCollectionListView: View {
  let kind: LibraryCollectionKind
  @StateObject private var viewModel = LibrarySongsViewModel()
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var searchText = ""

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  private var listAnimation: Animation? {
    reduceMotion ? nil : AppMotion.spring(response: 0.34, dampingFraction: 0.84)
  }

  private var collections: [LibrarySongCollection] {
    let all = kind.collections(from: viewModel.songs)
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return all }
    return all.filter { collection in
      collection.title.localizedCaseInsensitiveContains(query)
        || collection.songs.contains { song in
          song.title.localizedCaseInsensitiveContains(query)
            || song.displayArtist.localizedCaseInsensitiveContains(query)
        }
    }
  }

  var body: some View {
    List {
      if viewModel.isLoading && collections.isEmpty {
        collectionSkeletonRows
      } else if collections.isEmpty {
        emptyState
          .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
      } else {
        Section {
          ForEach(collections) { collection in
            NavigationLink {
              LibraryCollectionDetailView(kind: kind, collection: collection)
            } label: {
              LibraryCollectionRow(collection: collection, symbol: kind.symbol)
            }
            .id(collection.id)
            .contextMenu {
              LibraryCollectionActionsMenu(collection: collection)
            } preview: {
              LibraryCollectionPreview(collection: collection, symbol: kind.symbol)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
            .onAppear {
              if collection.id == collections.last?.id {
                viewModel.loadMore()
              }
            }
          }
          if viewModel.isLoadingMore {
            HStack {
              Spacer()
              ProgressView()
                .controlSize(.regular)
              Spacer()
            }
            .frame(height: 44)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
          }
        }
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .smoothScrolling()
    .musicScreenBackground()
    .navigationTitle(kind.title)
    .navigationBarTitleDisplayMode(.large)
    .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: kind.searchPrompt)
    .refreshable {
      AppHaptic.selection.play()
      viewModel.refresh()
    }
    .task {
      viewModel.loadIfNeeded()
    }
    .animation(listAnimation, value: collections.map(\.id))
  }

  private var emptyState: some View {
    MusicEmptyState(
      title: kind.emptyTitle,
      message: searchText.isEmpty
        ? "Songs you load from Twins Karaoke will appear here."
        : "Try another search."
    )
    .frame(maxWidth: .infinity, minHeight: 360)
  }

  private var collectionSkeletonRows: some View {
    CenteredLoadingView()
      .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
  }
}

struct LibraryCollectionRow: View {
  let collection: LibrarySongCollection
  let symbol: String

  var body: some View {
    HStack(spacing: 12) {
      LibraryCollectionArtwork(collection: collection, symbol: symbol, cornerRadius: 8)
        .frame(width: 56, height: 56)
      VStack(alignment: .leading, spacing: 3) {
        Text(collection.title)
          .font(AM.Font.rowTitle)
          .foregroundStyle(.primary)
          .lineLimit(1)
        HStack(spacing: 5) {
          Text(collection.subtitle)
          if let duration = collection.durationText {
            Text("•")
            Text(duration)
          }
        }
        .font(AM.Font.rowSubtitle)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .frame(height: 64)
    .padding(.vertical, 4)
  }
}

struct LibraryCollectionDetailView: View {
  let kind: LibraryCollectionKind
  let collection: LibrarySongCollection
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var scrollOffset: CGFloat = 0

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  private var chromeAnimation: Animation? {
    reduceMotion ? nil : AppMotion.spring(response: 0.34, dampingFraction: 0.84)
  }

  private var contentAnimation: Animation? {
    reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.84)
  }

  var body: some View {
    GeometryReader { geo in
      ScrollView {
        VStack(spacing: 18) {
          heroArtwork(width: geo.size.width)
          VStack(spacing: 4) {
            Text(collection.title)
              .font(.title2.bold())
              .multilineTextAlignment(.center)
            HStack(spacing: 5) {
              Text(collection.subtitle)
              if let duration = collection.durationText {
                Text("•")
                Text(duration)
              }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
          }
          .padding(.horizontal)
          if collection.songs.isEmpty {
            LibraryCollectionEmptyStateView(kind: kind)
              .padding(.top, 12)
              .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
          } else {
            actionButtons
              .padding(.horizontal)
            // Collection detail screens can be arbitrarily long, so large ones use
            // text-first rows to keep scrolling predictable on iPhone.
            let showsRowArtwork = collection.songs.count <= 200
            LazyVStack(spacing: 0) {
              ForEach(collection.songs) { song in
                Button {
                  play(song)
                } label: {
                  SongRow(song: song, size: .regular, showsArtwork: showsRowArtwork)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .songRowAccessibility(song: song) {
                      play(song)
                    }
                }
                .buttonStyle(PressableButtonStyle(scale: 0.985, dim: 0.78, haptic: .selection))
                .accessibilityHint("Starts playback.")
                Divider().padding(.leading, 76)
              }
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
          }
        }
        .padding(.bottom, 16)
        .background(
          GeometryReader { proxy in
            Color.clear.preference(
              key: LibraryCollectionScrollOffsetKey.self,
              value: proxy.frame(in: .named("libraryCollectionScroll")).minY
            )
          }
        )
      }
      .smoothScrolling()
      .coordinateSpace(name: "libraryCollectionScroll")
      .onPreferenceChange(LibraryCollectionScrollOffsetKey.self) { scrollOffset = quantizedScrollOffset($0) }
    }
    .navigationTitle(scrollOffset < -180 ? collection.title : "")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(scrollOffset < -180 ? .visible : .hidden, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          LibraryCollectionActionsMenu(collection: collection)
        } label: {
          Label("More Actions", systemImage: "ellipsis")
            .font(.headline)
            .foregroundStyle(Color.appAccent)
            .frame(width: 44, height: 44)
            .labelStyle(.iconOnly)
            .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.65, haptic: .selection))
      }
    }
    .animation(chromeAnimation, value: scrollOffset < -180)
    .animation(contentAnimation, value: collection.songs.count)
    .scrollIndicators(.hidden)
    .musicScreenBackground()
  }

  private func play(_ song: Song) {
    AppHaptic.selection.play()
    AudioPlayerManager.shared.play(song: song, context: collection.songs)
  }

  private func heroArtwork(width: CGFloat) -> some View {
    let baseSize: CGFloat = 240
    let stretch = reduceMotion ? 0 : max(0, scrollOffset)
    let shrink = reduceMotion ? 0 : max(0, -scrollOffset * 0.4)
    let size = max(140, baseSize + stretch * 0.6 - shrink)
    let yOffset = reduceMotion ? 0 : (scrollOffset > 0 ? -scrollOffset / 2 : 0)
    let artworkOpacity = reduceMotion ? 1 : 1 - min(0.7, max(0, -scrollOffset / 250))
    return LibraryCollectionArtwork(collection: collection, symbol: kind.symbol, cornerRadius: 14)
      .frame(width: size, height: size)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
      .opacity(artworkOpacity)
      .frame(width: width)
      .offset(y: yOffset)
      .padding(.top, 12)
      .contextMenu {
        LibraryCollectionActionsMenu(collection: collection)
      }
  }

  private var actionButtons: some View {
    HStack(spacing: 12) {
      Button {
        if let first = collection.songs.first {
          AudioPlayerManager.shared.playInOrder(song: first, context: collection.songs)
        }
      } label: {
        LibraryActionButtonLabel(symbol: "play.fill", text: "Play", style: .tertiary)
      }
      .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.75, haptic: .medium))
      Button {
        AudioPlayerManager.shared.playShuffled(from: collection.songs)
      } label: {
        LibraryActionButtonLabel(symbol: "shuffle", text: "Shuffle", style: .tertiary)
      }
      .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.75, haptic: .medium))
    }
  }

}

private struct LibraryCollectionEmptyStateView: View {
  let kind: LibraryCollectionKind

  var body: some View {
    MusicEmptyState(
      title: kind.emptyTitle,
      message: "Songs you load from Twins Karaoke will appear here."
    )
    .frame(maxWidth: .infinity)
    .padding(.vertical, 28)
  }
}

private struct LibraryCollectionActionsMenu: View {
  let collection: LibrarySongCollection
  private let pendingDownloads: [Song]
  private let downloadingCount: Int

  private var allDownloaded: Bool {
    !collection.songs.isEmpty && pendingDownloads.isEmpty && downloadingCount == 0
  }

  init(collection: LibrarySongCollection) {
    self.collection = collection
    // Snapshot download state for transparent menu stability. Download progress
    // can publish frequently while a menu is open.
    let downloads = DownloadManager.shared
    self.pendingDownloads = collection.songs.filter { !downloads.isDownloaded($0.id) && !downloads.isDownloading($0.id) }
    self.downloadingCount = collection.songs.filter { downloads.isDownloading($0.id) }.count
  }

  var body: some View {
    if collection.songs.isEmpty {
      Text("No Songs")
    } else {
      Button {
        AppHaptic.selection.play()
        if let first = collection.songs.first {
          AudioPlayerManager.shared.playInOrder(song: first, context: collection.songs)
        }
      } label: {
        Label("Play", systemImage: "play.fill")
      }

      Button {
        AppHaptic.selection.play()
        AudioPlayerManager.shared.playShuffled(from: collection.songs)
      } label: {
        Label("Shuffle", systemImage: "shuffle")
      }

      Divider()

      if downloadingCount > 0 {
        Label("Downloading \(downloadingCount)…", systemImage: "arrow.down.circle")
      } else if allDownloaded {
        Button(role: .destructive) {
          AppHaptic.warning.play()
          for song in collection.songs {
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
          let label =
            pendingDownloads.count < collection.songs.count ? "Download Remaining" : "Download"
          Label(label, systemImage: "arrow.down.circle")
        }
      }
    }
  }
}

private struct LibraryCollectionPreview: View {
  let collection: LibrarySongCollection
  let symbol: String

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      LibraryCollectionArtwork(collection: collection, symbol: symbol, cornerRadius: 12)
        .frame(width: 220, height: 220)
      VStack(alignment: .leading, spacing: 3) {
        Text(collection.title)
          .font(AM.Font.tileTitle)
          .foregroundStyle(.primary)
          .lineLimit(2)
        Text(collection.subtitle)
          .font(AM.Font.tileCaption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(16)
    .frame(width: 252, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}

private struct LibraryCollectionArtwork: View {
  let collection: LibrarySongCollection
  let symbol: String
  let cornerRadius: CGFloat

  private var artworkURLs: [URL] {
    Playlist.songArtworkURLs(collection.songs, limit: 4)
  }

  var body: some View {
    ZStack {
      if artworkURLs.count > 1 {
        PlaylistMosaicArtwork(urls: artworkURLs, cornerRadius: cornerRadius)
      } else if let url = collection.artworkURL {
        RemoteArtworkImage(url: url, cornerRadius: 0, contentMode: .fill, showsLoading: false)
      } else {
        LinearGradient(
          colors: [Color.appPlaceholderTertiary.opacity(0.9), Color.appPlaceholderPrimary],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        Image(systemName: symbol)
          .font(.title.bold())
          .foregroundStyle(.white.opacity(0.85))
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }
}

private struct LibraryCollectionScrollOffsetKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private func quantizedScrollOffset(_ offset: CGFloat) -> CGFloat {
  // Bucket scroll offset changes so the parallax artwork and collapsed title do not
  // trigger a full view update for every sub-pixel movement.
  (offset / 8).rounded() * 8
}

private extension Song {
  var libraryOriginalArtistNames: [String] {
    Self.normalizedLibraryNames(originalArtists)
  }

  var libraryCoverArtistNames: [String] {
    Self.normalizedLibraryNames(coverArtists)
  }

  static func normalizedLibraryNames(_ names: [String]?) -> [String] {
    let cleaned = (names ?? []).map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    .filter { !$0.isEmpty }
    return Array(Set(cleaned)).sorted {
      $0.localizedStandardCompare($1) == .orderedAscending
    }
  }
}

struct LibraryRow: View {
  let icon: String
  let color: Color
  let title: String
  var subtitle: String? = nil

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: icon)
        .font(.title2)
        .foregroundStyle(color)
        .frame(width: 30)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(AM.Font.rowTitle)
          .fontWeight(.semibold)
          .foregroundStyle(.primary)
          .lineLimit(1)
        if let subtitle {
          Text(subtitle)
            .font(AM.Font.tileCaption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
        }
      }

      Spacer()
    }
    .padding(.vertical, 10)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(subtitle ?? "")
  }
}

struct PlaylistListRow: View {
  let playlist: Playlist
  var body: some View {
    HStack(spacing: 12) {
      PlaylistArtwork(playlist: playlist, cornerRadius: 6)
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
      VStack(alignment: .leading, spacing: 2) {
        Text(playlist.name)
          .font(.subheadline)
          .lineLimit(1)
        PlaylistSongCountLabel(playlist: playlist, fallbackText: "Playlist")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
    .padding(.vertical, 2)
  }
}

struct PlaylistsGridScreen: View {
  @ObservedObject var viewModel: PlaylistsViewModel
  @ObservedObject var savedStore: SavedPlaylistsStore = .shared
  @ObservedObject private var userManager = UserPlaylistsManager.shared
  @ObservedObject private var favorites = FavoritesManager.shared
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var showCreateSheet = false
  @State private var searchText = ""
  let cols = AM.Layout.playlistGridColumns

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  private var isLoggedIn: Bool {
    UserDefaults.standard.string(forKey: "nk.token") != nil
  }
  private var combinedPlaylists: [Playlist] {
    let userConverted = userManager.playlists.map { $0.asPlaylist() }
    let all = viewModel.allPlaylists(saved: savedStore.playlists)
    let existingIDs = Set(all.map { $0.id })
    let uniqueUser = userConverted.filter { !existingIDs.contains($0.id) }
    return uniqueUser + all
  }
  private var displayedPlaylists: [Playlist] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return combinedPlaylists }
    return combinedPlaylists.filter { playlist in
      playlist.name.localizedCaseInsensitiveContains(query)
    }
  }
  var body: some View {
    let all = combinedPlaylists
    let displayed = displayedPlaylists
    ScrollView {
      Group {
        if viewModel.isLoading && userManager.isLoading && all.isEmpty {
          PlaylistsSkeletonView()
        } else if displayed.isEmpty {
          MusicEmptyState(
            title: searchText.isEmpty ? "No Playlists" : "No Results",
            message: searchText.isEmpty
              ? "Playlists you add will appear here."
              : "Try another playlist name."
          )
          .frame(maxWidth: .infinity, minHeight: 360)
          .padding(.top, 48)
        } else {
          LazyVGrid(columns: cols, spacing: AM.Spacing.l) {
            ForEach(displayed) { playlist in
              NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                PlaylistGridCell(playlist: playlist)
              }
              .buttonStyle(PressableButtonStyle())
              .contextMenu {
                PlaylistActionsMenuItems(playlist: playlist, songs: playlist.songListDTOs ?? [])
              } preview: {
                PlaylistContextPreview(playlist: playlist)
              }
            }
          }
          .padding(.horizontal, AM.Spacing.screenMargin)
          .padding(.vertical, AM.Spacing.m)
        }
      }
    }
    .smoothScrolling()
    .navigationTitle("Playlists")
    .searchable(
      text: $searchText,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: "Search Playlists"
    )
    .toolbar {
      if isLoggedIn {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            AppHaptic.selection.play()
            showCreateSheet = true
          } label: {
            Image(systemName: "plus")
              .font(.headline)
              .foregroundStyle(Color.appAccent)
              .frame(width: 44, height: 44)
              .contentShape(Circle())
          }
          .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.72))
        }
      }
    }
    .task { userManager.loadIfNeeded() }
    .onChange(of: favorites.favoriteIDs) { _, _ in
      viewModel.fetchFavoriteSongs()
    }
    .animation(
      reduceMotion ? nil : AppMotion.spring(response: 0.34, dampingFraction: 0.84),
      value: displayed.map(\.id))
    .sheet(isPresented: $showCreateSheet) {
      CreatePlaylistSheet()
    }
  }
}

struct PlaylistGridCell: View {
  let playlist: Playlist
  var width: CGFloat? = nil
  var body: some View {
    VStack(alignment: .leading, spacing: AM.Spacing.s) {
      artwork
        .clipShape(RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
        .amShadow(AM.Shadow.card)
      Text(playlist.name)
        .font(AM.Font.tileTitle)
        .foregroundStyle(.primary)
        .lineLimit(1)
      if !playlist.isFavorites {
        PlaylistSongCountLabel(playlist: playlist, fallbackText: "Playlist")
          .font(AM.Font.tileCaption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .frame(width: width, alignment: .leading)
    .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
  }

  @ViewBuilder private var artwork: some View {
    if let width {
      PlaylistArtwork(playlist: playlist, cornerRadius: AM.Radius.card)
        .frame(width: width, height: width)
    } else {
      PlaylistArtwork(playlist: playlist, cornerRadius: AM.Radius.card)
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }
  }
}

struct RecentlyAddedSection: View {
  let songs: [Song]
  var horizontalPadding: CGFloat = AM.Spacing.screenMargin
  var headerHorizontalPadding: CGFloat = AM.Spacing.screenMargin
  private let cols = AM.Layout.songGridColumns
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Recently Added")
        .font(AM.Font.sectionHeader)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, headerHorizontalPadding)
        .padding(.top, 2)
      LazyVGrid(columns: cols, spacing: 22) {
        ForEach(songs) { song in
          MusicGridCard(song: song, context: songs, fillsWidth: true)
        }
      }
      .padding(.horizontal, horizontalPadding)
      .padding(.bottom, 16)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct PlaylistContextPreview: View {
  let playlist: Playlist

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      PlaylistArtwork(playlist: playlist, cornerRadius: 12)
        .frame(width: 220, height: 220)
      VStack(alignment: .leading, spacing: 3) {
        Text(playlist.name)
          .font(AM.Font.tileTitle)
          .foregroundStyle(.primary)
          .lineLimit(2)
        PlaylistSongCountLabel(playlist: playlist, fallbackText: "Playlist")
          .font(AM.Font.tileCaption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(16)
    .frame(width: 252, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}

struct PlaylistsSkeletonView: View {
  var body: some View {
    CenteredLoadingView(label: "Loading playlists")
  }
}
