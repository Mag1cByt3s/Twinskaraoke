import Combine
import Foundation
import SwiftUI

extension Playlist: Hashable {
  public static func == (lhs: Playlist, rhs: Playlist) -> Bool { lhs.id == rhs.id }
  public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

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
    guard let url = URL(string: "\(StorageHost.api)/api/playlist/\(playlist.id)") else { return }

    loadingIDs.insert(playlist.id)
    var request = URLRequest(url: url)
    if let token = UserDefaults.standard.string(forKey: "nk.token"), !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    GuestIdentity.applyIfNeeded(to: &request)

    URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
      let count = Self.resolveCount(from: data)
      DispatchQueue.main.async {
        guard let self else { return }
        self.loadingIDs.remove(playlist.id)
        if let count, count > 0 {
          self.resolvedCounts[playlist.id] = count
        }
      }
    }.resume()
  }

  nonisolated private static func resolveCount(from data: Data?) -> Int? {
    guard let data else { return nil }
    let decoder = JSONDecoder()
    if let playlist = try? decoder.decode(Playlist.self, from: data) {
      return max(playlist.songCount, playlist.songListDTOs?.count ?? 0)
    }
    if let songs = SongPayloadDecoder.decodeSongs(from: data) {
      return songs.count
    }
    return nil
  }
}

struct PlaylistSongCountLabel: View {
  let playlist: Playlist
  var fallbackText: String? = nil

  @ObservedObject private var countStore = PlaylistSongCountStore.shared

  private var labelText: String? {
    if let count = countStore.displayedCount(for: playlist) {
      return "\(count) songs"
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
  @ObservedObject private var savedStore = SavedPlaylistsStore.shared
  @ObservedObject private var addedTracker = RecentlyAddedTracker.shared
  @ObservedObject private var favorites = FavoritesManager.shared
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var path = NavigationPath()
  let cols = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  var body: some View {
    let recents = viewModel.recentlyAddedPlaylists(saved: savedStore.playlists)
    NavigationStack(path: $path) {
      List {
        Section {
          NavigationLink {
            PlaylistsGridScreen(viewModel: viewModel)
          } label: {
            LibraryRow(
              icon: "music.note.list",
              color: .appAccent,
              title: "Playlists",
              subtitle: "Curated sets and saved mixes")
          }
          NavigationLink {
            ArtistsView()
          } label: {
            LibraryRow(
              icon: "music.mic",
              color: .purple,
              title: "Artists",
              subtitle: "Browse original and cover voices")
          }
          NavigationLink {
            LibraryCollectionListView(kind: .albums)
          } label: {
            LibraryRow(
              icon: "square.stack",
              color: .orange,
              title: "Albums",
              subtitle: "Grouped from the karaoke catalog")
          }
          NavigationLink {
            LibrarySongsView()
          } label: {
            LibraryRow(
              icon: "music.note",
              color: .blue,
              title: "Songs",
              subtitle: "All playable tracks")
          }
          NavigationLink {
            VideoGalleryView()
          } label: {
            LibraryRow(
              icon: "play.rectangle",
              color: .red,
              title: "Video Gallery",
              subtitle: "Watch karaoke videos")
          }
          NavigationLink {
            ArtGalleryView()
          } label: {
            LibraryRow(
              icon: "paintpalette",
              color: .pink,
              title: "Art Gallery",
              subtitle: "Browse HD artwork")
          }
          NavigationLink {
            LibraryCollectionListView(kind: .composers)
          } label: {
            LibraryRow(
              icon: "music.quarternote.3",
              color: .teal,
              title: "Composers",
              subtitle: "Songs by creator")
          }
          NavigationLink {
            LibraryCollectionListView(kind: .compilations)
          } label: {
            LibraryRow(
              icon: "rectangle.stack",
              color: .indigo,
              title: "Compilations",
              subtitle: "Smart karaoke collections")
          }
          NavigationLink {
            DownloadedSongsView()
          } label: {
            LibraryRow(
              icon: "arrow.down.circle",
              color: .green,
              title: "Downloaded",
              subtitle: "Saved for offline playback")
          }
          NavigationLink {
            RandomSongsView()
          } label: {
            LibraryRow(
              icon: "shuffle",
              color: .cyan,
              title: "Random Songs",
              subtitle: "Discover something unexpected")
          }
        }
        if !recents.isEmpty {
          Section {
            RecentlyAddedSection(playlists: recents) { playlist in
              path.append(playlist)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
          }
          .listSectionSpacing(8)
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .musicScreenBackground()
      .navigationTitle("Library")
      .navigationBarTitleDisplayMode(.large)
      .refreshable {
        AppHaptic.selection.play()
        favorites.loadIfNeeded()
        viewModel.fetchPlaylists()
        viewModel.fetchFavoriteSongs()
      }
      .navigationDestination(for: Playlist.self) { playlist in
        PlaylistDetailView(playlist: playlist)
      }
      .onAppear {
        favorites.loadIfNeeded()
        viewModel.fetchPlaylists()
        viewModel.fetchFavoriteSongs()
      }
      .onChange(of: favorites.favoriteIDs) { _, _ in
        viewModel.fetchFavoriteSongs()
      }
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: recents.map(\.id))
    }
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
  @EnvironmentObject private var audioManager: AudioPlayerManager
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  private var listAnimation: Animation? {
    reduceMotion ? nil : .easeInOut(duration: 0.22)
  }

  var body: some View {
    let songs = viewModel.displayedSongs
    let isSearching = !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            SongRow(song: song, size: .regular)
              .padding(.vertical, 6)
              .contentShape(Rectangle())
              .onTapGesture {
                play(song, context: songs)
              }
              .songRowAccessibility(song: song) {
                play(song, context: songs)
              }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Color.clear)
            .onAppear {
              viewModel.loadMoreIfNeeded(current: song)
            }
          }
          if viewModel.isLoadingMore {
            HStack {
              Spacer()
              LoadingIndicator(size: 28)
              Spacer()
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
          }
        }
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
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
    audioManager.play(song: song, context: context)
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
      Image(systemName: "arrow.up.arrow.down")
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(.appAccent)
        .frame(width: 34, height: 34)
        .contentShape(Rectangle())
    }
    .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.72, haptic: .selection))
  }

  @ViewBuilder
  private func actionButtons(songs: [Song]) -> some View {
    HStack(spacing: 12) {
      Button {
        if let first = songs.first {
          audioManager.playInOrder(song: first, context: songs)
        }
      } label: {
        actionLabel(symbol: "play.fill", text: "Play")
      }
      .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.75, haptic: .medium))
      Button {
        audioManager.playShuffled(from: songs)
      } label: {
        actionLabel(symbol: "shuffle", text: "Shuffle")
      }
      .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.75, haptic: .medium))
    }
  }

  private func actionLabel(symbol: String, text: String) -> some View {
    HStack(spacing: 6) {
      Image(systemName: symbol)
      Text(text).fontWeight(.semibold)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
    .foregroundColor(.appAccent)
    .background(Color(.tertiarySystemFill))
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
  }

  private func emptyState(isSearching: Bool) -> some View {
    MusicEmptyState(
      systemImage: "music.note",
      title: isSearching ? "No Results" : "No Songs",
      message: isSearching
        ? "Try another song or artist."
        : "Songs you load from Twins Karaoke will appear here."
    )
    .frame(maxWidth: .infinity, minHeight: 360)
  }

  private var skeletonRows: some View {
    ForEach(0..<10, id: \.self) { _ in
      SongRowSkeleton(size: .regular)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
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
        subtitle: LibrarySongCollection.songCountText(value.songs.count),
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
        subtitle: LibrarySongCollection.songCountText(matching.count),
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

  static func songCountText(_ count: Int) -> String {
    count == 1 ? "1 song" : "\(count) songs"
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
    reduceMotion ? nil : .easeInOut(duration: 0.22)
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
              LoadingIndicator(size: 28)
              Spacer()
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
          }
        }
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
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
      systemImage: kind.symbol,
      title: kind.emptyTitle,
      message: searchText.isEmpty
        ? "Songs you load from Twins Karaoke will appear here."
        : "Try another search."
    )
    .frame(maxWidth: .infinity, minHeight: 360)
  }

  private var collectionSkeletonRows: some View {
    ForEach(0..<10, id: \.self) { _ in
      HStack(spacing: 12) {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color(.tertiarySystemFill))
          .frame(width: 56, height: 56)
        VStack(alignment: .leading, spacing: 8) {
          RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color(.tertiarySystemFill))
            .frame(width: 160, height: 14)
          RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color(.tertiarySystemFill))
            .frame(width: 88, height: 11)
        }
        Spacer()
      }
      .padding(.vertical, 6)
      .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
      .redacted(reason: .placeholder)
    }
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
          .font(.system(size: 16, weight: .regular))
          .foregroundColor(.primary)
          .lineLimit(1)
        HStack(spacing: 5) {
          Text(collection.subtitle)
          if let duration = collection.durationText {
            Text("•")
            Text(duration)
          }
        }
        .font(.system(size: 13))
        .foregroundColor(.secondary)
        .lineLimit(1)
      }
      Spacer()
    }
    .padding(.vertical, 4)
  }
}

struct LibraryCollectionDetailView: View {
  let kind: LibraryCollectionKind
  let collection: LibrarySongCollection
  @EnvironmentObject private var audioManager: AudioPlayerManager
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
    reduceMotion ? nil : .easeInOut(duration: 0.2)
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
            .foregroundColor(.secondary)
          }
          .padding(.horizontal)
          if collection.songs.isEmpty {
            LibraryCollectionEmptyStateView(kind: kind)
              .padding(.top, 12)
              .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
          } else {
            actionButtons
              .padding(.horizontal)
            LazyVStack(spacing: 0) {
              ForEach(collection.songs) { song in
                SongRow(song: song, size: .regular)
                  .padding(.horizontal)
                  .padding(.vertical, 8)
                  .contentShape(Rectangle())
                  .onTapGesture {
                    play(song)
                  }
                  .songRowAccessibility(song: song) {
                    play(song)
                  }
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
      .coordinateSpace(name: "libraryCollectionScroll")
      .onPreferenceChange(LibraryCollectionScrollOffsetKey.self) { scrollOffset = $0 }
    }
    .navigationTitle(scrollOffset < -180 ? collection.title : "")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(scrollOffset < -180 ? .visible : .hidden, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          LibraryCollectionActionsMenu(collection: collection)
        } label: {
          Image(systemName: "ellipsis")
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.appAccent)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
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
    audioManager.play(song: song, context: collection.songs)
  }

  private func heroArtwork(width: CGFloat) -> some View {
    let baseSize: CGFloat = 240
    let stretch = reduceMotion ? 0 : max(0, scrollOffset)
    let shrink = reduceMotion ? 0 : max(0, -scrollOffset * 0.4)
    let size = max(140, baseSize + stretch * 0.6 - shrink)
    let blur = reduceMotion ? 0 : min(8, max(0, -scrollOffset / 30))
    let yOffset = reduceMotion ? 0 : (scrollOffset > 0 ? -scrollOffset / 2 : 0)
    let artworkOpacity = reduceMotion ? 1 : 1 - min(0.7, max(0, -scrollOffset / 250))
    return LibraryCollectionArtwork(collection: collection, symbol: kind.symbol, cornerRadius: 14)
      .frame(width: size, height: size)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
      .blur(radius: blur)
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
          audioManager.playInOrder(song: first, context: collection.songs)
        }
      } label: {
        actionLabel(symbol: "play.fill", text: "Play")
      }
      .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.75, haptic: .medium))
      Button {
        audioManager.playShuffled(from: collection.songs)
      } label: {
        actionLabel(symbol: "shuffle", text: "Shuffle")
      }
      .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.75, haptic: .medium))
    }
  }

  private func actionLabel(symbol: String, text: String) -> some View {
    HStack(spacing: 6) {
      Image(systemName: symbol)
      Text(text).fontWeight(.semibold)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
    .foregroundColor(.appAccent)
    .background(Color(.tertiarySystemFill))
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}

private struct LibraryCollectionEmptyStateView: View {
  let kind: LibraryCollectionKind

  var body: some View {
    MusicEmptyState(
      systemImage: kind.symbol,
      title: kind.emptyTitle,
      message: "Songs you load from Twins Karaoke will appear here."
    )
    .frame(maxWidth: .infinity)
    .padding(.vertical, 28)
  }
}

private struct LibraryCollectionActionsMenu: View {
  let collection: LibrarySongCollection
  @EnvironmentObject private var audioManager: AudioPlayerManager
  @StateObject private var downloads = DownloadManager.shared

  private var pendingDownloads: [Song] {
    collection.songs.filter { !downloads.isDownloaded($0.id) && !downloads.isDownloading($0.id) }
  }

  private var downloadingCount: Int {
    collection.songs.filter { downloads.isDownloading($0.id) }.count
  }

  private var allDownloaded: Bool {
    !collection.songs.isEmpty && pendingDownloads.isEmpty && downloadingCount == 0
  }

  var body: some View {
    if collection.songs.isEmpty {
      Label("No Songs", systemImage: "music.note.list")
    } else {
      Button {
        AppHaptic.selection.play()
        if let first = collection.songs.first {
          audioManager.playInOrder(song: first, context: collection.songs)
        }
      } label: {
        Label("Play", systemImage: "play.fill")
      }

      Button {
        AppHaptic.selection.play()
        audioManager.playShuffled(from: collection.songs)
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
            downloads.remove(songID: song.id)
          }
        } label: {
          Label("Remove Downloads", systemImage: "trash")
        }
      } else {
        Button {
          AppHaptic.success.play()
          for song in pendingDownloads {
            downloads.download(song: song)
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
          .font(.system(size: 17, weight: .semibold))
          .foregroundColor(.primary)
          .lineLimit(2)
        Text(collection.subtitle)
          .font(.system(size: 14))
          .foregroundColor(.secondary)
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
    Array(collection.songs.prefix(4).compactMap(\.imageURL))
  }

  var body: some View {
    ZStack {
      if artworkURLs.count >= 4 {
        LazyVGrid(
          columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)],
          spacing: 0
        ) {
          ForEach(Array(artworkURLs.enumerated()), id: \.offset) { _, url in
            LoadingImage(url: url, cornerRadius: 0, contentMode: .fill, showsLoading: false)
              .aspectRatio(1, contentMode: .fill)
          }
        }
      } else if let url = collection.artworkURL {
        LoadingImage(url: url, cornerRadius: 0, contentMode: .fill, showsLoading: false)
      } else {
        LinearGradient(
          colors: [Color.appPlaceholderTertiary.opacity(0.9), Color.appPlaceholderPrimary],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        Image(systemName: symbol)
          .font(.system(size: 30, weight: .semibold))
          .foregroundColor(.white.opacity(0.85))
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
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.system(size: 17, weight: .semibold))
        .foregroundColor(color)
        .frame(width: 38, height: 38)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(color.opacity(0.14))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(color.opacity(0.08), lineWidth: 1)
        )
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 17, weight: .semibold))
          .foregroundColor(.primary)
          .lineLimit(1)
        if let subtitle {
          Text(subtitle)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
        }
      }

      Spacer()
    }
    .padding(.vertical, 6)
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
          .font(.system(size: 15, weight: .medium))
          .lineLimit(1)
        PlaylistSongCountLabel(playlist: playlist, fallbackText: "Playlist")
          .font(.system(size: 12))
          .foregroundColor(.secondary)
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
  let cols = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

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
          PlaylistsSkeletonView(cols: cols)
        } else if displayed.isEmpty {
          MusicEmptyState(
            systemImage: "music.note.list",
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
              .font(.system(size: 16, weight: .semibold))
              .foregroundColor(.appAccent)
          }
          .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.72))
        }
      }
    }
    .task { userManager.loadIfNeeded() }
    .onChange(of: favorites.favoriteIDs) { _, _ in
      viewModel.fetchFavoriteSongs()
    }
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: displayed.map(\.id))
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
        .foregroundColor(.primary)
        .lineLimit(1)
      PlaylistSongCountLabel(playlist: playlist, fallbackText: "Playlist")
        .font(AM.Font.tileCaption)
        .foregroundColor(.secondary)
        .lineLimit(1)
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
  let playlists: [Playlist]
  let onSelect: (Playlist) -> Void
  private let cols = [
    GridItem(.flexible(), spacing: 14),
    GridItem(.flexible(), spacing: 14),
  ]
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      AMSectionHeader("Recently Added")
      LazyVGrid(columns: cols, spacing: 22) {
        ForEach(playlists) { playlist in
          Button {
            AppHaptic.selection.play()
            onSelect(playlist)
          } label: {
            PlaylistGridCell(playlist: playlist)
          }
          .buttonStyle(.plain)
          .contextMenu {
            PlaylistActionsMenuItems(playlist: playlist, songs: playlist.songListDTOs ?? [])
          } preview: {
            PlaylistContextPreview(playlist: playlist)
          }
        }
      }
      .padding(.horizontal, 8)
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
          .font(.system(size: 17, weight: .semibold))
          .foregroundColor(.primary)
          .lineLimit(2)
        PlaylistSongCountLabel(playlist: playlist, fallbackText: "Playlist")
          .font(.system(size: 14))
          .foregroundColor(.secondary)
          .lineLimit(1)
      }
    }
    .padding(16)
    .frame(width: 252, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}

struct PlaylistsSkeletonView: View {
  let cols: [GridItem]
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
    LazyVGrid(columns: cols, spacing: 16) {
      ForEach(0..<8, id: \.self) { index in
        VStack(alignment: .leading, spacing: 6) {
          RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous)
            .fill(Color.appPlaceholderPrimary)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
          RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color.appPlaceholderSecondary)
            .frame(width: index % 3 == 0 ? 108 : 138, height: 13)
          RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color.appPlaceholderPrimary)
            .frame(width: 72, height: 11)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .opacity(!reduceMotion && pulse ? 0.58 : 1.0)
    .redacted(reason: .placeholder)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Loading playlists")
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
        pulse = false
      } else {
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
          pulse = true
        }
      }
    }
  }
}
