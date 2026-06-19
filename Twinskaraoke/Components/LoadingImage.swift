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
    // Keep network/decode concurrency below the point where image work can steal
    // main-thread time from touch tracking on ProMotion devices.
    dl.config.maxConcurrentDownloads = 4
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
        MusicArtworkPlaceholder(cornerRadius: cornerRadius)
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
        .transition(.opacity.animation(AppMotion.easeOut(duration: 0.15)))
      }

    }
  }

  private func markRendered(_ loadedURL: URL) {
    guard renderedFullURL != loadedURL || !fullLoaded || loadFailed else { return }
    withAnimation(AppMotion.easeOut(duration: 0.12)) {
      renderedFullURL = loadedURL
      fullLoaded = true
      loadFailed = false
    }
  }

  private func markFinishedAfterFailure() {
    withAnimation(AppMotion.easeOut(duration: 0.12)) {
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

}

struct MusicArtworkPlaceholder: View {
  var cornerRadius: CGFloat = 8

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        LinearGradient(
          colors: [
            .appPlaceholderSecondary,
            .appPlaceholderPrimary,
            .appPlaceholderQuaternary,
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        LinearGradient(
          colors: [
            Color.white.opacity(0.18),
            Color.clear,
            Color.black.opacity(0.08),
          ],
          startPoint: .top,
          endPoint: .bottomTrailing
        )
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
      reduceMotion ? nil : AppMotion.linear(duration: 0.82).repeatForever(autoreverses: false),
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
  @ObservedObject private var scrollState = ScrollPerformanceState.shared
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
        restartIfNeeded(active: effectiveActive)
      }
      .onChange(of: effectiveActive) { _, effectiveActive in
        restartIfNeeded(active: effectiveActive)
      }
  }

  private var effectiveActive: Bool {
    isActive
      && !scrollState.isScrolling
      && !AppMotion.reduceMotion(
        systemReduceMotion: systemReduceMotion,
        respectPreference: respectReducedMotion
      )
  }

  private func restartIfNeeded(active: Bool) {
    if active {
      phase = -0.8
      withAnimation(AppMotion.linear(duration: 1.65).repeatForever(autoreverses: false)) {
        phase = 1.8
      }
    } else {
      withAnimation(nil) {
        phase = -0.8
      }
    }
  }

  private func shimmer(width: CGFloat) -> some View {
    LinearGradient(
      colors: [
        .clear,
        Color.white.opacity(0.22),
        Color.white.opacity(0.10),
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

enum MusicSkeletonTone {
  case primary, secondary, tertiary, quaternary

  var color: Color {
    switch self {
    case .primary: return .appPlaceholderPrimary
    case .secondary: return .appPlaceholderSecondary
    case .tertiary: return .appPlaceholderTertiary
    case .quaternary: return .appPlaceholderQuaternary
    }
  }
}

struct MusicSkeletonBlock: View {
  var cornerRadius: CGFloat = 4
  var tone: MusicSkeletonTone = .primary
  var strokeOpacity: Double = 0.035

  var body: some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      .fill(tone.color)
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .stroke(Color.primary.opacity(strokeOpacity), lineWidth: 0.6)
      }
  }
}

struct MusicSkeletonLine: View {
  var width: CGFloat?
  var height: CGFloat = 13
  var tone: MusicSkeletonTone = .secondary

  var body: some View {
    MusicSkeletonBlock(cornerRadius: min(height / 2, 4), tone: tone, strokeOpacity: 0)
      .frame(width: width, height: height)
  }
}

struct MusicEmptyState: View {
  let title: String
  let message: String

  init(title: String, message: String) {
    self.title = title
    self.message = message
  }

  var body: some View {
    VStack(spacing: 15) {
      MusicEmptyStateMark()

      VStack(spacing: 6) {
        Text(title)
          .font(.system(size: 21, weight: .bold))
          .foregroundColor(.primary)
          .multilineTextAlignment(.center)
        Text(message)
          .font(.system(size: 15))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: 340)
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 24)
    .padding(.vertical, 10)
  }
}

struct MusicEmptyActionButton: View {
  let title: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.primary)
        .padding(.horizontal, AM.Spacing.xl)
        .padding(.vertical, 11)
        .background(Color.appSecondaryBackground, in: Capsule())
        .overlay {
          Capsule()
            .stroke(Color.appDivider, lineWidth: 0.7)
        }
    }
    .buttonStyle(PressableButtonStyle(scale: 0.94, dim: 0.78, haptic: .selection))
  }
}

struct MusicEmptyStateMark: View {
  var body: some View {
    ZStack(alignment: .bottomLeading) {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color.appPlaceholderSecondary)
        .frame(width: 116, height: 82)
        .overlay {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(Color.appDivider, lineWidth: 0.7)
        }

      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(Color.appPlaceholderPrimary)
        .frame(width: 56, height: 56)
        .offset(x: 10, y: -13)

      VStack(alignment: .leading, spacing: 6) {
        MusicSkeletonLine(width: 38, height: 7, tone: .tertiary)
        MusicSkeletonLine(width: 28, height: 6, tone: .primary)
      }
      .offset(x: 75, y: -27)
    }
    .frame(width: 132, height: 96)
    .accessibilityHidden(true)
  }
}

struct MusicCircularPlaceholder: View {
  var body: some View {
    GeometryReader { proxy in
      let side = min(proxy.size.width, proxy.size.height)
      ZStack {
        Circle()
          .fill(Color.appPlaceholderSecondary)
        Circle()
          .fill(Color.appPlaceholderPrimary)
          .frame(width: side * 0.48, height: side * 0.48)
          .offset(x: -side * 0.08, y: -side * 0.08)
        MusicSkeletonLine(width: side * 0.30, height: max(side * 0.08, 4), tone: .tertiary)
          .offset(x: side * 0.18, y: side * 0.20)
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
    .accessibilityHidden(true)
  }
}
