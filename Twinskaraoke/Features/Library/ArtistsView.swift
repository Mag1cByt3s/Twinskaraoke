import Combine
import Foundation
import SwiftUI

nonisolated struct Artist: Codable, Identifiable, Equatable, Sendable {
  let id: String
  let name: String
  let summary: String?
  let imagePath: String?
  let songCount: Int?
  let songListDTOs: [Song]?
  var imageURL: URL? {
    guard let path = imagePath, !path.isEmpty else { return nil }
    let cleanPath = path.hasPrefix("/") ? path : "/" + path
    return URL(string: StorageHost.base + cleanPath)
  }
  static func == (lhs: Artist, rhs: Artist) -> Bool { lhs.id == rhs.id }
}
@MainActor
final class ArtistsViewModel: ObservableObject {
  @Published var artists: [Artist] = []
  @Published var isLoading = false
  @Published var canLoadMore = true
  private var page = 0
  private let pageSize = 25
  func fetchInitial() {
    guard artists.isEmpty else { return }
    page = 0
    canLoadMore = true
    load(reset: true)
  }

  func refresh() {
    page = 0
    canLoadMore = true
    load(reset: true)
  }
  func loadMoreIfNeeded(current: Artist) {
    guard let idx = artists.firstIndex(of: current) else { return }
    if idx >= artists.count - 5 && !isLoading && canLoadMore {
      load(reset: false)
    }
  }
  private func load(reset: Bool) {
    let startIndex = page * pageSize
    let urlString =
      "\(StorageHost.api)/api/artists?startIndex=\(startIndex)&pageSize=\(pageSize)&search=&sortBy=Name&sortDescending=False"
    guard let url = URL(string: urlString) else { return }
    isLoading = true
    var request = URLRequest(url: url)
    GuestIdentity.applyIfNeeded(to: &request)
    URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
      Task { @MainActor [weak self, data, reset] in
        self?.applyArtistsResponse(data, reset: reset)
      }
    }.resume()
  }

  private func applyArtistsResponse(_ data: Data?, reset: Bool) {
    defer { isLoading = false }

    guard let data, let decoded = try? JSONDecoder().decode([Artist].self, from: data) else {
      return
    }

    if reset {
      artists = decoded
    } else {
      let existing = Set(artists.map { $0.id })
      artists += decoded.filter { !existing.contains($0.id) }
    }
    page += 1
    canLoadMore = decoded.count == pageSize
  }
}
@MainActor
final class ArtistDetailViewModel: ObservableObject {
  @Published var artist: Artist?
  @Published var isLoading = false
  @Published private(set) var hasLoadedDetail = false
  @Published var errorMessage: String?
  private var loadedID: String?

  func load(id: String, fallback: Artist?, force: Bool = false) {
    if !force, loadedID == id, hasLoadedDetail { return }
    if artist == nil || loadedID != id { artist = fallback }
    loadedID = id
    hasLoadedDetail = false
    errorMessage = nil
    guard let url = URL(string: "\(StorageHost.api)/api/artist/\(id)") else { return }
    isLoading = true
    var request = URLRequest(url: url)
    GuestIdentity.applyIfNeeded(to: &request)
    URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
      Task { @MainActor [weak self, data] in
        self?.applyArtistDetailResponse(data)
      }
    }.resume()
  }

  private func applyArtistDetailResponse(_ data: Data?) {
    defer { isLoading = false }

    guard let data else {
      errorMessage = "Check your connection and try again."
      return
    }

    guard let decoded = try? JSONDecoder().decode(Artist.self, from: data) else {
      errorMessage = "The artist could not be loaded right now."
      return
    }

    artist = decoded
    hasLoadedDetail = true
    errorMessage = nil
  }
}

struct ArtistsView: View {
  @StateObject private var viewModel = ArtistsViewModel()
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var searchText = ""

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  private var displayedArtists: [Artist] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return viewModel.artists }
    return viewModel.artists.filter { artist in
      artist.name.localizedCaseInsensitiveContains(query)
        || artist.summary?.localizedCaseInsensitiveContains(query) == true
    }
  }

  var body: some View {
    Group {
      if viewModel.artists.isEmpty && viewModel.isLoading {
        ArtistsSkeletonView()
          .transition(.opacity)
      } else if displayedArtists.isEmpty {
        MusicEmptyState(
          systemImage: "music.mic",
          title: searchText.isEmpty ? "No Artists" : "No Results",
          message: searchText.isEmpty
            ? "Artists you load from Twinskaraoke will appear here."
            : "Try another artist."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List {
          ForEach(displayedArtists) { artist in
            NavigationLink(destination: ArtistDetailView(artist: artist)) {
              ArtistRow(artist: artist)
            }
            .onAppear { viewModel.loadMoreIfNeeded(current: artist) }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
          }
          if viewModel.isLoading {
            HStack {
              Spacer()
              LoadingIndicator(size: 28)
                .padding(.vertical, 8)
              Spacer()
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
          }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
      }
    }
    .musicScreenBackground()
    .navigationTitle("Artists")
    .navigationBarTitleDisplayMode(.large)
    .searchable(
      text: $searchText,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: "Search Artists"
    )
    .refreshable {
      AppHaptic.selection.play()
      viewModel.refresh()
    }
    .onAppear { viewModel.fetchInitial() }
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: displayedArtists.map(\.id))
  }
}

private struct ArtistsSkeletonView: View {
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
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(0..<12, id: \.self) { index in
          HStack(spacing: 12) {
            Circle()
              .fill(Color.appPlaceholderPrimary)
              .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 7) {
              RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.appPlaceholderSecondary)
                .frame(width: index == 2 || index == 8 ? 118 : 168, height: 13)
              RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.appPlaceholderPrimary)
                .frame(width: 74, height: 11)
            }

            Spacer(minLength: 12)

            Circle()
              .fill(Color.appPlaceholderPrimary)
              .frame(width: 24, height: 24)
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 8)

          if index < 11 {
            Divider().padding(.leading, 80)
          }
        }
      }
      .padding(.top, 8)
    }
    .opacity(!reduceMotion && pulse ? 0.58 : 1.0)
    .redacted(reason: .placeholder)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Loading artists")
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
}

private struct ArtistRow: View {
  let artist: Artist
  var body: some View {
    HStack(spacing: 12) {
      ArtistAvatar(url: artist.imageURL)
        .frame(width: 52, height: 52)
        .clipShape(Circle())
      VStack(alignment: .leading, spacing: 2) {
        Text(artist.name)
          .font(AM.Font.rowTitle)
          .lineLimit(1)
        if let count = artist.songCount, count > 0 {
          Text("\(count) songs")
            .font(AM.Font.rowSubtitle)
            .foregroundColor(.secondary)
        }
      }
      Spacer()
    }
    .padding(.vertical, 4)
  }
}

private struct ArtistAvatar: View {
  let url: URL?
  var body: some View {
    Group {
      if let url {
        LoadingImage(url: url, cornerRadius: 0, showsLoading: false)
      } else {
        ZStack {
          Color(.systemGray5)
          Image(systemName: "music.mic")
            .font(.system(size: 22, weight: .medium))
            .foregroundColor(.secondary)
        }
      }
    }
  }
}

struct ArtistDetailView: View {
  let artist: Artist
  @StateObject private var loader = ArtistDetailViewModel()
  @EnvironmentObject var audioManager: AudioPlayerManager
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var scrollOffset: CGFloat = 0
  private var current: Artist { loader.artist ?? artist }
  private var songs: [Song] { current.songListDTOs ?? [] }
  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }
  var body: some View {
    GeometryReader { geo in
      ScrollView {
        VStack(spacing: 18) {
          parallaxHero(width: geo.size.width)
          VStack(spacing: 4) {
            Text(current.name)
              .font(.title2.bold())
              .multilineTextAlignment(.center)
            if let count = current.songCount, count > 0 {
              Text("\(count) songs")
                .font(.subheadline)
                .foregroundColor(.secondary)
            } else if !songs.isEmpty {
              Text("\(songs.count) songs")
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
          }
          .padding(.horizontal)
          if !songs.isEmpty {
            actionButtons
            LazyVStack(spacing: 0) {
              ForEach(songs) { song in
                ArtistSongRow(song: song) {
                  play(song)
                }
                  .padding(.horizontal)
                  .padding(.vertical, 8)
                Divider().padding(.leading, 76)
              }
            }
          } else if loader.isLoading {
            ArtistSongsSkeleton()
          } else if let message = loader.errorMessage {
            ArtistDetailStateView(
              systemImage: "wifi.exclamationmark",
              title: "Couldn't Load Songs",
              message: message,
              buttonTitle: "Try Again"
            ) {
              loader.load(id: artist.id, fallback: artist, force: true)
            }
          } else if loader.hasLoadedDetail {
            ArtistDetailStateView(
              systemImage: "music.note.list",
              title: "No Songs",
              message: "Songs by \(current.name) will appear here when they are available.",
              buttonTitle: "Refresh"
            ) {
              loader.load(id: artist.id, fallback: artist, force: true)
            }
          }
          aboutSection
        }
        .padding(.bottom, 16)
        .background(
          GeometryReader { proxy in
            Color.clear.preference(
              key: ArtistScrollOffsetKey.self,
              value: proxy.frame(in: .named("artistScroll")).minY
            )
          }
        )
      }
      .scrollIndicators(.hidden)
      .coordinateSpace(name: "artistScroll")
      .onPreferenceChange(ArtistScrollOffsetKey.self) { scrollOffset = $0 }
    }
    .musicScreenBackground()
    .navigationTitle(scrollOffset < -180 ? current.name : "")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(scrollOffset < -180 ? .visible : .hidden, for: .navigationBar)
    .toolbar {
      if !songs.isEmpty {
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            ArtistActionsMenu(songs: songs)
          } label: {
            Image(systemName: "ellipsis")
              .font(.system(size: 16, weight: .semibold))
              .foregroundColor(.appAccent)
              .frame(width: 32, height: 32)
              .contentShape(Rectangle())
          }
          .buttonStyle(PressableButtonStyle(scale: 0.92, dim: 0.78, haptic: .selection))
        }
      }
    }
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: scrollOffset < -180)
    .animation(
      reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82),
      value: songs.map(\.id))
    .onAppear { loader.load(id: artist.id, fallback: artist) }
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
    let blur = reduceMotion ? 0 : min(8, max(0, -scrollOffset / 30))
    let yOffset = reduceMotion ? 0 : (scrollOffset > 0 ? -scrollOffset / 2 : 0)
    let artworkOpacity = reduceMotion ? 1 : 1 - min(0.7, max(0, -scrollOffset / 250))
    ArtistAvatar(url: current.imageURL)
      .frame(width: size, height: size)
      .clipShape(Circle())
      .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
      .blur(radius: blur)
      .opacity(artworkOpacity)
      .frame(width: width)
      .offset(y: yOffset)
      .padding(.top, 12)
      .contextMenu {
        if !songs.isEmpty {
          ArtistActionsMenu(songs: songs)
        }
      }
  }
  private var actionButtons: some View {
    HStack(spacing: 12) {
      Button {
        if let first = songs.first {
          audioManager.playInOrder(song: first, context: songs)
        }
      } label: {
        actionLabel(symbol: "play.fill", text: "Play", isPrimary: true)
      }
      .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.75, haptic: .medium))
      Button {
        audioManager.playShuffled(from: songs)
      } label: {
        actionLabel(symbol: "shuffle", text: "Shuffle", isPrimary: false)
      }
      .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.75, haptic: .medium))
    }
    .padding(.horizontal)
  }

  @ViewBuilder
  private var aboutSection: some View {
    if let summary = current.summary, !summary.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text("About")
          .font(.system(size: 18, weight: .bold))
        Text(summary)
          .font(.system(size: 14))
          .foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal)
      .padding(.top, 12)
    }
  }

  private func actionLabel(symbol: String, text: String, isPrimary: Bool) -> some View {
    HStack(spacing: 6) {
      Image(systemName: symbol)
        .font(.system(size: 15, weight: .semibold))
      Text(text).fontWeight(.semibold)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
    .foregroundColor(isPrimary ? .appControlActiveForeground : .appAccent)
    .background(isPrimary ? Color.appControlActiveFill : Color.appControlInactiveFill)
    .clipShape(RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
  }
}

private struct ArtistSongRow: View {
  let song: Song
  let onPlay: () -> Void

  var body: some View {
    SongRow(song: song, size: .regular)
      .contentShape(Rectangle())
      .onTapGesture {
        onPlay()
      }
      .songRowAccessibility(song: song) {
        onPlay()
      }
  }
}

private struct ArtistSongsSkeleton: View {
  var body: some View {
    LazyVStack(spacing: 0) {
      ForEach(0..<7, id: \.self) { _ in
        HStack(spacing: 12) {
          RoundedRectangle(cornerRadius: AM.Radius.thumb, style: .continuous)
            .fill(Color.appPlaceholderPrimary)
            .frame(width: 52, height: 52)
          VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
              .fill(Color.appPlaceholderSecondary)
              .frame(width: 190, height: 12)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
              .fill(Color.appPlaceholderPrimary)
              .frame(width: 116, height: 10)
          }
          Spacer()
          LoadingIndicator(size: 16)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        Divider().padding(.leading, 76)
      }
    }
    .redacted(reason: .placeholder)
    .accessibilityLabel("Loading artist songs")
  }
}

private struct ArtistDetailStateView: View {
  let systemImage: String
  let title: String
  let message: String
  let buttonTitle: String
  let onRefresh: () -> Void
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var isPulsing = false
  @State private var hasAppeared = false

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  var body: some View {
    VStack(spacing: AM.Spacing.xl) {
      ZStack {
        Circle()
          .fill(Color.appAccent.opacity(isPulsing ? 0.16 : 0.08))
          .frame(width: 116, height: 116)
          .scaleEffect(isPulsing ? 1.08 : 0.96)
        Circle()
          .fill(Color.appAccent.opacity(0.12))
          .frame(width: 84, height: 84)
        Image(systemName: systemImage)
          .font(.system(size: 34, weight: .semibold))
          .foregroundColor(.appAccent)
          .symbolRenderingMode(.hierarchical)
      }
      .scaleEffect(hasAppeared ? 1 : 0.94)
      .opacity(hasAppeared ? 1 : 0)

      VStack(spacing: AM.Spacing.s) {
        Text(title)
          .font(.system(size: 23, weight: .bold))
          .foregroundColor(.primary)
          .multilineTextAlignment(.center)
        Text(message)
          .font(.system(size: 15))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .lineLimit(3)
      }
      .frame(maxWidth: 340)

      Button {
        AppHaptic.selection.play()
        onRefresh()
      } label: {
        Label(buttonTitle, systemImage: "arrow.clockwise")
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.white)
          .padding(.horizontal, AM.Spacing.xl)
          .padding(.vertical, 11)
          .background(Color.appAccent, in: Capsule())
          .shadow(color: Color.appAccent.opacity(0.28), radius: 10, y: 4)
      }
      .buttonStyle(PressableButtonStyle(scale: 0.94, dim: 0.78, haptic: .selection))

      VStack(spacing: AM.Spacing.s) {
        ArtistDetailHintRow(
          systemImage: "music.mic",
          title: "Artist catalog",
          message: "Songs appear here as the backend returns this artist's tracks."
        )
        ArtistDetailHintRow(
          systemImage: "ellipsis.circle",
          title: "Use song menus",
          message: "Queue, favorite, download, or add songs to playlists."
        )
      }
      .frame(maxWidth: 360)
      .opacity(hasAppeared ? 1 : 0)
      .offset(y: hasAppeared ? 0 : 10)
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, AM.Spacing.screenMargin)
    .padding(.vertical, 24)
    .onAppear {
      guard !reduceMotion else {
        hasAppeared = true
        isPulsing = false
        return
      }
      withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
        hasAppeared = true
      }
      withAnimation(.easeInOut(duration: 1.45).repeatForever(autoreverses: true)) {
        isPulsing = true
      }
    }
    .onChange(of: reduceMotion) { _, reduceMotion in
      if reduceMotion {
        withAnimation(nil) {
          isPulsing = false
          hasAppeared = true
        }
      } else {
        withAnimation(.easeInOut(duration: 1.45).repeatForever(autoreverses: true)) {
          isPulsing = true
        }
      }
    }
    .accessibilityElement(children: .contain)
  }
}

private struct ArtistDetailHintRow: View {
  let systemImage: String
  let title: String
  let message: String

  var body: some View {
    HStack(spacing: AM.Spacing.m) {
      Image(systemName: systemImage)
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.appAccent)
        .frame(width: 30, height: 30)
        .background(Color.appAccent.opacity(0.12), in: Circle())
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(.primary)
        Text(message)
          .font(.system(size: 13))
          .foregroundColor(.secondary)
          .lineLimit(2)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, AM.Spacing.m)
    .padding(.vertical, AM.Spacing.s)
    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
  }
}

private struct ArtistActionsMenu: View {
  let songs: [Song]
  @EnvironmentObject private var audioManager: AudioPlayerManager
  @StateObject private var downloads = DownloadManager.shared

  private var pendingDownloads: [Song] {
    songs.filter { !downloads.isDownloaded($0.id) && !downloads.isDownloading($0.id) }
  }

  private var downloadingCount: Int {
    songs.filter { downloads.isDownloading($0.id) }.count
  }

  private var allDownloaded: Bool {
    !songs.isEmpty && pendingDownloads.isEmpty && downloadingCount == 0
  }

  private var downloadTitle: String {
    let downloadedCount = songs.count - pendingDownloads.count - downloadingCount
    return downloadedCount > 0 ? "Download Remaining" : "Download"
  }

  var body: some View {
    if songs.isEmpty {
      Label("No Songs", systemImage: "music.note.list")
    } else {
      Button {
        AppHaptic.selection.play()
        if let first = songs.first {
          audioManager.playInOrder(song: first, context: songs)
        }
      } label: {
        Label("Play", systemImage: "play.fill")
      }

      Button {
        AppHaptic.selection.play()
        audioManager.playShuffled(from: songs)
      } label: {
        Label("Shuffle", systemImage: "shuffle")
      }

      Divider()

      if downloadingCount > 0 {
        Label("Downloading \(downloadingCount)...", systemImage: "arrow.down.circle")
      } else if allDownloaded {
        Button(role: .destructive) {
          AppHaptic.warning.play()
          for song in songs {
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
          Label(downloadTitle, systemImage: "arrow.down.circle")
        }
      }
    }
  }
}

private struct ArtistScrollOffsetKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
