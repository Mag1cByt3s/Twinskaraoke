import LNPopupUI
import Combine
import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

@MainActor
private final class PopupPlaybackState: ObservableObject {
  static let shared = PopupPlaybackState()

  @Published private(set) var hasCurrentSong = false
  @Published private(set) var title = ""
  @Published private(set) var subtitle = ""
  @Published private(set) var artwork: UIImage?
  @Published private(set) var progress: Float = 0
  @Published private(set) var isPlaying = false
  @Published private(set) var isRadioMode = false

  private var cancellables = Set<AnyCancellable>()

  private init(manager: AudioPlayerManager = .shared) {
    manager.$currentSong
      .map { song in
        PopupSongSnapshot(
          id: song?.id,
          title: song?.title ?? "",
          subtitle: song?.displayArtist ?? ""
        )
      }
      .removeDuplicates()
      .sink { [weak self] snapshot in
        self?.hasCurrentSong = snapshot.id != nil
        self?.title = snapshot.title
        self?.subtitle = snapshot.subtitle
      }
      .store(in: &cancellables)

    manager.$nowPlayingArtwork
      .removeDuplicates(by: { $0 === $1 })
      .sink { [weak self] in self?.artwork = $0 }
      .store(in: &cancellables)

    manager.$progress
      .throttle(for: .milliseconds(350), scheduler: RunLoop.main, latest: true)
      .map { Float(min(max($0, 0), 1)) }
      .removeDuplicates()
      .sink { [weak self] in self?.progress = $0 }
      .store(in: &cancellables)

    manager.$isPlaying
      .removeDuplicates()
      .sink { [weak self] in self?.isPlaying = $0 }
      .store(in: &cancellables)

    manager.$isRadioMode
      .removeDuplicates()
      .sink { [weak self] isRadioMode in
        self?.isRadioMode = isRadioMode
        if isRadioMode {
          self?.progress = 0
        }
      }
      .store(in: &cancellables)
  }
}

private struct PopupSongSnapshot: Equatable {
  let id: String?
  let title: String
  let subtitle: String
}

#if canImport(UIKit)
  @MainActor
  private final class PopupOpenIntentGate: NSObject, UIGestureRecognizerDelegate {
    static let shared = PopupOpenIntentGate()

    private static let touchRecognizerName = "Twinskaraoke.IntentionalMiniPlayerOpen"
    private var openIntentExpiresAt = Date.distantPast

    func consumeIntent() -> Bool {
      guard Date() <= openIntentExpiresAt else { return false }
      openIntentExpiresAt = .distantPast
      return true
    }

    func installTouchRecognizer(on popupBar: LNPopupBar) {
      let alreadyInstalled = popupBar.gestureRecognizers?.contains {
        $0.name == Self.touchRecognizerName
      } ?? false
      guard !alreadyInstalled else { return }

      let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(markIntentionalMiniPlayerTouch(_:)))
      recognizer.name = Self.touchRecognizerName
      recognizer.minimumPressDuration = 0
      recognizer.cancelsTouchesInView = false
      recognizer.delegate = self
      popupBar.addGestureRecognizer(recognizer)
    }

    @objc private func markIntentionalMiniPlayerTouch(_ recognizer: UILongPressGestureRecognizer) {
      guard recognizer.state == .began else { return }
      openIntentExpiresAt = Date().addingTimeInterval(0.35)
    }

    nonisolated func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      true
    }
  }
#endif

struct ContentView: View {
  var body: some View {
    PopupHostView()
      .environmentObject(AudioPlayerManager.shared)
  }
}

private struct PopupHostView: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var selectedSection: RootSection? = .home
  @State private var showCaptcha = false
  var body: some View {
    rootShell
      .modifier(PopupModifier())
      .onAppear {
        configureTabBarAppearance()
        applyUITestInitialSectionIfNeeded()
        if DeveloperMode.shouldTriggerEasterEgg() {
          showCaptcha = true
        }
      }
      .fullScreenCover(isPresented: $showCaptcha) {
        CaptchaWebView(
          url: URL(string: "https://twinskaraoke.evilneur.org")!,
          onClose: { showCaptcha = false }
        )
        .ignoresSafeArea()
      }
  }

  @ViewBuilder
  private var rootShell: some View {
    if usesSidebarShell {
      sidebarShell
    } else {
      rootTabs
    }
  }

  private var usesSidebarShell: Bool {
    guard AM.Layout.usesWideCanvas(horizontalSizeClass: horizontalSizeClass) else { return false }
    #if canImport(UIKit)
      let idiom = UIDevice.current.userInterfaceIdiom
      return idiom == .pad || idiom == .mac
    #else
      return true
    #endif
  }

  private var rootTabs: some View {
    TabView(selection: selectedTabBinding) {
      HomeView()
        .tabItem { Label(RootSection.home.title, systemImage: RootSection.home.selectedSystemImage) }
        .tag(RootSection.home)
      NewView()
        .tabItem { Label(RootSection.new.title, systemImage: RootSection.new.selectedSystemImage) }
        .tag(RootSection.new)
      RadioView()
        .tabItem { Label(RootSection.radio.title, systemImage: RootSection.radio.selectedSystemImage) }
        .tag(RootSection.radio)
      LibraryView()
        .tabItem { Label(RootSection.library.title, systemImage: RootSection.library.selectedSystemImage) }
        .tag(RootSection.library)
      SearchView()
        .tabItem { Label(RootSection.search.title, systemImage: RootSection.search.selectedSystemImage) }
        .tag(RootSection.search)
    }
    .tint(.appAccent)
  }

  private var sidebarShell: some View {
    NavigationSplitView {
      List(selection: $selectedSection) {
        ForEach(RootSectionGroup.allCases) { group in
          Section(group.title) {
            ForEach(group.sections) { section in
              SidebarSectionRow(section: section, isSelected: currentSection == section)
                .tag(Optional(section))
                .accessibilityIdentifier(section.sidebarAccessibilityIdentifier)
            }
          }
        }
      }
      .listStyle(.sidebar)
      .navigationTitle("Twinskaraoke")
      .safeAreaInset(edge: .bottom, spacing: 0) {
        SidebarNowPlayingHint()
      }
    } detail: {
      currentSection.content
        .id(currentSection)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(shellTransition)
    }
    .navigationSplitViewStyle(.balanced)
    .tint(.appAccent)
    .animation(shellAnimation, value: currentSection)
    .onChange(of: selectedSection) { _, newValue in
      if newValue == nil {
        selectedSection = .home
      } else {
        AppHaptic.selection.play()
      }
    }
  }

  private var selectedTabBinding: Binding<RootSection> {
    Binding(
      get: { currentSection },
      set: { newSection in
        if selectedSection != newSection {
          AppHaptic.selection.play()
        }
        selectedSection = newSection
      }
    )
  }

  private var currentSection: RootSection {
    selectedSection ?? .home
  }

  private var shellAnimation: Animation? {
    reduceMotion ? nil : .easeInOut(duration: 0.24)
  }

  private var shellTransition: AnyTransition {
    reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing))
  }

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  private func configureTabBarAppearance() {
    #if canImport(UIKit)
      let appearance = UITabBarAppearance()
      appearance.configureWithTransparentBackground()
      appearance.backgroundEffect = nil
      appearance.backgroundColor = .clear
      appearance.shadowColor = .clear
      UITabBar.appearance().isTranslucent = true
      UITabBar.appearance().standardAppearance = appearance
      UITabBar.appearance().scrollEdgeAppearance = appearance
    #endif
  }

  private func applyUITestInitialSectionIfNeeded() {
    let arguments = ProcessInfo.processInfo.arguments
    guard let flagIndex = arguments.firstIndex(of: "-UITestInitialSection"),
      arguments.indices.contains(flagIndex + 1),
      let section = RootSection(rawValue: arguments[flagIndex + 1].lowercased())
    else {
      return
    }
    selectedSection = section
  }
}

private enum RootSection: String, CaseIterable, Identifiable {
  case home
  case new
  case radio
  case library
  case search

  var id: String { rawValue }

  var sidebarAccessibilityIdentifier: String {
    "RootSection.\(rawValue)"
  }

  var title: String {
    switch self {
    case .home: return "Home"
    case .new: return "New"
    case .radio: return "Radio"
    case .library: return "Library"
    case .search: return "Search"
    }
  }

  var systemImage: String {
    switch self {
    case .home: return "house"
    case .new: return "square.grid.2x2"
    case .radio: return "dot.radiowaves.left.and.right"
    case .library: return "music.note.list"
    case .search: return "magnifyingglass"
    }
  }

  var selectedSystemImage: String {
    switch self {
    case .home: return "house.fill"
    case .new: return "square.grid.2x2.fill"
    case .radio: return "dot.radiowaves.left.and.right"
    case .library: return "music.note.list"
    case .search: return "magnifyingglass"
    }
  }

  @ViewBuilder
  var content: some View {
    switch self {
    case .home:
      HomeView()
    case .new:
      NewView()
    case .radio:
      RadioView()
    case .library:
      LibraryView()
    case .search:
      SearchView()
    }
  }
}

private enum RootSectionGroup: String, CaseIterable, Identifiable {
  case discover
  case collection

  var id: String { rawValue }

  var title: String {
    switch self {
    case .discover: return "Discover"
    case .collection: return "Collection"
    }
  }

  var sections: [RootSection] {
    switch self {
    case .discover: return [.home, .new, .radio, .search]
    case .collection: return [.library]
    }
  }
}

private struct SidebarSectionRow: View {
  let section: RootSection
  let isSelected: Bool

  var body: some View {
    Label {
      Text(section.title)
        .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
    } icon: {
      ZStack {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(section.sidebarTint.opacity(isSelected ? 1 : 0.14))
        Image(systemName: isSelected ? section.selectedSystemImage : section.systemImage)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(isSelected ? Color.white : section.sidebarTint)
      }
      .frame(width: 25, height: 25)
      .accessibilityHidden(true)
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(section.title)
  }
}

private struct SidebarNowPlayingHint: View {
  @ObservedObject private var popupState = PopupPlaybackState.shared

  var body: some View {
    Group {
      if popupState.hasCurrentSong {
        HStack(spacing: 10) {
          artwork
          VStack(alignment: .leading, spacing: 2) {
            Text("Now Playing")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(.secondary)
              .textCase(.uppercase)
            Text(popupState.title)
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(.primary)
              .lineLimit(1)
            if !popupState.subtitle.isEmpty {
              Text(popupState.subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
          Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) {
          Rectangle()
            .fill(Color.appDivider)
            .frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Now Playing")
        .accessibilityValue(popupState.subtitle.isEmpty ? popupState.title : "\(popupState.title), \(popupState.subtitle)")
      }
    }
  }

  @ViewBuilder
  private var artwork: some View {
    if let artwork = popupState.artwork {
      Image(uiImage: artwork)
        .resizable()
        .scaledToFill()
        .frame(width: 38, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: AM.Radius.thumb, style: .continuous))
    } else {
      MusicArtworkPlaceholder(cornerRadius: AM.Radius.thumb)
        .frame(width: 38, height: 38)
    }
  }
}

private extension RootSection {
  var sidebarTint: Color {
    switch self {
    case .home:
      return .appAccent
    case .new:
      return Color(red: 0.63, green: 0.34, blue: 0.98)
    case .radio:
      return Color(red: 0.98, green: 0.42, blue: 0.18)
    case .library:
      return Color(red: 0.18, green: 0.58, blue: 0.98)
    case .search:
      return Color(red: 0.23, green: 0.68, blue: 0.48)
    }
  }
}

private struct PopupModifier: ViewModifier {
  @ObservedObject private var popupState = PopupPlaybackState.shared

  func body(content: Content) -> some View {
    content
      .popup(
        isBarPresented: .constant(popupState.hasCurrentSong),
        isPopupOpen: Binding(
          get: { AudioPlayerManager.shared.showFullScreen },
          set: { isOpen in
            if isOpen {
              #if canImport(UIKit)
                let isIntentionalOpen =
                  AudioPlayerManager.shared.showFullScreen || PopupOpenIntentGate.shared.consumeIntent()
                guard isIntentionalOpen else { return }
              #endif
            }
            AudioPlayerManager.shared.showFullScreen = isOpen
          }
        )
      ) {
        PopupContent(popupState: popupState)
      }
      .popupBarStyle(.floating)
      .popupBarProgressViewStyle(popupState.isRadioMode ? .none : .bottom)
      .popupCloseButtonStyle(.none)
      .popupInteractionStyle(.drag)
      .popupBarMarqueeScrollEnabled(false)
      .popupBarCustomizer { popupBar in
        popupBar.accessibilityIdentifier = "MiniPlayerBar"
        popupBar.accessibilityLabel = "Now Playing"
        popupBar.accessibilityHint = "Opens the full-screen player."
        // LNPopupUI's drag recognizer can report an open during unrelated root
        // navigation and system gestures. This touch marker lets the binding accept
        // deliberate mini-player opens while LNPopupUI still owns the transition.
        PopupOpenIntentGate.shared.installTouchRecognizer(on: popupBar)
      }
  }
}

private struct PopupContent: View {
  @ObservedObject private var popupState: PopupPlaybackState

  init(popupState: PopupPlaybackState) {
    self.popupState = popupState
  }

  var body: some View {
    FullScreenPlayerView()
      .environmentObject(AudioPlayerManager.shared)
      .modifier(
        PopupTitleModifier(
          title: popupState.title,
          subtitle: popupState.subtitle)
      )
      .modifier(PopupImageModifier(artwork: popupState.artwork))
      .modifier(
        PopupProgressModifier(
          progress: popupState.isRadioMode ? 0 : popupState.progress
        )
      )
      .popupBarButtons({
        PopupBarTrailingItems(
          isPlaying: popupState.isPlaying,
          isRadioMode: popupState.isRadioMode,
          onTogglePlayPause: { AudioPlayerManager.shared.togglePlayPause() },
          onNext: { AudioPlayerManager.shared.playNextOrRandom() })
      })
  }
}

private struct PopupTitleModifier: ViewModifier, Equatable {
  let title: String
  let subtitle: String
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.title == rhs.title && lhs.subtitle == rhs.subtitle
  }
  func body(content: Content) -> some View {
    content.popupTitle(title, subtitle: subtitle)
  }
}

private struct PopupImageModifier: ViewModifier, Equatable {
  let artwork: UIImage?
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.artwork === rhs.artwork
  }
  func body(content: Content) -> some View {
    if let artwork {
      content.popupImage(Image(uiImage: artwork))
    } else {
      content.popupImage(Image(systemName: "music.note"))
    }
  }
}

private struct PopupProgressModifier: ViewModifier, Equatable {
  let progress: Float

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.progress == rhs.progress
  }

  func body(content: Content) -> some View {
    content.popupProgress(progress)
  }
}

private struct PopupBarTrailingItems: View, Equatable {
  let isPlaying: Bool
  let isRadioMode: Bool
  let onTogglePlayPause: () -> Void
  let onNext: () -> Void

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.isPlaying == rhs.isPlaying && lhs.isRadioMode == rhs.isRadioMode
  }

  var body: some View {
    HStack(spacing: 16) {
      Button(action: onTogglePlayPause) {
        Group {
          if #available(iOS 17.0, *) {
            Image(systemName: playPauseSymbol)
              .contentTransition(.symbolEffect(.replace))
          } else {
            Image(systemName: playPauseSymbol)
              .contentTransition(.opacity)
          }
        }
        .font(.system(size: 23, weight: .semibold))
        .foregroundColor(.primary)
        .frame(width: 34, height: 34)
        .contentShape(Rectangle())
      }
      .buttonStyle(PressableButtonStyle(scale: 0.86, dim: 0.65, haptic: .medium))
      .accessibilityLabel(playPauseAccessibilityLabel)
      .accessibilityHint(
        isRadioMode ? "Controls the live radio stream." : "Controls the current song."
      )
      if !isRadioMode {
        Button(action: onNext) {
          Image(systemName: "forward.fill")
            .font(.system(size: 21, weight: .semibold))
            .foregroundColor(.primary)
            .frame(width: 34, height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.86, dim: 0.65, haptic: .light))
        .accessibilityLabel("Next track")
        .accessibilityHint("Skips to the next song.")
      }
    }
  }

  private var playPauseAccessibilityLabel: String {
    if isRadioMode {
      return isPlaying ? "Stop live radio" : "Play live radio"
    }
    return isPlaying ? "Pause" : "Play"
  }

  private var playPauseSymbol: String {
    if isRadioMode {
      return isPlaying ? "stop.fill" : "play.fill"
    }
    return isPlaying ? "pause.fill" : "play.fill"
  }
}

#Preview {
  ContentView()
}
