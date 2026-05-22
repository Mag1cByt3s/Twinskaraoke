import SwiftUI

enum AppearanceMode: String, CaseIterable {
  case system, light, dark
  var label: String {
    switch self {
    case .system: return "System"
    case .light: return "Light"
    case .dark: return "Dark"
    }
  }
  var colorScheme: ColorScheme? {
    switch self {
    case .system: return nil
    case .light: return .light
    case .dark: return .dark
    }
  }
}

extension Color {
  #if canImport(UIKit)
    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
      Color(
        uiColor: UIColor { trait in
          trait.userInterfaceStyle == .dark ? dark : light
        })
    }
  #endif

  static let appAccent = Color(red: 0.98, green: 0.176, blue: 0.282)
  #if canImport(UIKit)
    static let appSheetGradientTop = adaptive(
      light: UIColor(red: 0.97, green: 0.98, blue: 1.0, alpha: 1),
      dark: UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1))
    static let appSheetGradientBottom = adaptive(
      light: UIColor(red: 0.90, green: 0.93, blue: 0.98, alpha: 1),
      dark: .black)
    static let appGlassFill = adaptive(
      light: UIColor.white.withAlphaComponent(0.72),
      dark: UIColor.white.withAlphaComponent(0.14))
    static let appGlassFillStrong = adaptive(
      light: UIColor.white.withAlphaComponent(0.92),
      dark: UIColor.white.withAlphaComponent(0.96))
    static let appGlassForeground = adaptive(
      light: UIColor.label.withAlphaComponent(0.85),
      dark: UIColor.white.withAlphaComponent(0.85))
    static let appControlActiveFill = adaptive(
      light: UIColor.label,
      dark: .white)
    static let appControlActiveForeground = adaptive(
      light: .white,
      dark: .black)
    static let appControlInactiveFill = adaptive(
      light: UIColor.black.withAlphaComponent(0.08),
      dark: UIColor.white.withAlphaComponent(0.16))
    static let appArtworkOverlay = adaptive(
      light: UIColor.white.withAlphaComponent(0.45),
      dark: UIColor.black.withAlphaComponent(0.40))
    static let appDivider = adaptive(
      light: UIColor.black.withAlphaComponent(0.10),
      dark: UIColor.white.withAlphaComponent(0.12))
    static let appShadow = adaptive(
      light: UIColor.black.withAlphaComponent(0.12),
      dark: UIColor.black.withAlphaComponent(0.18))
    static let appHeroShadowIdle = adaptive(
      light: UIColor.black.withAlphaComponent(0.14),
      dark: UIColor.black.withAlphaComponent(0.22))
    static let appHeroShadowPlaying = adaptive(
      light: UIColor.black.withAlphaComponent(0.20),
      dark: UIColor.black.withAlphaComponent(0.45))
    static let appAmbientWash = adaptive(
      light: UIColor.white.withAlphaComponent(0.24),
      dark: UIColor.black.withAlphaComponent(0.28))
    static let appAmbientVignetteTop = adaptive(
      light: UIColor.white.withAlphaComponent(0.34),
      dark: UIColor.black.withAlphaComponent(0.52))
    static let appAmbientVignetteMid = adaptive(
      light: UIColor.white.withAlphaComponent(0.10),
      dark: UIColor.black.withAlphaComponent(0.18))
    static let appAmbientVignetteBottom = adaptive(
      light: UIColor.white.withAlphaComponent(0.40),
      dark: UIColor.black.withAlphaComponent(0.58))
    static let appAmbientRadial = adaptive(
      light: UIColor.white.withAlphaComponent(0.08),
      dark: UIColor.black.withAlphaComponent(0.14))
    static let appFavoritesTileBackground = adaptive(
      light: UIColor(red: 0.98, green: 0.98, blue: 1.0, alpha: 1),
      dark: UIColor.secondarySystemBackground)
    static let appPlaceholderPrimary = adaptive(
      light: UIColor(red: 0.78, green: 0.84, blue: 0.96, alpha: 1),
      dark: UIColor(red: 0.14, green: 0.16, blue: 0.22, alpha: 1))
    static let appPlaceholderSecondary = adaptive(
      light: UIColor(red: 0.86, green: 0.89, blue: 0.98, alpha: 1),
      dark: UIColor(red: 0.10, green: 0.12, blue: 0.18, alpha: 1))
    static let appPlaceholderTertiary = adaptive(
      light: UIColor(red: 0.92, green: 0.80, blue: 0.90, alpha: 1),
      dark: UIColor(red: 0.18, green: 0.10, blue: 0.20, alpha: 1))
    static let appPlaceholderQuaternary = adaptive(
      light: UIColor(red: 0.84, green: 0.88, blue: 0.96, alpha: 1),
      dark: UIColor(red: 0.08, green: 0.08, blue: 0.14, alpha: 1))
  #endif
}

enum AM {
  enum Radius {
    static let thumb: CGFloat = 6
    static let card: CGFloat = 6
    static let hero: CGFloat = 8
    static let tile: CGFloat = 8
    static let popup: CGFloat = 6
    static let sheet: CGFloat = 14
  }

  enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 28
    static let screenMargin: CGFloat = 16
    static let shelfSpacing: CGFloat = 28
    static let shelfTile: CGFloat = 170
  }

  enum Font {
    static let sectionHeader = SwiftUI.Font.system(size: 22, weight: .bold)
    static let groupHeader = SwiftUI.Font.system(size: 17, weight: .bold)
    static let tileTitle = SwiftUI.Font.system(size: 15, weight: .semibold)
    static let tileCaption = SwiftUI.Font.system(size: 13)
    static let rowTitle = SwiftUI.Font.system(size: 16, weight: .regular)
    static let rowSubtitle = SwiftUI.Font.system(size: 13)
    static let nowPlayingTitle = SwiftUI.Font.system(size: 22, weight: .bold)
    static let nowPlayingArtist = SwiftUI.Font.system(size: 17)
    static let timecode = SwiftUI.Font.system(size: 12, weight: .medium, design: .monospaced)
    static let chevron = SwiftUI.Font.system(size: 14, weight: .bold)
  }

  enum Shadow {
    static let card = ShadowStyle(color: .appShadow, radius: 10, y: 4)
    static let heroIdle = ShadowStyle(color: .appHeroShadowIdle, radius: 16, y: 10)
    static let heroPlaying = ShadowStyle(color: .appHeroShadowPlaying, radius: 28, y: 18)
  }

  struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let y: CGFloat
  }
}

extension View {
  func amShadow(_ style: AM.ShadowStyle) -> some View {
    self.shadow(color: style.color, radius: style.radius, y: style.y)
  }
}

struct AMSectionHeader<Destination: View>: View {
  let title: String
  let destination: Destination?
  init(_ title: String, destination: Destination) {
    self.title = title
    self.destination = destination
  }
  init(_ title: String) where Destination == EmptyView {
    self.title = title
    self.destination = nil
  }
  var body: some View {
    Group {
      if let destination {
        NavigationLink(destination: destination) {
          headerRow(showChevron: true)
        }
        .buttonStyle(.plain)
      } else {
        headerRow(showChevron: false)
      }
    }
    .padding(.horizontal, AM.Spacing.screenMargin)
  }
  private func headerRow(showChevron: Bool) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: AM.Spacing.xs) {
      Text(title)
        .font(AM.Font.sectionHeader)
        .foregroundColor(.primary)
      if showChevron {
        Image(systemName: "chevron.right")
          .font(.system(size: 17, weight: .bold))
          .foregroundColor(.secondary.opacity(0.7))
      }
      Spacer()
    }
    .contentShape(Rectangle())
  }
}
