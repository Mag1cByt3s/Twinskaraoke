import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

enum AppHaptic {
  case light
  case medium
  case selection
  case success
  case warning
  case error

  func play() {
    #if canImport(UIKit)
      switch self {
      case .light:
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
      case .medium:
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
      case .selection:
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
      case .success:
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
      case .warning:
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
      case .error:
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.error)
      }
    #endif
  }
}

enum AppMotion {
  static func reduceMotion(systemReduceMotion: Bool, respectPreference: Bool) -> Bool {
    respectPreference && systemReduceMotion
  }
}

struct PressableButtonStyle: ButtonStyle {
  var scale: CGFloat = 0.97
  var dim: Double = 0.7
  var haptic: AppHaptic? = nil

  func makeBody(configuration: Configuration) -> some View {
    PressableButtonBody(
      configuration: configuration,
      scale: scale,
      dim: dim,
      haptic: haptic
    )
  }
}

private struct PressableButtonBody: View {
  let configuration: ButtonStyle.Configuration
  let scale: CGFloat
  let dim: Double
  let haptic: AppHaptic?
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var wasPressed = false

  var body: some View {
    configuration.label
      .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? scale : 1.0))
      .opacity(configuration.isPressed ? dim : 1.0)
      .animation(
        reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.7),
        value: configuration.isPressed)
      .onChange(of: configuration.isPressed) { _, isPressed in
        if isPressed && !wasPressed {
          haptic?.play()
        }
        wasPressed = isPressed
      }
  }

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }
}
