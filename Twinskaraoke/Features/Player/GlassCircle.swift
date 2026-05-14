import SwiftUI

struct GlassCircle: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      content
        .glassEffect(in: Circle())
        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
    } else {
      content
        .background(
          Circle()
            .fill(Color.white.opacity(0.14))
        )
        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
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
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
    } else {
      content
        .background(
          shape.fill(Color.white.opacity(0.12))
        )
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
    }
  }
}
