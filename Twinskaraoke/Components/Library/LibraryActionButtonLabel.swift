import SwiftUI

enum LibraryActionButtonLabelStyle { case primary, secondary, tertiary }

struct LibraryActionButtonLabel: View {
  let symbol: String
  let text: String
  var style: LibraryActionButtonLabelStyle = .secondary
  var cornerRadius: CGFloat = 10

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

    HStack(spacing: 6) {
      Image(systemName: symbol)
        .font(iconFont)
      Text(text).fontWeight(.semibold)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
    .foregroundStyle(foregroundColor)
    .background(backgroundColor, in: shape)
    .shadow(color: shadowColor, radius: 5, x: 0, y: 2)
    .contentShape(shape)
  }

  private var foregroundColor: Color {
    style == .primary ? .appControlActiveForeground : .appAccent
  }

  private var backgroundColor: Color {
    switch style {
    case .primary:
      return .appControlActiveFill
    case .secondary:
      return .appControlInactiveFill
    case .tertiary:
      return Color(.tertiarySystemFill)
    }
  }

  private var borderColor: Color {
    switch style {
    case .primary:
      return Color.white.opacity(0.16)
    case .secondary:
      return Color.appDivider
    case .tertiary:
      return Color.appDivider
    }
  }

  private var shadowColor: Color {
    switch style {
    case .primary:
      return Color.appShadow.opacity(0.42)
    case .secondary, .tertiary:
      return Color.appShadow.opacity(0.18)
    }
  }

  private var iconFont: Font? {
    style == .tertiary ? nil : .headline
  }
}
