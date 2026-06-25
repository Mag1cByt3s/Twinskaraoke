import Combine
import SwiftUI

struct PlaylistListView: View {
    let title: String
    let playlists: [Playlist]
    var apiURL: ((Int, Int) -> String)?
    let cols = AM.Layout.playlistGridColumns
    @Environment(\.appReduceMotion) private var reduceMotion
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
            prefetchArtwork()
        }
        .onChange(of: Array(displayedPlaylists.prefix(12)).map(\.id)) { _, _ in
            prefetchArtwork()
        }
    }

    private func prefetchArtwork() {
        ArtworkPrefetcher.shared.prefetchPlaylists(
            Array(displayedPlaylists.prefix(12)),
            limit: 12,
            reason: "playlist list"
        )
    }
}

