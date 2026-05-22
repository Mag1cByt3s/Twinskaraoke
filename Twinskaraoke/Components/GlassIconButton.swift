import SwiftUI

struct GlassXButton: View {
  var action: () -> Void
  var size: CGFloat = 36
  var iconSize: CGFloat = 16

  var body: some View {
    Button(action: action) {
      Image(systemName: "xmark")
        .font(.system(size: iconSize, weight: .semibold))
        .foregroundColor(.appGlassForeground)
        .frame(width: size, height: size)
    }
    .modifier(GlassCircle())
    .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6))
  }
}

struct GlassCheckmarkButton: View {
  var action: () -> Void
  var size: CGFloat = 36
  var iconSize: CGFloat = 16
  var isEnabled: Bool = true

  var body: some View {
    Button(action: action) {
      Image(systemName: "checkmark")
        .font(.system(size: iconSize, weight: .semibold))
        .foregroundColor(isEnabled ? .appGlassForeground : .secondary.opacity(0.5))
        .frame(width: size, height: size)
    }
    .disabled(!isEnabled)
    .modifier(GlassCircle())
    .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6))
  }
}
