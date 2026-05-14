import SwiftUI

struct RadioQueueView: View {
  @ObservedObject var radio = RadioController.shared
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
        header
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            if let current = radio.nowPlaying?.nowPlaying?.song {
              section(title: "Live Now") {
                row(song: current, isCurrent: true)
              }
            }
            if let next = radio.nowPlaying?.playingNext?.song {
              section(title: "Up Next") {
                row(song: next, isCurrent: false)
              }
            }
            if let history = radio.nowPlaying?.songHistory, !history.isEmpty {
              section(title: "Recently Played") {
                VStack(spacing: 0) {
                  ForEach(Array(history.prefix(20).enumerated()), id: \.offset) { _, item in
                    row(song: item.song, isCurrent: false)
                    Divider().background(.white.opacity(0.08)).padding(.leading, 64)
                  }
                }
              }
            }
          }
          .padding(.horizontal, 20)
          .padding(.bottom, 20)
        }
      }
    }
    .preferredColorScheme(.dark)
  }
  private var header: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(radio.nowPlaying?.station.name ?? "Radio")
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(.white)
        if let listeners = radio.nowPlaying?.listeners {
          Text("\(listeners.unique) listening")
            .font(.system(size: 12))
            .foregroundColor(.white.opacity(0.55))
        }
      }
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
  }
  @ViewBuilder
  private func section<Content: View>(title: String, @ViewBuilder content: () -> Content)
    -> some View
  {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.white.opacity(0.55))
        .textCase(.uppercase)
      content()
    }
  }
  private func row(song: RadioNowPlaying.SongInfo, isCurrent: Bool) -> some View {
    HStack(spacing: 12) {
      Group {
        if let art = song.art, let url = URL(string: art) {
          LoadingImage(url: url, cornerRadius: 6)
        } else {
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.white.opacity(0.1))
        }
      }
      .frame(width: 48, height: 48)
      VStack(alignment: .leading, spacing: 2) {
        Text(song.title ?? song.text ?? "")
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(isCurrent ? .appAccent : .white)
          .lineLimit(1)
        Text(song.artist ?? "")
          .font(.system(size: 13))
          .foregroundColor(.white.opacity(0.55))
          .lineLimit(1)
      }
      Spacer()
      if isCurrent {
        EqualizerBars(isAnimating: audioManager.isPlaying)
          .frame(width: 16, height: 16)
          .foregroundColor(.appAccent)
      }
    }
    .padding(.vertical, 6)
  }
}
