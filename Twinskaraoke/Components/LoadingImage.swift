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
  static let defaultOptions: SDWebImageOptions = [
    .retryFailed,
    .scaleDownLargeImages,
    .continueInBackground,
    .highPriority
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
  @State private var fullLoaded: Bool = false
  var body: some View {
    GeometryReader { geo in
      let pixelSize = NSValue(cgSize: thumbnailPixelSize(for: geo.size))
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
              .frame(width: geo.size.width, height: geo.size.height)
              .clipped()
              .blur(radius: 2)
          } placeholder: {
            Color.clear
          }
        }
        WebImage(
          url: url,
          options: ImageCacheConfig.defaultOptions,
          context: context
        ) { image in
          image
            .resizable()
            .aspectRatio(contentMode: contentMode)
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        } placeholder: {
          if showsLoading && lowResURL == nil {
            LoadingIndicator(size: min(geo.size.width, geo.size.height) * 0.5)
          } else {
            Color.clear
          }
        }
        .onSuccess { _, _, _ in
          withAnimation(.easeOut(duration: 0.15)) {
            fullLoaded = true
          }
        }
        .transition(.opacity.animation(.easeOut(duration: 0.15)))
      }
      .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
      .drawingGroup(opaque: !transparentBackground)
    }
    .aspectRatio(1, contentMode: .fit)
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .onChange(of: url) { fullLoaded = false }
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
  var body: some View {
    ProgressView()
      .progressViewStyle(.circular)
      .tint(Color.appAccent)
      .frame(width: size, height: size)
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
