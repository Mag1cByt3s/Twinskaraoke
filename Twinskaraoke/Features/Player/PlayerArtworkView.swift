import SwiftUI

struct PlayerArtworkView: View {
  @EnvironmentObject var audioManager: AudioPlayerManager
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  let song: Song
  let size: CGFloat
  var onTap: (() -> Void)?
  var body: some View {
    Group {
      if let onTap {
        Button {
          AppHaptic.selection.play()
          onTap()
        } label: {
          artwork
        }
        .buttonStyle(PressableButtonStyle(scale: 0.985, dim: 0.88, haptic: nil))
      } else {
        artwork
      }
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(song.title) artwork")
    .accessibilityHint(onTap == nil ? "Album artwork." : "Opens full-screen artwork.")
    .accessibilityAction {
      onTap?()
    }
  }

  private var artwork: some View {
    ZStack {
      RemoteArtworkImage(
        url: audioManager.displayImageURL(for: song), cornerRadius: AM.Radius.hero,
        contentMode: .fill
      )
      .frame(width: size, height: size)
      .clipShape(RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous))
      .id(song.id)
      .scaleEffect(audioManager.isPlaying ? 1.0 : 0.88)
      .amShadow(audioManager.isPlaying ? AM.Shadow.heroPlaying : AM.Shadow.heroIdle)
      .animation(artworkPlaybackAnimation, value: audioManager.isPlaying)
      if audioManager.isBuffering {
        bufferingOverlay
          .transition(bufferingTransition)
      }
    }
    .animation(bufferingAnimation, value: audioManager.isBuffering)
  }

  private var bufferingOverlay: some View {
    ZStack {
      RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous)
        .fill(Color.appArtworkOverlay)
        .frame(width: size, height: size)
      ProgressView()
        .controlSize(.large)
    }
    .accessibilityHidden(true)
  }

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  private var artworkPlaybackAnimation: Animation? {
    reduceMotion ? nil : AppMotion.spring(response: 0.55, dampingFraction: 0.86)
  }

  private var bufferingAnimation: Animation? {
    reduceMotion ? nil : AppMotion.spring(response: 0.25, dampingFraction: 0.86)
  }

  private var bufferingTransition: AnyTransition {
    reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96))
  }
}
