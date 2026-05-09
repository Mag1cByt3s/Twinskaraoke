import CarPlay
import Combine
import Foundation
import MediaPlayer
import UIKit

@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  private var interfaceController: CPInterfaceController?
  private var subscriptions: Set<AnyCancellable> = []
  private let playlistsViewModel = PlaylistsViewModel()
  private weak var libraryTab: CPListTemplate?
  private weak var recentsTab: CPListTemplate?
  private weak var favoritesTab: CPListTemplate?

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    self.interfaceController = interfaceController
    let library = makeLibraryTab()
    let recents = makeRecentsTab()
    let favorites = makeFavoritesTab()
    libraryTab = library
    recentsTab = recents
    favoritesTab = favorites
    let tabBar = CPTabBarTemplate(templates: [library, recents, favorites])
    interfaceController.setRootTemplate(tabBar, animated: false, completion: nil)
    bindStores()
    playlistsViewModel.fetchPlaylists()
    playlistsViewModel.fetchFavoriteSongs()
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnectInterfaceController interfaceController: CPInterfaceController
  ) {
    self.interfaceController = nil
    subscriptions.removeAll()
  }

  private func makeLibraryTab() -> CPListTemplate {
    let template = CPListTemplate(title: "Library", sections: [])
    template.tabImage = UIImage(systemName: "music.note.list")
    refreshLibrary(template)
    return template
  }

  private func makeRecentsTab() -> CPListTemplate {
    let template = CPListTemplate(title: "Recents", sections: [])
    template.tabImage = UIImage(systemName: "clock")
    refreshRecents(template)
    return template
  }

  private func makeFavoritesTab() -> CPListTemplate {
    let template = CPListTemplate(title: "Favorites", sections: [])
    template.tabImage = UIImage(systemName: "heart")
    refreshFavorites(template)
    return template
  }

  private func refreshLibrary(_ template: CPListTemplate) {
    let saved = SavedPlaylistsStore.shared.playlists
    let server = playlistsViewModel.playlists
    let favorites = playlistsViewModel.favoritesPlaylist
    let serverIDs = Set(server.map { $0.id })
    let merged = [favorites] + server + saved.filter { !serverIDs.contains($0.id) }
    let items = merged.map { playlistRow(for: $0) }
    template.updateSections([CPListSection(items: items)])
  }

  private func refreshRecents(_ template: CPListTemplate) {
    let items = RecentlyPlayedStore.shared.playlists.map { playlistRow(for: $0) }
    template.updateSections([CPListSection(items: items)])
  }

  private func refreshFavorites(_ template: CPListTemplate) {
    let songs = playlistsViewModel.favoriteSongs
    let items = songs.map { song in songRow(song: song, queue: songs) }
    template.updateSections([CPListSection(items: items)])
  }

  private func bindStores() {
    SavedPlaylistsStore.shared.$playlists
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        guard let self, let template = self.libraryTab else { return }
        self.refreshLibrary(template)
      }
      .store(in: &subscriptions)
    RecentlyPlayedStore.shared.$playlists
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        guard let self, let template = self.recentsTab else { return }
        self.refreshRecents(template)
      }
      .store(in: &subscriptions)
    playlistsViewModel.$playlists
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        guard let self, let template = self.libraryTab else { return }
        self.refreshLibrary(template)
      }
      .store(in: &subscriptions)
    playlistsViewModel.$favoriteSongs
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        guard let self else { return }
        if let template = self.libraryTab { self.refreshLibrary(template) }
        if let template = self.favoritesTab { self.refreshFavorites(template) }
      }
      .store(in: &subscriptions)
  }

  private func playlistRow(for playlist: Playlist) -> CPListItem {
    let subtitle = playlist.songCount > 0 ? "\(playlist.songCount) songs" : nil
    let item = CPListItem(text: playlist.name, detailText: subtitle)
    item.accessoryType = .disclosureIndicator
    item.handler = { [weak self] _, completion in
      self?.openPlaylist(playlist)
      completion()
    }
    loadImage(playlist.imageURL) { [weak item] image in
      item?.setImage(image)
    }
    return item
  }

  private func songRow(song: Song, queue: [Song]) -> CPListItem {
    let item = CPListItem(text: song.title, detailText: song.displayArtist)
    item.handler = { [weak self] _, completion in
      AudioPlayerManager.shared.play(song: song, context: queue)
      self?.presentNowPlaying()
      completion()
    }
    loadImage(song.imageURL) { [weak item] image in
      item?.setImage(image)
    }
    return item
  }

  private func openPlaylist(_ playlist: Playlist) {
    let template = CPListTemplate(title: playlist.name, sections: [])
    if let inline = playlist.songListDTOs, !inline.isEmpty {
      template.updateSections([
        CPListSection(items: inline.map { songRow(song: $0, queue: inline) })
      ])
    } else {
      let placeholder = CPListItem(text: "Loading…", detailText: nil)
      placeholder.isEnabled = false
      template.updateSections([CPListSection(items: [placeholder])])
    }
    interfaceController?.pushTemplate(template, animated: true, completion: nil)
    fetchSongs(for: playlist.id, fallback: playlist.songListDTOs) {
      [weak self, weak template] songs in
      guard let self, let template, let songs, !songs.isEmpty else { return }
      template.updateSections([
        CPListSection(items: songs.map { self.songRow(song: $0, queue: songs) })
      ])
    }
  }

  private func presentNowPlaying() {
    guard let interfaceController else { return }
    let nowPlaying = CPNowPlayingTemplate.shared
    if interfaceController.topTemplate !== nowPlaying {
      interfaceController.pushTemplate(nowPlaying, animated: true, completion: nil)
    }
  }

  private func fetchSongs(
    for playlistID: String,
    fallback: [Song]?,
    completion: @escaping ([Song]?) -> Void
  ) {
    let isFavorites = playlistID == Playlist.favoritesID
    let urlString =
      isFavorites
      ? "\(StorageHost.api)/api/favorites/type?type=0"
      : "\(StorageHost.api)/api/playlist/\(playlistID)"
    guard let url = URL(string: urlString) else {
      completion(fallback)
      return
    }
    var request = URLRequest(url: url)
    if isFavorites, let token = UserDefaults.standard.string(forKey: "nk.token") {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    GuestIdentity.applyIfNeeded(to: &request)
    URLSession.shared.dataTask(with: request) { data, _, _ in
      let songs = Self.decodeSongs(from: data) ?? fallback
      DispatchQueue.main.async { completion(songs) }
    }.resume()
  }

  private static func decodeSongs(from data: Data?) -> [Song]? {
    guard let data else { return nil }
    let decoder = JSONDecoder()
    if let playlist = try? decoder.decode(Playlist.self, from: data),
      let list = playlist.songListDTOs, !list.isEmpty
    {
      return list
    }
    if let list = try? decoder.decode([Song].self, from: data), !list.isEmpty {
      return list
    }
    return nil
  }

  private func loadImage(_ url: URL?, completion: @escaping (UIImage?) -> Void) {
    guard let url else {
      completion(nil)
      return
    }
    URLSession.shared.dataTask(with: url) { data, _, _ in
      let image = data.flatMap { UIImage(data: $0) }
      DispatchQueue.main.async { completion(image) }
    }.resume()
  }
}
