import SwiftUI

struct PlayerView: View {
  @EnvironmentObject var audioManager: AudioManager
  @Environment(\.colorScheme) private var colorScheme
  var body: some View {
    if let song = audioManager.currentSong {
      GeometryReader { geo in
        let artSize = min(geo.size.width * 0.45, 80)
        ScrollView {
          VStack(spacing: 6) {
            ZStack {
              AsyncImage(url: song.imageURL) { image in
                image.resizable().scaledToFit()
              } placeholder: {
                RoundedRectangle(cornerRadius: 10)
                  .fill(Color.secondary.opacity(0.25))
              }
              .frame(width: artSize, height: artSize)
              .clipShape(RoundedRectangle(cornerRadius: 10))
              .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
              if audioManager.isLoading {
                RoundedRectangle(cornerRadius: 10)
                  .fill(overlayColor)
                  .frame(width: artSize, height: artSize)
                ProgressView()
                  .progressViewStyle(CircularProgressViewStyle(tint: .appAccent))
                  .scaleEffect(0.6)
              }
            }
            .frame(width: artSize, height: artSize)
            VStack(spacing: 1) {
              Text(song.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
              Text(song.artistName)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 1) {
              let total = max(audioManager.duration, 1)
              ProgressView(value: min(audioManager.currentTime, total), total: total)
                .tint(.secondary.opacity(0.8))
                .scaleEffect(y: 0.6)
              HStack {
                Text(formatTime(audioManager.currentTime))
                Spacer()
                Text("-" + formatTime(max(0, audioManager.duration - audioManager.currentTime)))
              }
              .font(.system(size: 9, design: .monospaced))
              .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)
            HStack(spacing: 16) {
              Button {
                audioManager.playPrevious()
              } label: {
                Image(systemName: "backward.fill")
                  .font(.system(size: 20))
                  .foregroundColor(.primary)
              }
              .buttonStyle(.plain)
              .disabled(audioManager.isLoading)
              Button {
                audioManager.togglePlayPause()
              } label: {
                Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                  .font(.system(size: 30))
                  .foregroundColor(.primary)
              }
              .buttonStyle(.plain)
              Button {
                audioManager.playNext()
              } label: {
                Image(systemName: "forward.fill")
                  .font(.system(size: 20))
                  .foregroundColor(.primary)
              }
              .buttonStyle(.plain)
              .disabled(audioManager.isLoading)
            }
            .padding(.top, 2)
            HStack(spacing: 20) {
              Button {
                audioManager.toggleShuffle()
              } label: {
                Image(systemName: "shuffle")
                  .font(.system(size: 13))
                  .foregroundColor(audioManager.isShuffleOn ? .appAccent : .secondary)
              }
              .buttonStyle(.plain)
              Button {
                audioManager.toggleMode()
              } label: {
                Image(systemName: audioManager.playbackMode.iconName)
                  .font(.system(size: 13))
                  .foregroundColor(
                    audioManager.playbackMode == .singleLoop ? .appAccent : .secondary)
              }
              .buttonStyle(.plain)
              NavigationLink(destination: QueueView().environmentObject(audioManager)) {
                Image(systemName: "list.bullet")
                  .font(.system(size: 13))
                  .foregroundColor(.secondary)
              }
              .buttonStyle(.plain)
            }
            .padding(.top, 4)
          }
          .frame(minHeight: geo.size.height)
        }
      }
      .background(
        Group {
          if let url = audioManager.currentSong?.imageURL {
            AsyncImage(url: url) { image in
              image.resizable().scaledToFill()
            } placeholder: {
              backgroundBase
            }
            .blur(radius: 30)
            .opacity(0.35)
            .ignoresSafeArea()
          } else {
            backgroundBase.ignoresSafeArea()
          }
        }
      )
      .navigationTitle("Now Playing")
    } else {
      VStack(spacing: 8) {
        Image(systemName: "music.note")
          .font(.system(size: 28))
          .foregroundColor(.secondary)
        Text("No song playing")
          .font(.system(size: 13))
          .foregroundColor(.secondary)
      }
      .navigationTitle("Now Playing")
    }
  }
  private var backgroundBase: Color {
    colorScheme == .dark
      ? Color.black
      : Color(red: 0.95, green: 0.96, blue: 0.99)
  }
  private var overlayColor: Color {
    colorScheme == .dark
      ? Color.black.opacity(0.3)
      : Color.white.opacity(0.45)
  }
  private func formatTime(_ time: Double) -> String {
    if time.isNaN || time.isInfinite { return "0:00" }
    let mins = Int(time) / 60
    let secs = Int(time) % 60
    return String(format: "%d:%02d", mins, secs)
  }
}
