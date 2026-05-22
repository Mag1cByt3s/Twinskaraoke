import SwiftUI

struct PlayerArtworkView: View {
  @EnvironmentObject var audioManager: AudioPlayerManager
  let song: Song
  let size: CGFloat
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
      .scaleEffect(audioManager.isPlaying ? 1.0 : 0.86)
      .animation(.spring(response: 0.5, dampingFraction: 0.78), value: audioManager.isPlaying)
      if audioManager.isBuffering {
        RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous)
          .fill(Color.appArtworkOverlay)
          .frame(width: size, height: size)
        LoadingIndicator(size: 64)
      }
    }
    .frame(maxWidth: .infinity)
  }
}
