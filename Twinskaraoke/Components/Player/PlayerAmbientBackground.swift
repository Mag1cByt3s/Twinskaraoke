import SwiftUI

#if canImport(UIKit)
  import SDWebImageSwiftUI
#endif

struct PlayerAmbientBackground: View {
  let artworkURL: URL?
  var isPlaying: Bool = true
  @State private var palette: ArtworkPalette = .placeholder

  var body: some View {
    ZStack {
      Color(.systemBackground)
      blurredArtworkLayer
      colorWashLayer
      vignetteLayer
    }
    .ignoresSafeArea()
    .animation(.easeInOut(duration: 0.4), value: artworkURL)
    .animation(.easeInOut(duration: 0.8), value: palette)
    .onAppear(perform: loadPalette)
    .onChange(of: artworkURL) { _ in loadPalette() }
  }

  @ViewBuilder
  private var blurredArtworkLayer: some View {
    if let artworkURL {
      GeometryReader { geo in
        let pixelSize = NSValue(cgSize: backgroundPixelSize(for: geo.size))
        WebImage(
          url: artworkURL,
          options: ImageCacheConfig.defaultOptions,
          context: [.imageThumbnailPixelSize: pixelSize]
        ) { image in
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(1.22)
            .blur(radius: 58)
            .saturation(1.05)
            .clipped()
            .transition(.opacity)
        } placeholder: {
          fallbackGradient
            .frame(width: geo.size.width, height: geo.size.height)
        }
      }
    } else {
      fallbackGradient
    }
  }

  private var colorWashLayer: some View {
    ZStack {
      LinearGradient(
        colors: [
          palette.primary.opacity(0.36),
          palette.secondary.opacity(0.22),
          palette.tertiary.opacity(0.28),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )

      Rectangle()
        .fill(Color.black.opacity(0.28))
    }
  }

  private var vignetteLayer: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color.black.opacity(0.52),
          Color.black.opacity(0.18),
          Color.black.opacity(0.58),
        ],
        startPoint: .top,
        endPoint: .bottom
      )

      RadialGradient(
        colors: [
          Color.clear,
          Color.black.opacity(0.14),
        ],
        center: .center,
        startRadius: 140,
        endRadius: 520
      )
    }
  }

  private var fallbackGradient: some View {
    LinearGradient(
      colors: [
        palette.primary,
        palette.secondary,
        palette.tertiary,
        palette.quaternary,
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  private func backgroundPixelSize(for displaySize: CGSize) -> CGSize {
    #if canImport(UIKit)
      let scale = UIScreen.main.scale
    #else
      let scale: CGFloat = 2
    #endif
    let width = max(displaySize.width, 1) * scale
    let height = max(displaySize.height, 1) * scale
    return CGSize(width: min(width, 1400), height: min(height, 1400))
  }

  private func loadPalette() {
    guard let url = artworkURL else {
      palette = .placeholder
      return
    }
    #if canImport(UIKit)
      SDWebImageManager.shared.loadImage(
        with: url,
        options: [.retryFailed],
        progress: nil
      ) { image, _, _, _, _, _ in
        guard let image else { return }
        let extracted = ArtworkPalette(image: image)
        DispatchQueue.main.async {
          palette = extracted
        }
      }
    #endif
  }
}
