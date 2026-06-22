import SwiftUI

struct GlassXButton: View {
    var action: () -> Void
    var size: CGFloat = 44
    var iconSize: CGFloat = 16
    var accessibilityLabel = "Close"

    var body: some View {
        Button(action: action) {
            icon
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6))
        .buttonBorderShape(.circle)
    }

    private var icon: some View {
        Label(accessibilityLabel, systemImage: "xmark")
            .labelStyle(.iconOnly)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(Color.appGlassForeground)
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
            icon
                .frame(width: size, height: size)
                .modifier(GlassCircle())
                .contentShape(Circle())
        }
        .disabled(!isEnabled)
        .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6))
        .buttonBorderShape(.circle)
    }

    private var icon: some View {
        Label(accessibilityLabel, systemImage: "checkmark")
            .labelStyle(.iconOnly)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(isEnabled ? Color.appGlassForeground : Color.secondary)
    }
}
