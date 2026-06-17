import SDWebImageSwiftUI
import SwiftUI

enum ImageCacheConfig {
  private static var didApply = false
  static func applyLimits() {
    guard !didApply else { return }
    didApply = true
    let cfg = SDImageCache.shared.config
    cfg.maxMemoryCost = 32 * 1024 * 1024
    cfg.maxMemoryCount = 48
    cfg.maxDiskSize = 256 * 1024 * 1024
    cfg.shouldCacheImagesInMemory = true
    cfg.shouldUseWeakMemoryCache = true
    cfg.maxDiskAge = 30 * 24 * 60 * 60
    SDImageCache.shared.clearMemory()
    let dl = SDWebImageDownloader.shared
    dl.config.maxConcurrentDownloads = 6
    dl.requestModifier = SDWebImageDownloaderRequestModifier { request in
      var r = request
      r.cachePolicy = .returnCacheDataElseLoad
      r.timeoutInterval = 15
      return r
    }
    #if canImport(UIKit)
      NotificationCenter.default.addObserver(
        forName: UIApplication.didReceiveMemoryWarningNotification,
        object: nil, queue: .main
      ) { _ in
        SDImageCache.shared.clearMemory()
      }
    #endif
  }
  static let thumbnailPixelSize = CGSize(width: 480, height: 480)
  /// Keep list artwork on normal priority so image fetch/decode work does not
  /// compete with touch tracking during scroll. Callers can opt into full size separately.
  static let defaultOptions: SDWebImageOptions = [
    .retryFailed,
    .scaleDownLargeImages
  ]
}

struct LoadingImage: View {
  let url: URL?
  var cornerRadius: CGFloat = 8
  var contentMode: ContentMode = .fill
  var showsLoading: Bool = true
  var lowResURL: URL? = nil
  var transparentBackground: Bool = false
  var fullResolution: Bool = false
  /// Use this for fixed-size thumbnails to avoid a GeometryReader per cell and
  /// to downsample the source image to the actual display size.
  var fixedDisplaySize: CGSize? = nil
  @State private var fullLoaded: Bool = false
  @State private var loadFailed: Bool = false
  @State private var renderedFullURL: URL?
  var body: some View {
    Group {
      if let fixedDisplaySize {
        imageContent(size: fixedDisplaySize)
          .frame(width: fixedDisplaySize.width, height: fixedDisplaySize.height)
      } else {
        GeometryReader { geo in
          imageContent(size: geo.size)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .onChange(of: url) {
      fullLoaded = false
      loadFailed = false
      renderedFullURL = nil
    }
  }

  @ViewBuilder
  private func imageContent(size: CGSize) -> some View {
    let pixelSize = NSValue(cgSize: thumbnailPixelSize(for: size))
    let context: [SDWebImageContextOption: Any] =
      fullResolution
      ? [:] : [
        .imageThumbnailPixelSize: pixelSize,
        .imageDecodeOptions: [SDImageCoderOption.decodeScaleFactor: 1.0]
      ]
    ZStack {
      if !transparentBackground {
        MusicArtworkPlaceholder()
      }
      if let lowResURL, !fullLoaded {
        WebImage(
          url: lowResURL,
          options: [.retryFailed, .scaleDownLargeImages, .fromCacheOnly],
          context: [.imageThumbnailPixelSize: NSValue(cgSize: CGSize(width: 120, height: 120))]
        ) { image in
          image
            .resizable()
            .aspectRatio(contentMode: contentMode)
            .frame(width: size.width, height: size.height)
            .clipped()
            .blur(radius: 2)
        } placeholder: {
          Color.clear
        }
      }
      if let url, !loadFailed {
        WebImage(
          url: url,
          options: ImageCacheConfig.defaultOptions,
          context: context
        ) { image in
          image
            .resizable()
            .aspectRatio(contentMode: contentMode)
            .frame(width: size.width, height: size.height)
            .clipped()
            .onAppear {
              markRendered(url)
            }
        } placeholder: {
          Color.clear
        }
        .onFailure { _ in
          markFinishedAfterFailure()
        }
        .onSuccess { _, _, _ in
          markRendered(url)
        }
        .transition(.opacity.animation(.easeOut(duration: 0.15)))
      }

      if shouldShowLoading {
        LoadingIndicator(size: min(size.width, size.height) * 0.5)
          .transition(.opacity.animation(.easeOut(duration: 0.12)))
      }
    }
  }

  private var shouldShowLoading: Bool {
    showsLoading
      && lowResURL == nil
      && url != nil
      && !fullLoaded
      && !loadFailed
      && renderedFullURL != url
  }

  private func markRendered(_ loadedURL: URL) {
    guard renderedFullURL != loadedURL || !fullLoaded || loadFailed else { return }
    withAnimation(.easeOut(duration: 0.12)) {
      renderedFullURL = loadedURL
      fullLoaded = true
      loadFailed = false
    }
  }

  private func markFinishedAfterFailure() {
    withAnimation(.easeOut(duration: 0.12)) {
      loadFailed = true
    }
  }

  private func thumbnailPixelSize(for displaySize: CGSize) -> CGSize {
    #if canImport(UIKit)
      let scale = UIScreen.main.scale
    #else
      let scale: CGFloat = 2
    #endif
    let w = max(displaySize.width, 1) * scale
    let h = max(displaySize.height, 1) * scale
    let cap = ImageCacheConfig.thumbnailPixelSize
    return CGSize(width: min(w, cap.width), height: min(h, cap.height))
  }

  private struct MusicArtworkPlaceholder: View {
    var body: some View {
      LinearGradient(
        colors: [
          .appPlaceholderSecondary,
          .appPlaceholderPrimary,
          .appPlaceholderQuaternary,
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    }
  }
}

struct LoadingIndicator: View {
  var size: CGFloat = 20
  var tint: Color = .secondary
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var isAnimating = false

  var body: some View {
    ZStack {
      ForEach(0..<tickCount, id: \.self) { index in
        Capsule(style: .continuous)
          .fill(tint.opacity(opacity(for: index)))
          .frame(width: tickWidth, height: tickLength)
          .offset(y: -tickRadius)
          .rotationEffect(.degrees(Double(index) * tickAngle))
      }
    }
    .rotationEffect(.degrees(isAnimating ? 360 : 0))
    .frame(width: containerSize, height: containerSize)
    .contentShape(Rectangle())
    .animation(
      reduceMotion ? nil : .linear(duration: 0.82).repeatForever(autoreverses: false),
      value: isAnimating
    )
    .onAppear {
      isAnimating = !reduceMotion
    }
    .onChange(of: reduceMotion) { _, reduceMotion in
      isAnimating = !reduceMotion
    }
    .accessibilityLabel("Loading")
  }

  private var containerSize: CGFloat {
    min(max(size, 16), 34)
  }

  private var tickCount: Int {
    12
  }

  private var tickAngle: Double {
    360 / Double(tickCount)
  }

  private var tickWidth: CGFloat {
    max(containerSize * 0.07, 1.5)
  }

  private var tickLength: CGFloat {
    max(containerSize * 0.23, 4)
  }

  private var tickRadius: CGFloat {
    containerSize * 0.31
  }

  private func opacity(for index: Int) -> Double {
    let progress = Double(index) / Double(max(tickCount - 1, 1))
    return reduceMotion ? 0.58 : 0.16 + progress * 0.62
  }

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }
}

struct MusicSkeletonShimmer: ViewModifier {
  var isActive: Bool
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var phase: CGFloat = -0.8

  func body(content: Content) -> some View {
    content
      .overlay {
        GeometryReader { proxy in
          shimmer(width: proxy.size.width)
            .opacity(effectiveActive ? 1 : 0)
            .blendMode(.plusLighter)
            .mask(content)
        }
        .clipShape(Rectangle())
        .allowsHitTesting(false)
      }
      .onAppear {
        guard effectiveActive else {
          phase = -0.8
          return
        }
        withAnimation(.linear(duration: 1.65).repeatForever(autoreverses: false)) {
          phase = 1.8
        }
      }
      .onChange(of: effectiveActive) { _, effectiveActive in
        if effectiveActive {
          phase = -0.8
          withAnimation(.linear(duration: 1.65).repeatForever(autoreverses: false)) {
            phase = 1.8
          }
        } else {
          withAnimation(nil) {
            phase = -0.8
          }
        }
      }
  }

  private var effectiveActive: Bool {
    isActive && !AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  private func shimmer(width: CGFloat) -> some View {
    LinearGradient(
      colors: [
        .clear,
        Color.white.opacity(0.22),
        Color.appAccent.opacity(0.075),
        .clear,
      ],
      startPoint: .top,
      endPoint: .bottom
    )
    .frame(width: max(width * 0.36, 56))
    .rotationEffect(.degrees(12))
    .offset(x: width * phase)
  }
}

extension View {
  func musicSkeletonShimmer(active: Bool) -> some View {
    modifier(MusicSkeletonShimmer(isActive: active))
  }
}

struct MusicEmptyState: View {
  let systemImage: String
  let title: String
  let message: String

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.system(size: 28, weight: .semibold))
        .foregroundColor(.appAccent)
        .frame(width: 64, height: 64)
        .background(Color.appAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
      VStack(spacing: 4) {
        Text(title)
          .font(.system(size: 19, weight: .bold))
          .foregroundColor(.primary)
          .multilineTextAlignment(.center)
        Text(message)
          .font(.system(size: 14))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .lineLimit(3)
      }
    }
    .frame(maxWidth: 320)
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 24)
  }
}
