import SwiftUI

struct GlassCircle: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      content
        .glassEffect(.regular.interactive(), in: Circle())
        .contentShape(Circle())
    } else {
      content
        .background(
          Circle()
            .fill(Color.appGlassFill)
        )
        .overlay(
          Circle()
            .stroke(Color.appDivider.opacity(0.7), lineWidth: 0.5)
        )
        .clipShape(Circle())
        .contentShape(Circle())
    }
  }
}

struct GlassRoundedRect: ViewModifier {
  let cornerRadius: CGFloat

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    if #available(iOS 26.0, *) {
      content
        .glassEffect(in: shape)
        .shadow(color: .appShadow, radius: 14, y: 6)
    } else {
      content
        .background(
          shape.fill(Color.appGlassFill)
        )
        .shadow(color: .appShadow, radius: 14, y: 6)
    }
  }
}
