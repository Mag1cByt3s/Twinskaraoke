import SwiftUI

struct AddToPlaylistSheet: View {
  let song: Song
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @ObservedObject private var manager = UserPlaylistsManager.shared

  @State private var inFlight: Set<String> = []
  @State private var added: Set<String> = []
  @State private var failed: Set<String> = []
  @State private var showCreatePlaylist = false

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 22) {
          AddToPlaylistSongPreview(song: song)
            .padding(.top, 8)

          if manager.isLoading && manager.playlists.isEmpty {
            AddToPlaylistLoadingRows()
              .transition(.opacity)
          } else if manager.playlists.isEmpty {
            emptyState
              .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
          } else {
            VStack(spacing: 10) {
              ForEach(manager.playlists) { playlist in
                Button {
                  add(to: playlist)
                } label: {
                  AddToPlaylistRow(
                    playlist: playlist,
                    state: state(for: playlist)
                  )
                }
                .buttonStyle(PressableButtonStyle(scale: 0.98, dim: 0.82, haptic: rowHaptic(for: playlist)))
                .disabled(inFlight.contains(playlist.id) || added.contains(playlist.id))
                .contextMenu {
                  Button {
                    add(to: playlist)
                  } label: {
                    Label("Add to Playlist", systemImage: "plus.circle")
                  }
                  Button {
                    AppHaptic.selection.play()
                    showCreatePlaylist = true
                  } label: {
                    Label("New Playlist", systemImage: "music.note.list")
                  }
                } preview: {
                  AddToPlaylistPreview(playlist: playlist)
                }
              }
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
          }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
      }
      .smoothScrolling()
      .musicScreenBackground()
      .safeAreaInset(edge: .bottom) {
        if !manager.playlists.isEmpty {
          Button {
            AppHaptic.selection.play()
            showCreatePlaylist = true
          } label: {
            Label("New Playlist", systemImage: "plus")
              .font(.system(size: 16, weight: .semibold))
              .foregroundColor(.appControlActiveForeground)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 14)
              .background(Color.appControlActiveFill, in: Capsule())
          }
          .buttonStyle(PressableButtonStyle(scale: 0.97, dim: 0.78, haptic: .medium))
          .padding(.horizontal, 20)
          .padding(.top, 10)
          .padding(.bottom, 10)
          .background(.regularMaterial)
        } else {
          EmptyView()
        }
      }
      .navigationTitle("Add to Playlist")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          GlassXButton(action: {
            AppHaptic.selection.play()
            dismiss()
          })
        }
        ToolbarItem(placement: .confirmationAction) {
          GlassCheckmarkButton(
            action: {
              AppHaptic.selection.play()
              dismiss()
            },
            isEnabled: !added.isEmpty
          )
        }
      }
      .toolbarBackground(.hidden, for: .navigationBar)
      .task { manager.loadIfNeeded() }
      .sheet(isPresented: $showCreatePlaylist) {
        CreatePlaylistSheet()
      }
      .animation(
        reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.84),
        value: manager.playlists.map(\.id))
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: inFlight)
      .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82), value: added)
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: failed)
    }
  }

  private var emptyState: some View {
    VStack(spacing: 18) {
      MusicEmptyState(
        title: "No Playlists",
        message: "Create a playlist first to save this song."
      )
      Button {
        AppHaptic.selection.play()
        showCreatePlaylist = true
      } label: {
        Label("New Playlist", systemImage: "plus")
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.appControlActiveForeground)
          .padding(.horizontal, 22)
          .padding(.vertical, 12)
          .background(Color.appControlActiveFill, in: Capsule())
      }
      .buttonStyle(PressableButtonStyle(scale: 0.95, dim: 0.78, haptic: .medium))
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 32)
  }

  private func state(for playlist: UserPlaylist) -> AddToPlaylistRowState {
    if inFlight.contains(playlist.id) { return .adding }
    if added.contains(playlist.id) { return .added }
    if failed.contains(playlist.id) { return .failed }
    return .idle
  }

  private func rowHaptic(for playlist: UserPlaylist) -> AppHaptic? {
    added.contains(playlist.id) || inFlight.contains(playlist.id) ? nil : .selection
  }

  private func add(to playlist: UserPlaylist) {
    guard !inFlight.contains(playlist.id), !added.contains(playlist.id) else { return }
    inFlight.insert(playlist.id)
    failed.remove(playlist.id)
    manager.addSong(song.id, toPlaylist: playlist.id) { success in
      inFlight.remove(playlist.id)
      if success {
        AppHaptic.success.play()
        added.insert(playlist.id)
      } else {
        AppHaptic.error.play()
        failed.insert(playlist.id)
      }
    }
  }
}

private enum AddToPlaylistRowState: Hashable {
  case idle
  case adding
  case added
  case failed
}

private struct AddToPlaylistSongPreview: View {
  let song: Song

  var body: some View {
    HStack(spacing: 14) {
      LoadingImage(url: song.imageURL, cornerRadius: 10)
        .frame(width: 74, height: 74)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: Color.appShadow, radius: 10, y: 6)

      VStack(alignment: .leading, spacing: 4) {
        Text("Add Song")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(.secondary)
          .textCase(.uppercase)
        Text(song.title)
          .font(.system(size: 19, weight: .bold))
          .foregroundColor(.primary)
          .lineLimit(2)
        Text(song.displayArtist)
          .font(.system(size: 14))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(Color.appControlInactiveFill, in: RoundedRectangle(cornerRadius: AM.Radius.sheet, style: .continuous))
    .accessibilityElement(children: .combine)
  }
}

private struct AddToPlaylistRow: View {
  let playlist: UserPlaylist
  let state: AddToPlaylistRowState

  var body: some View {
    HStack(spacing: 12) {
      PlaylistArtwork(playlist: playlist.asPlaylist(), cornerRadius: 7)
        .frame(width: 50, height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

      VStack(alignment: .leading, spacing: 3) {
        Text(playlist.name)
          .font(.system(size: 16, weight: .medium))
          .foregroundColor(.primary)
          .lineLimit(1)
        Text(subtitle)
          .font(.system(size: 13))
          .foregroundColor(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 12)

      statusView
        .frame(width: 28, height: 28)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(rowBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(borderColor, lineWidth: state == .idle ? 0 : 1)
    }
    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
  }

  private var subtitle: String {
    switch state {
    case .idle:
      return "\(playlist.songCount) songs"
    case .adding:
      return "Adding..."
    case .added:
      return "Added"
    case .failed:
      return "Could not add. Tap to retry."
    }
  }

  @ViewBuilder
  private var statusView: some View {
    switch state {
    case .idle:
      Image(systemName: "plus.circle")
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(Color.appAccent)
    case .adding:
      LoadingIndicator(size: 22)
    case .added:
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(.green)
    case .failed:
      Image(systemName: "exclamationmark.circle.fill")
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(Color.appAccent)
    }
  }

  private var rowBackground: Color {
    switch state {
    case .idle:
      return Color.appControlInactiveFill
    case .adding:
      return Color.appControlInactiveFill
    case .added:
      return Color.green.opacity(0.12)
    case .failed:
      return Color.appAccent.opacity(0.12)
    }
  }

  private var borderColor: Color {
    switch state {
    case .idle, .adding:
      return .clear
    case .added:
      return .green.opacity(0.35)
    case .failed:
      return Color.appAccent.opacity(0.35)
    }
  }

  private var accessibilityLabel: String {
    switch state {
    case .idle:
      return "Add to \(playlist.name), \(playlist.songCount) songs"
    case .adding:
      return "Adding to \(playlist.name)"
    case .added:
      return "Added to \(playlist.name)"
    case .failed:
      return "Could not add to \(playlist.name). Tap to retry."
    }
  }
}

private struct AddToPlaylistLoadingRows: View {
  var body: some View {
    VStack(spacing: 10) {
      ForEach(0..<6, id: \.self) { _ in
        HStack(spacing: 12) {
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.appPlaceholderPrimary)
            .frame(width: 50, height: 50)
          VStack(alignment: .leading, spacing: 3) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
              .fill(Color.appPlaceholderSecondary)
              .frame(width: 160, height: 16)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
              .fill(Color.appPlaceholderPrimary)
              .frame(width: 80, height: 13)
          }
          Spacer()
          Circle()
            .fill(Color.appPlaceholderPrimary)
            .frame(width: 28, height: 28)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.appControlInactiveFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      }
    }
    .redacted(reason: .placeholder)
    .musicSkeletonShimmer(active: true)
    .accessibilityLabel("Loading playlists")
  }
}

private struct AddToPlaylistPreview: View {
  let playlist: UserPlaylist

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      PlaylistArtwork(playlist: playlist.asPlaylist(), cornerRadius: 10)
        .frame(width: 220, height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

      VStack(alignment: .leading, spacing: 3) {
        Text(playlist.isPublic ? "Public Playlist" : "Private Playlist")
          .font(.system(size: 12, weight: .bold))
          .foregroundColor(.appAccent)
          .textCase(.uppercase)
        Text(playlist.name)
          .font(.system(size: 17, weight: .semibold))
          .foregroundColor(.primary)
          .lineLimit(2)
        Text("\(playlist.songCount) songs")
          .font(.system(size: 14))
          .foregroundColor(.secondary)
      }
    }
    .padding(16)
    .frame(width: 252, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}
