import SwiftUI

enum LibraryActionButtonLabelStyle { case primary, secondary, tertiary }

struct LibraryActionButtonLabel: View {
  let symbol: String
  let text: String
  var style: LibraryActionButtonLabelStyle = .secondary
  var cornerRadius: CGFloat = 10

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: symbol)
        .font(iconFont)
      Text(text).fontWeight(.semibold)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
    .foregroundColor(foregroundColor)
    .background(backgroundColor)
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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

  private var iconFont: Font? {
    style == .tertiary ? nil : .system(size: 15, weight: .semibold)
  }
}
