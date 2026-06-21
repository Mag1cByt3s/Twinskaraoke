import SwiftUI

struct GlassXButton: View {
  var action: () -> Void
  var size: CGFloat = 44
  var iconSize: CGFloat = 16
  var accessibilityLabel = "Close"

  var body: some View {
    Button(action: action) {
      Label(accessibilityLabel, systemImage: "xmark")
        .labelStyle(.iconOnly)
        .font(.headline)
        .foregroundStyle(Color.appGlassForeground)
        .frame(width: size, height: size)
        .contentShape(Circle())
    }
    .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6))
  }
}

struct GlassCheckmarkButton: View {
  var action: () -> Void
  var size: CGFloat = 44
  var iconSize: CGFloat = 16
  var isEnabled: Bool = true
  var accessibilityLabel = "Done"

  var body: some View {
    Button(action: action) {
      Label(accessibilityLabel, systemImage: "checkmark")
        .labelStyle(.iconOnly)
        .font(.headline)
        .foregroundStyle(isEnabled ? Color.appGlassForeground : Color.secondary)
        .frame(width: size, height: size)
        .contentShape(Circle())
    }
    .disabled(!isEnabled)
    .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6))
  }
}
