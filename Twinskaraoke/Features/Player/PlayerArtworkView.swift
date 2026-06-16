import SwiftUI

struct PlayerArtworkView: View {
  @EnvironmentObject var audioManager: AudioPlayerManager
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  let song: Song
  let size: CGFloat
  var onTap: (() -> Void)?
  var body: some View {
    ZStack {
      LoadingImage(
        url: audioManager.displayImageURL(for: song), cornerRadius: AM.Radius.hero,
        contentMode: .fill
      )
      .frame(width: size, height: size)
      .clipShape(RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous))
      .id(song.id)
      .amShadow(audioManager.isPlaying ? AM.Shadow.heroPlaying : AM.Shadow.heroIdle)
      .animation(artworkPlaybackAnimation, value: audioManager.isPlaying)
      if audioManager.isBuffering {
        bufferingOverlay
          .transition(bufferingTransition)
      }
    }
    .frame(maxWidth: .infinity)
    .animation(bufferingAnimation, value: audioManager.isBuffering)
    .onTapGesture {
      if onTap != nil {
        AppHaptic.selection.play()
      }
      onTap?()
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(song.title) artwork")
    .accessibilityHint(onTap == nil ? "Album artwork." : "Opens full-screen artwork.")
    .accessibilityAction {
      onTap?()
    }
  }

  private var bufferingOverlay: some View {
    ZStack {
      RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous)
        .fill(Color.appArtworkOverlay)
        .frame(width: size, height: size)
      LoadingIndicator(size: min(48, max(30, size * 0.13)))
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
    reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.86)
  }

  private var bufferingAnimation: Animation? {
    reduceMotion ? nil : .easeInOut(duration: 0.18)
  }

  private var bufferingTransition: AnyTransition {
    reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96))
  }
}
