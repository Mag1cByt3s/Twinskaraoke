import Combine
import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

enum DisplayRefreshRate {
  /// Uses the active screen's advertised maximum so ProMotion devices can request
  /// higher-frequency redraws while older devices naturally remain at 60 Hz.
  static var maximumFramesPerSecond: Int {
    #if canImport(UIKit)
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

  static let appAccent = Color(red: 0.98, green: 0.12, blue: 0.22)
  #if canImport(UIKit)
    static let appBackground = adaptive(
      light: UIColor.systemBackground,
      dark: UIColor.black)
    static let appSecondaryBackground = adaptive(
      light: UIColor.secondarySystemBackground,
      dark: UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1))
    static let appGroupedBackground = adaptive(
      light: UIColor.systemGroupedBackground,
      dark: UIColor.black)
    static let appSheetGradientTop = adaptive(
      light: UIColor.systemBackground,
      dark: UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1))
    static let appSheetGradientBottom = adaptive(
      light: UIColor.secondarySystemBackground,
      dark: .black)
    static let appGlassFill = adaptive(
      light: UIColor.white.withAlphaComponent(0.78),
      dark: UIColor.white.withAlphaComponent(0.12))
    static let appGlassFillStrong = adaptive(
      light: UIColor.white.withAlphaComponent(0.95),
      dark: UIColor.white.withAlphaComponent(0.18))
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
      light: UIColor.separator.withAlphaComponent(0.42),
      dark: UIColor.white.withAlphaComponent(0.11))
    static let appShadow = adaptive(
      light: UIColor.black.withAlphaComponent(0.16),
      dark: UIColor.black.withAlphaComponent(0.36))
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
      light: UIColor(red: 0.86, green: 0.87, blue: 0.90, alpha: 1),
      dark: UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1))
    static let appPlaceholderSecondary = adaptive(
      light: UIColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1),
      dark: UIColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1))
    static let appPlaceholderTertiary = adaptive(
      light: UIColor(red: 0.78, green: 0.78, blue: 0.82, alpha: 1),
      dark: UIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1))
    static let appPlaceholderQuaternary = adaptive(
      light: UIColor(red: 0.72, green: 0.72, blue: 0.76, alpha: 1),
      dark: UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1))
    static let appToolbarPillBackground = adaptive(
      light: UIColor.black.withAlphaComponent(0.82),
      dark: UIColor.white.withAlphaComponent(0.12))
    static let appToolbarAvatarBackground = adaptive(
      light: UIColor.black.withAlphaComponent(0.72),
      dark: UIColor.white.withAlphaComponent(0.12))
  #endif
}

enum AM {
  enum Radius {
    static let thumb: CGFloat = 7
    static let card: CGFloat = 8
    static let hero: CGFloat = 10
    static let tile: CGFloat = 8
    static let popup: CGFloat = 6
    static let sheet: CGFloat = 16
  }

  enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 28
    static let screenMargin: CGFloat = 16
    static let shelfSpacing: CGFloat = 20
    static let shelfTile: CGFloat = 162
    static let compactShelfTile: CGFloat = 132
    static let tabBarContentInset: CGFloat = 32
    static let sidebarContentInset: CGFloat = 32
  }

  enum Layout {
    static let wideContentMaxWidth: CGFloat = 1180
    static let wideRailMaxWidth: CGFloat = 740
    static let wideInspectorWidth: CGFloat = 340

    static func usesWideCanvas(
      horizontalSizeClass: UserInterfaceSizeClass?,
      availableWidth: CGFloat? = nil
    ) -> Bool {
      guard horizontalSizeClass == .regular else { return false }
      #if canImport(UIKit)
        if UIDevice.current.userInterfaceIdiom == .mac {
          return true
        }
      #endif
      let width = availableWidth ?? currentScreenWidth
      return width >= 1050 && width > currentScreenHeight
    }

    private static var currentScreenWidth: CGFloat {
      #if canImport(UIKit)
        UIScreen.main.bounds.width
      #else
        1200
      #endif
    }

    private static var currentScreenHeight: CGFloat {
      #if canImport(UIKit)
        UIScreen.main.bounds.height
      #else
        800
      #endif
    }

    static func shelfTileWidth(for availableWidth: CGFloat, compact: Bool = false) -> CGFloat {
      let sidePadding = Spacing.screenMargin * 2
      let visibleItems: CGFloat
      if availableWidth >= 900 {
        visibleItems = compact ? 5.4 : 4.6
      } else if availableWidth >= 700 {
        visibleItems = compact ? 4.4 : 3.6
      } else if availableWidth <= 360 {
        visibleItems = compact ? 2.35 : 1.92
      } else {
        visibleItems = compact ? 2.85 : 2.22
      }
      let spacing = Spacing.l * max(visibleItems - 1, 0)
      let rawWidth = (availableWidth - sidePadding - spacing) / visibleItems
      let minimum = compact ? 118.0 : 148.0
      let maximum = compact ? 152.0 : 190.0
      return min(max(rawWidth, minimum), maximum)
    }

    static func playlistShelfTileWidth(for availableWidth: CGFloat) -> CGFloat {
      min(max(availableWidth * 0.42, 148), Spacing.shelfTile)
    }

    static func adaptiveGridColumns(
      minimum: CGFloat,
      spacing: CGFloat = Spacing.l
    ) -> [GridItem] {
      [
        GridItem(
          .adaptive(minimum: minimum, maximum: minimum + 72),
          spacing: spacing,
          alignment: .top
        )
      ]
    }

    static let playlistGridColumns = adaptiveGridColumns(minimum: 156)
    static let songGridColumns = adaptiveGridColumns(minimum: 154)
    static let categoryGridColumns = adaptiveGridColumns(minimum: 160, spacing: Spacing.m)

    static func mediaShelfHeight(tileWidth: CGFloat) -> CGFloat {
      tileWidth + 92
    }

    static func compactMediaShelfHeight(tileWidth: CGFloat) -> CGFloat {
      tileWidth + 78
    }

    static let mediaShelfHeight = mediaShelfHeight(tileWidth: 190)
    static let compactMediaShelfHeight = compactMediaShelfHeight(tileWidth: 152)
  }

  enum Font {
    static let sectionHeader = SwiftUI.Font.system(size: 23, weight: .bold)
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
    static let card = ShadowStyle(color: .appShadow, radius: 12, y: 5)
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
  func musicScreenBackground() -> some View {
    self.background(Color.appBackground.ignoresSafeArea())
  }
  func bottomChromeScrollTracking() -> some View {
    self.modifier(BottomChromeScrollTrackingModifier())
  }
  func tabBarScrollInset() -> some View {
    self.modifier(TabBarScrollInsetModifier())
  }
  func tabBarBottomPadding() -> some View {
    self.modifier(TabBarBottomPaddingModifier())
  }
}

@MainActor
final class BottomChromeState: ObservableObject {
  static let shared = BottomChromeState()

  @Published private(set) var isCollapsed = false

  private let collapseThreshold: CGFloat = 36
  private let expandThreshold: CGFloat = 4

  private init() {}

  func updateScrollOffset(_ offset: CGFloat) {
    if offset > collapseThreshold {
      setCollapsed(true)
    } else if offset <= expandThreshold {
      setCollapsed(false)
    }
  }

  func expand() {
    setCollapsed(false)
  }

  private func setCollapsed(_ collapsed: Bool) {
    guard isCollapsed != collapsed else { return }
    isCollapsed = collapsed
  }
}

private struct BottomChromeScrollTrackingModifier: ViewModifier {
  @ObservedObject private var chromeState = BottomChromeState.shared

  func body(content: Content) -> some View {
    if #available(iOS 18.0, *) {
      content
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
          max(0, geometry.contentOffset.y + geometry.contentInsets.top)
        } action: { _, offset in
          chromeState.updateScrollOffset(offset)
        }
    } else {
      content
    }
  }
}

private enum AdaptiveBottomChrome {
  static func inset(horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
    #if canImport(UIKit)
      if horizontalSizeClass == .regular {
        let idiom = UIDevice.current.userInterfaceIdiom
        if idiom == .pad || idiom == .mac {
          return AM.Spacing.sidebarContentInset
        }
      }
    #endif
    return AM.Spacing.tabBarContentInset
  }
}

private struct TabBarScrollInsetModifier: ViewModifier {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  func body(content: Content) -> some View {
    content.contentMargins(
      .bottom,
      AdaptiveBottomChrome.inset(horizontalSizeClass: horizontalSizeClass),
      for: .scrollContent
    )
  }
}

private struct TabBarBottomPaddingModifier: ViewModifier {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  func body(content: Content) -> some View {
    content.padding(
      .bottom,
      AdaptiveBottomChrome.inset(horizontalSizeClass: horizontalSizeClass)
    )
  }
}

struct AccountToolbarButton: View {
  @AppStorage("nk.username") private var username: String = ""
  @AppStorage("nk.avatar") private var avatar: String = ""

  var body: some View {
    NavigationLink {
      AccountView()
    } label: {
      avatarContent
        .frame(width: 30, height: 30)
        .clipShape(Circle())
      .frame(width: 36, height: 36)
      .contentShape(Circle())
    }
    .buttonStyle(PressableButtonStyle(scale: 0.92, dim: 0.78, haptic: .selection))
    .accessibilityIdentifier("AccountToolbarButton")
    .accessibilityLabel(accessibilityLabel)
    .accessibilityHint("Opens account and settings.")
  }

  @ViewBuilder
  private var avatarContent: some View {
    if let url = avatarURL {
      AsyncImage(url: url) { phase in
        switch phase {
        case .success(let image):
          image.resizable().scaledToFill()
        default:
          fallbackAvatar
        }
      }
    } else {
      fallbackAvatar
    }
  }

  @ViewBuilder
  private var fallbackAvatar: some View {
    ZStack {
      Circle().fill(Color.appPlaceholderSecondary)
      if let initial = displayInitial {
        Text(initial)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(.secondary)
      } else {
        MusicCircularPlaceholder()
      }
    }
  }

  private var displayName: String {
    username.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var displayInitial: String? {
    guard let first = displayName.first else { return nil }
    return String(first).uppercased()
  }

  private var avatarURL: URL? {
    let trimmed = avatar.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.lowercased() != "null" else { return nil }
    return URL(string: trimmed)
  }

  private var accessibilityLabel: String {
    displayName.isEmpty ? "Account" : "Account, \(displayName)"
  }
}

struct ToolbarIconButton: View {
  let systemImage: String
  let accessibilityLabel: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      ToolbarIconLabel(systemImage: systemImage)
    }
    .buttonStyle(PressableButtonStyle(scale: 0.92, dim: 0.78, haptic: .selection))
    .accessibilityLabel(accessibilityLabel)
  }
}

struct ToolbarCapsuleMenu<Content: View>: View {
  let accessibilityLabel: String
  @ViewBuilder let content: () -> Content

  var body: some View {
    Menu {
      content()
    } label: {
      ToolbarIconLabel(systemImage: "ellipsis")
    }
    .buttonStyle(PressableButtonStyle(scale: 0.92, dim: 0.78, haptic: .selection))
    .accessibilityLabel(accessibilityLabel)
  }
}

private struct ToolbarIconLabel: View {
  let systemImage: String
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    ZStack {
      ToolbarControlBackground()
      Image(systemName: systemImage)
        .font(.system(size: 16, weight: .semibold))
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
    }
    .frame(width: 36, height: 36)
    .contentShape(Circle())
  }
}

private struct ToolbarControlBackground: View {
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Circle()
      .fill(.regularMaterial)
      .overlay {
        Circle()
          .strokeBorder(borderColor, lineWidth: 0.7)
      }
      .shadow(color: shadowColor, radius: 5, x: 0, y: 2)
  }

  private var borderColor: Color {
    colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.08)
  }

  private var shadowColor: Color {
    colorScheme == .dark ? Color.black.opacity(0.35) : Color.black.opacity(0.10)
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
    HStack(alignment: .firstTextBaseline, spacing: AM.Spacing.s) {
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
    .padding(.top, 2)
    .contentShape(Rectangle())
  }
}
