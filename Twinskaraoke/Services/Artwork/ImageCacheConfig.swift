import Foundation
import SDWebImage
#if canImport(UIKit)
    import UIKit
#endif

enum ImageCacheConfig {
    private static var didApply = false

    static func applyLimits() {
        guard !didApply else { return }
        didApply = true
        let cfg = SDImageCache.shared.config
        cfg.maxMemoryCost = 32 * 1024 * 1024
        cfg.maxMemoryCount = 64
        cfg.maxDiskSize = 128 * 1024 * 1024
        cfg.shouldCacheImagesInMemory = true
        cfg.shouldUseWeakMemoryCache = true
        cfg.maxDiskAge = 30 * 24 * 60 * 60
        SDImageCache.shared.clearMemory()
        let dl = SDWebImageDownloader.shared

        dl.config.maxConcurrentDownloads = 2
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
        .scaleDownLargeImages,
    ]
}
