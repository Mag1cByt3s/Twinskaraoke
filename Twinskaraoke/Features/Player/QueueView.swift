import SwiftUI

struct QueueView: View {
  @EnvironmentObject var audioManager: AudioPlayerManager
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    ZStack {
      LinearGradient(
        colors: [Color(red: 0.10, green: 0.10, blue: 0.12), Color.black],
        startPoint: .top, endPoint: .bottom
      )
      .ignoresSafeArea()
      VStack(spacing: 0) {
        HStack {
          Text("Playing Next")
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.white)
          Spacer()
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 16, weight: .semibold))
              .foregroundColor(.white.opacity(0.85))
              .frame(width: 36, height: 36)
          }
          .modifier(GlassCircle())
          .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6))
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        HStack(spacing: 24) {
          QueueModeButton(
            symbol: "shuffle",
            isActive: audioManager.isShuffled
          ) {
            audioManager.toggleShuffle()
          }
          QueueModeButton(
            symbol: audioManager.repeatMode.symbol,
            isActive: audioManager.repeatMode.isActive
          ) {
            audioManager.toggleRepeat()
          }
          QueueModeButton(
            symbol: "infinity",
            isActive: audioManager.autoplayEnabled
          ) {
            audioManager.toggleAutoplay()
          }
          QueueModeButton(
            symbol: "wand.and.stars",
            isActive: audioManager.autoMixEnabled
          ) {
            audioManager.autoMixEnabled.toggle()
          }
          Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        if let current = audioManager.currentSong {
          HStack(spacing: 12) {
            LoadingImage(url: current.imageURL, cornerRadius: 6)
              .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
              Text(current.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
              Text(current.displayArtist)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(1)
            }
            Spacer()
            EqualizerBars(isAnimating: audioManager.isPlaying)
              .frame(width: 16, height: 16)
              .foregroundColor(.appAccent)
          }
          .padding(.horizontal, 20)
          .padding(.bottom, 14)
          Divider()
            .background(.white.opacity(0.12))
            .padding(.horizontal, 20)
        }
        if upNextSongs.isEmpty {
          VStack(spacing: 8) {
            Image(systemName: "music.note.list")
              .font(.system(size: 32))
              .foregroundColor(.white.opacity(0.35))
            Text("No songs queued")
              .font(.system(size: 14))
              .foregroundColor(.white.opacity(0.55))
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          List {
            ForEach(upNextSongs) { song in
              QueueRow(song: song)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                .contentShape(Rectangle())
                .onTapGesture {
                  audioManager.play(song: song, context: audioManager.queue)
                }
            }
            .onMove { source, destination in
              audioManager.moveInUpNext(from: source, to: destination)
            }
            .onDelete { indices in
              audioManager.removeFromUpNext(at: indices)
            }
          }
          .listStyle(.plain)
          .scrollContentBackground(.hidden)
          .environment(\.editMode, .constant(.active))
          .animation(.easeInOut(duration: 0.35), value: audioManager.isShuffled)
          .animation(.easeInOut(duration: 0.25), value: upNextSongs.map(\.id))
        }
      }
    }
    .preferredColorScheme(.dark)
  }
  private var upNextSongs: [Song] {
    guard let current = audioManager.currentSong,
      let idx = audioManager.queue.firstIndex(of: current),
      idx + 1 < audioManager.queue.count
    else { return [] }
    return Array(audioManager.queue[(idx + 1)...])
  }
}

struct QueueRow: View {
  let song: Song
  var body: some View {
    HStack(spacing: 12) {
      LoadingImage(url: song.imageURL, cornerRadius: 6)
        .frame(width: 48, height: 48)
      VStack(alignment: .leading, spacing: 2) {
        Text(song.title)
          .font(.system(size: 15, weight: .medium))
          .foregroundColor(.white)
          .lineLimit(1)
        Text(song.displayArtist)
          .font(.system(size: 13))
          .foregroundColor(.white.opacity(0.6))
          .lineLimit(1)
      }
      Spacer()
    }
  }
}

struct QueueModeButton: View {
  let symbol: String
  let isActive: Bool
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(isActive ? .black : .white)
        .frame(width: 38, height: 38)
        .modifier(QueueModeBackground(isActive: isActive))
    }
    .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.75))
  }
}

private struct QueueModeBackground: ViewModifier {
  let isActive: Bool
  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      if isActive {
        content.background(Circle().fill(Color.white))
      } else {
        content.glassEffect(in: Circle())
      }
    } else {
      content.background(
        Circle()
          .fill(isActive ? Color.white : Color.white.opacity(0.16))
      )
    }
  }
}
