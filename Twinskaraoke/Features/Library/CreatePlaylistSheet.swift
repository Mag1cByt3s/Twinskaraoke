import SwiftUI

struct CreatePlaylistSheet: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var manager = UserPlaylistsManager.shared

  @State private var name = ""
  @State private var playlistDescription = ""
  @State private var isPublic = false
  @State private var isSaving = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Playlist Name", text: $name)
          TextField("Description (optional)", text: $playlistDescription)
        }

        Section {
          Toggle("Public", isOn: $isPublic)
        } footer: {
          Text("Public playlists can be discovered by other users.")
        }

        if let errorMessage {
          Section {
            Text(errorMessage)
              .foregroundStyle(.red)
              .font(.footnote)
          }
        }
      }
      .navigationTitle("New Playlist")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          GlassXButton(action: { dismiss() })
        }
        ToolbarItem(placement: .confirmationAction) {
          if isSaving {
            ProgressView()
          } else {
            GlassCheckmarkButton(
              action: { save() },
              isEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty
            )
          }
        }
      }
      .toolbarBackground(.hidden, for: .navigationBar)
      .interactiveDismissDisabled(isSaving)
    }
  }

  private func save() {
    isSaving = true
    errorMessage = nil

    let trimmedName = name.trimmingCharacters(in: .whitespaces)
    let desc = playlistDescription.trimmingCharacters(in: .whitespaces)

    manager.createPlaylist(
      name: trimmedName,
      description: desc.isEmpty ? nil : desc,
      isPublic: isPublic
    ) { success in
      isSaving = false
      if success {
        dismiss()
      } else {
        errorMessage = "Failed to create playlist. Please try again."
      }
    }
  }
}
