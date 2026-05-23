import SDWebImageSwiftUI
import SwiftUI

enum ImageCacheConfig {
  private static var didApply = false
  static func applyLimits() {
    guard !didApply else { return }
    didApply = true
    let cfg = SDImageCache.shared.config
    cfg.maxMemoryCost = 24 * 1024 * 1024
    cfg.maxMemoryCount = 36
    cfg.maxDiskSize = 512 * 1024 * 1024
    cfg.shouldCacheImagesInMemory = true
    cfg.shouldUseWeakMemoryCache = true
    cfg.maxDiskAge = 90 * 24 * 60 * 60
    SDImageCache.shared.clearMemory()
    let dl = SDWebImageDownloader.shared
    dl.config.maxConcurrentDownloads = 4
    dl.requestModifier = SDWebImageDownloaderRequestModifier { request in
      var r = request
      r.cachePolicy = .returnCacheDataElseLoad
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
  static let defaultOptions: SDWebImageOptions = [.retryFailed, .scaleDownLargeImages]
}

struct LoadingImage: View {
  let url: URL?
  var cornerRadius: CGFloat = 8
  var contentMode: ContentMode = .fill
  var showsLoading: Bool = true
  var lowResURL: URL? = nil
  var transparentBackground: Bool = false
  @State private var fullLoaded: Bool = false
  var body: some View {
    GeometryReader { geo in
      let pixelSize = NSValue(cgSize: thumbnailPixelSize(for: geo.size))
      ZStack {
        if !transparentBackground {
          Color(.systemGray5)
        }
        if let lowResURL, !fullLoaded {
          WebImage(
            url: lowResURL,
            options: ImageCacheConfig.defaultOptions,
            context: [.imageThumbnailPixelSize: pixelSize]
          ) { image in
            image
              .resizable()
              .aspectRatio(contentMode: contentMode)
              .frame(width: geo.size.width, height: geo.size.height)
              .clipped()
          } placeholder: {
            Color.clear
          }
        }
        WebImage(
          url: url,
          options: ImageCacheConfig.defaultOptions,
          context: [.imageThumbnailPixelSize: pixelSize]
        ) { image in
          image
            .resizable()
            .aspectRatio(contentMode: contentMode)
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .transition(.opacity)
        } placeholder: {
          if showsLoading && lowResURL == nil {
            LoadingIndicator(size: min(geo.size.width, geo.size.height) * 0.5)
          } else {
            Color.clear
          }
        }
        .onSuccess { _, _, _ in
          DispatchQueue.main.async { fullLoaded = true }
        }
      }
      .frame(width: geo.size.width, height: geo.size.height)
    }
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
