import SwiftUI

#if os(iOS)
  import UIKit
#endif

enum DisplayRefreshRate {

  static var maximumFramesPerSecond: Int {
    #if os(iOS)
      max(UIScreen.main.maximumFramesPerSecond, 60)
    #else
      60
    #endif
  }

  static var isHighRefreshDisplay: Bool {
    maximumFramesPerSecond > 60
  }

  static var lightweightAnimationInterval: TimeInterval {
    1.0 / Double(maximumFramesPerSecond)
  }
}

enum AppMotion {
  static func reduceMotion(systemReduceMotion: Bool, respectPreference: Bool) -> Bool {
    respectPreference && systemReduceMotion
  }

  static func duration(_ seconds: TimeInterval) -> TimeInterval {
    guard DisplayRefreshRate.isHighRefreshDisplay else { return seconds }
    return seconds * 0.92
  }

  static func easeInOut(duration seconds: TimeInterval) -> Animation {
    .easeInOut(duration: duration(seconds))
  }

  static func easeOut(duration seconds: TimeInterval) -> Animation {
    .easeOut(duration: duration(seconds))
  }

  static func linear(duration seconds: TimeInterval) -> Animation {
    .linear(duration: duration(seconds))
  }

  static func spring(response: TimeInterval, dampingFraction: Double) -> Animation {
    .spring(response: duration(response), dampingFraction: dampingFraction)
  }
}
