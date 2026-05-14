import SwiftUI

/// Sheet for picking a playlist to add a song to.
struct AddToPlaylistSheet: View {
  let song: Song
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var manager = UserPlaylistsManager.shared

  @State private var inFlight: Set<String> = []
  @State private var added: Set<String> = []

  var body: some View {
    NavigationStack {
      Group {
        if manager.playlists.isEmpty {
          emptyState
        } else {
          List(manager.playlists) { playlist in
            Button {
              add(to: playlist)
            } label: {
              HStack(spacing: 12) {
                PlaylistArtwork(playlist: playlist.asPlaylist(), cornerRadius: 6)
                  .frame(width: 44, height: 44)
                  .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                  Text(playlist.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                  Text("\(playlist.songCount) songs")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                }
                Spacer()
                if inFlight.contains(playlist.id) {
                  LoadingIndicator(size: 18)
                } else if added.contains(playlist.id) {
                  Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                }
              }
            }
            .disabled(inFlight.contains(playlist.id) || added.contains(playlist.id))
          }
        }
      }
      .navigationTitle("Add to Playlist")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          GlassXButton(action: { dismiss() })
        }
      }
      .toolbarBackground(.hidden, for: .navigationBar)
      .task { manager.loadIfNeeded() }
    }
  }

  private var emptyState: some View {
    VStack(spacing: 16) {
      Image(systemName: "music.note.list")
        .font(.system(size: 48))
        .foregroundColor(.secondary)
      Text("No playlists")
        .font(.headline)
      Text("Create a playlist first to add songs.")
        .font(.subheadline)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func add(to playlist: UserPlaylist) {
    inFlight.insert(playlist.id)
    manager.addSong(song.id, toPlaylist: playlist.id) { success in
      inFlight.remove(playlist.id)
      if success {
        added.insert(playlist.id)
      }
    }
  }
}
