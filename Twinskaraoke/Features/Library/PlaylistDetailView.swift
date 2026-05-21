import Combine
import SwiftUI

struct PlaylistDetailView: View {
  let playlist: Playlist
  @EnvironmentObject var audioManager: AudioPlayerManager
  @StateObject private var loader = PlaylistDetailViewModel()
  @ObservedObject private var favorites = FavoritesManager.shared
  @State private var scrollOffset: CGFloat = 0
  @State private var showSongArtwork = true
  var body: some View {
    let songs: [Song] = loader.songs ?? playlist.songListDTOs ?? []
    GeometryReader { geo in
      ScrollView {
        VStack(spacing: 18) {
          parallaxHero(width: geo.size.width)
          VStack(spacing: 4) {
            Text(playlist.name)
              .font(.title2.bold())
              .multilineTextAlignment(.center)
            Text("\(playlist.songCount) songs")
              .font(.subheadline)
              .foregroundColor(.secondary)
          }
          .padding(.horizontal)
          if !songs.isEmpty {
            actionButtons(songs: songs)
            LazyVStack(spacing: 0) {
              ForEach(songs) { song in
                Button {
                  audioManager.play(song: song, context: songs)
                } label: {
                  PlaylistRow(song: song, showsArtwork: showSongArtwork)
                }
                .buttonStyle(PressableButtonStyle())
                Divider().padding(.leading, showSongArtwork ? 76 : 28)
              }
            }
          } else if loader.isLoading {
            LoadingIndicator(size: 48)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 40)
          }
        }
        .padding(.bottom, 16)
        .background(
          GeometryReader { proxy in
            Color.clear.preference(
              key: ScrollOffsetKey.self,
              value: proxy.frame(in: .named("playlistScroll")).minY
            )
          }
        )
      }
      .coordinateSpace(name: "playlistScroll")
      .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = $0 }
    }
    .navigationTitle(scrollOffset < -180 ? playlist.name : "")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(scrollOffset < -180 ? .visible : .hidden, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        PlaylistMoreMenu(
          playlist: playlist,
          songs: songs,
          showSongArtwork: $showSongArtwork
        )
      }
    }
    .animation(.easeInOut(duration: 0.2), value: scrollOffset < -180)
    .onAppear {
      if loader.songs == nil {
        showSongArtwork = PlaylistArtworkPreference.defaultValue(songCount: playlist.songCount)
      }
      loader.reload(playlistID: playlist.id, fallback: playlist.songListDTOs)
      RecentlyPlayedStore.shared.record(playlist)
    }
    .onChange(of: favorites.favoriteIDs) { _ in
      guard playlist.isFavorites else { return }
      loader.reload(playlistID: playlist.id, fallback: playlist.songListDTOs)
    }
  }
  private var playlistCoverURL: URL? {
    playlist.imageURL ?? loader.songs?.first?.imageURL
  }

  private func parallaxHero(width: CGFloat) -> some View {
    let baseSize: CGFloat = 240
    let stretch = max(0, scrollOffset)
    let shrink = max(0, -scrollOffset * 0.4)
    let size = max(140, baseSize + stretch * 0.6 - shrink)
    let blur = min(8, max(0, -scrollOffset / 30))
    let yOffset = scrollOffset > 0 ? -scrollOffset / 2 : 0
    return Group {
      if playlist.isFavorites {
        FavoritesArtworkTile()
      } else if let url = playlistCoverURL {
        LoadingImage(url: url, cornerRadius: 14)
      } else {
        PlaylistPlaceholderArtwork(seed: playlist.id)
      }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
    .blur(radius: blur)
    .opacity(1 - min(0.7, max(0, -scrollOffset / 250)))
    .frame(width: width)
    .offset(y: yOffset)
    .padding(.top, 12)
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
      .buttonStyle(PressableButtonStyle())
      Button {
        audioManager.playShuffled(from: songs)
      } label: {
        actionLabel(symbol: "shuffle", text: "Shuffle")
      }
      .buttonStyle(PressableButtonStyle())
    }
    .padding(.horizontal)
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

private struct PlaylistMoreMenu: View {
  let playlist: Playlist
  let songs: [Song]
  @Binding var showSongArtwork: Bool
  @StateObject private var downloads = DownloadManager.shared
  @ObservedObject private var savedStore: SavedPlaylistsStore = .shared
  private var pendingCount: Int {
    songs.filter { !downloads.isDownloaded($0.id) && !downloads.isDownloading($0.id) }.count
  }
  private var inFlightCount: Int {
    songs.filter { downloads.isDownloading($0.id) }.count
  }
  private var allDownloaded: Bool {
    !songs.isEmpty && pendingCount == 0 && inFlightCount == 0
  }
  private var canSaveToLibrary: Bool { !playlist.isFavorites && !playlist.isPersonal }
  private var isSaved: Bool { savedStore.isSaved(playlist) }
  var body: some View {
    Menu {
      Toggle(isOn: $showSongArtwork) {
        Label(showSongArtwork ? "Hide Song Art" : "Show Song Art", systemImage: "photo")
      }
      if canSaveToLibrary {
        Button {
          savedStore.toggle(playlist)
        } label: {
          if isSaved {
            Label("Remove from Library", systemImage: "checkmark.circle.fill")
          } else {
            Label("Add to Library", systemImage: "plus.circle")
          }
        }
      }
      if inFlightCount > 0 {
        Label("Downloading \(inFlightCount)…", systemImage: "arrow.down.circle")
      } else if allDownloaded {
        Button(role: .destructive) {
          for s in songs { downloads.remove(songID: s.id) }
        } label: {
          Label("Remove Downloads", systemImage: "trash")
        }
      } else {
        Button {
          for s in songs where !downloads.isDownloaded(s.id) && !downloads.isDownloading(s.id) {
            downloads.download(song: s)
          }
        } label: {
          let label = pendingCount < songs.count ? "Download Remaining" : "Download"
          Label(label, systemImage: "arrow.down.circle")
        }
      }
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(.appAccent)
        .frame(width: 32, height: 32)
        .contentShape(Rectangle())
    }
  }
}

private struct ScrollOffsetKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct PlaylistRow: View {
  let song: Song
  let showsArtwork: Bool
  var body: some View {
    SongRow(song: song, size: .regular, showsArtwork: showsArtwork)
      .padding(.horizontal)
      .padding(.vertical, 8)
  }
}

class PlaylistDetailViewModel: ObservableObject {
  @Published var songs: [Song]?
  @Published var isLoading = false
  private var loadedID: String?
  func reload(playlistID: String, fallback: [Song]? = nil) {
    loadedID = nil
    load(playlistID: playlistID, fallback: fallback)
  }
  func load(playlistID: String, fallback: [Song]?) {
    let alreadyFullyLoaded = (loadedID == playlistID) && (songs?.isEmpty == false)
    if alreadyFullyLoaded { return }
    loadedID = playlistID
    if songs?.isEmpty ?? true, let fallback = fallback, !fallback.isEmpty {
      self.songs = fallback
    }
    let isFavorites = playlistID == Playlist.favoritesID
    let urlString =
      isFavorites
      ? "\(StorageHost.api)/api/favorites/type?type=0"
      : "\(StorageHost.api)/api/playlist/\(playlistID)"
    guard let url = URL(string: urlString) else { return }
    isLoading = true
    var r = URLRequest(url: url)
    if let token = UserDefaults.standard.string(forKey: "nk.token"), !token.isEmpty {
      r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    GuestIdentity.applyIfNeeded(to: &r)
    URLSession.shared.dataTask(with: r) { [weak self] data, _, _ in
      guard let self = self else { return }
      let list = Self.decodeSongs(from: data)
      DispatchQueue.main.async {
        if let list = list, !list.isEmpty {
          self.songs = list
        }
        self.isLoading = false
      }
    }.resume()
  }
  private static func decodeSongs(from data: Data?) -> [Song]? {
    guard let data = data else { return nil }
    let decoder = JSONDecoder()
    if let wrapped = try? decoder.decode(PlaylistSongsResponse.self, from: data),
      !wrapped.songs.isEmpty
    {
      return wrapped.songs
    }
    if let playlist = try? decoder.decode(Playlist.self, from: data),
      let list = playlist.songListDTOs, !list.isEmpty
    {
      return list
    }
    if let list = (try? decoder.decode(LossyArray<Song>.self, from: data))?.elements, !list.isEmpty {
      return list
    }
    if let wrapped = try? decoder.decode([FavoriteSongEnvelope].self, from: data) {
      let unwrapped = wrapped.compactMap { $0.song }
      if !unwrapped.isEmpty { return unwrapped }
    }
    return nil
  }
}

private struct FavoriteSongEnvelope: Decodable {
  let song: Song?

  enum CodingKeys: String, CodingKey { case song, songData, songDTO }
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let decoded = try? container.decode(Song.self, forKey: .song) {
      song = decoded
    } else if let decoded = try? container.decode(Song.self, forKey: .songData) {
      song = decoded
    } else if let decoded = try? container.decode(Song.self, forKey: .songDTO) {
      song = decoded
    } else {
      song = nil
    }
  }
}

private struct PlaylistSongsResponse: Codable {
  let songs: [Song]

  enum CodingKeys: String, CodingKey {
    case items, songListDTOs, songs
  }
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    if let v = try? c.decode(LossyArray<Song>.self, forKey: .songListDTOs) {
      songs = v.elements
    } else if let v = try? c.decode(LossyArray<Song>.self, forKey: .items) {
      songs = v.elements
    } else if let v = try? c.decode(LossyArray<Song>.self, forKey: .songs) {
      songs = v.elements
    } else if let v = try? c.decode([Song].self, forKey: .songListDTOs) {
      songs = v
    } else if let v = try? c.decode([Song].self, forKey: .items) {
      songs = v
    } else if let v = try? c.decode([Song].self, forKey: .songs) {
      songs = v
    } else {
      songs = []
    }
  }
  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(songs, forKey: .songs)
  }
}

private enum PlaylistArtworkPreference {
  static func defaultValue(songCount: Int) -> Bool {
    songCount <= 200
  }
}
