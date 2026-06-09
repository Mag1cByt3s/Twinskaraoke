import LNPopupUI
import SwiftUI

struct ContentView: View {
  @StateObject var audioManager = AudioPlayerManager.shared

  var body: some View {
    PopupHostView()
      .environmentObject(audioManager)
  }
}

private struct PopupHostView: View {
  @EnvironmentObject var audioManager: AudioPlayerManager
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var selectedSection: RootSection? = .home
  @State private var showCaptcha = false
  var body: some View {
    rootShell
      .modifier(PopupModifier())
      .environmentObject(audioManager)
      .onAppear {
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
    if horizontalSizeClass == .regular {
      sidebarShell
    } else {
      rootTabs
    }
  }

  private var rootTabs: some View {
    TabView(selection: selectedTabBinding) {
      HomeView()
        .tabItem { Label(RootSection.home.title, systemImage: RootSection.home.selectedSystemImage) }
        .tag(RootSection.home)
      RadioView()
        .tabItem { Label(RootSection.radio.title, systemImage: RootSection.radio.systemImage) }
        .tag(RootSection.radio)
      LibraryView()
        .tabItem { Label(RootSection.library.title, systemImage: RootSection.library.systemImage) }
        .tag(RootSection.library)
      SearchView()
        .tabItem { Label(RootSection.search.title, systemImage: RootSection.search.systemImage) }
        .tag(RootSection.search)
      AccountView()
        .tabItem { Label(RootSection.account.title, systemImage: RootSection.account.systemImage) }
        .tag(RootSection.account)
    }
    .tint(.appAccent)
  }

  private var sidebarShell: some View {
    NavigationSplitView {
      List(selection: $selectedSection) {
        Section {
          ForEach(RootSection.allCases) { section in
            Label {
              Text(section.title)
            } icon: {
              Image(systemName: currentSection == section ? section.selectedSystemImage : section.systemImage)
            }
            .tag(Optional(section))
          }
        }
      }
      .listStyle(.sidebar)
      .navigationTitle("Twinskaraoke")
    } detail: {
      currentSection.content
        .id(currentSection)
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
      set: { selectedSection = $0 }
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
}

private enum RootSection: String, CaseIterable, Identifiable {
  case home
  case radio
  case library
  case search
  case account

  var id: String { rawValue }

  var title: String {
    switch self {
    case .home: return "Home"
    case .radio: return "Radio"
    case .library: return "Library"
    case .search: return "Search"
    case .account: return "Account"
    }
  }

  var systemImage: String {
    switch self {
    case .home: return "house"
    case .radio: return "dot.radiowaves.left.and.right"
    case .library: return "music.note.list"
    case .search: return "magnifyingglass"
    case .account: return "person"
    }
  }

  var selectedSystemImage: String {
    switch self {
    case .home: return "house.fill"
    case .radio: return "dot.radiowaves.left.and.right"
    case .library: return "music.note.list"
    case .search: return "magnifyingglass"
    case .account: return "person.fill"
    }
  }

  @ViewBuilder
  var content: some View {
    switch self {
    case .home:
      HomeView()
    case .radio:
      RadioView()
    case .library:
      LibraryView()
    case .search:
      SearchView()
    case .account:
      AccountView()
    }
  }
}

private struct PopupModifier: ViewModifier {
  @EnvironmentObject var audioManager: AudioPlayerManager
  func body(content: Content) -> some View {
    content
      .popup(
        isBarPresented: .constant(audioManager.currentSong != nil),
        isPopupOpen: $audioManager.showFullScreen
      ) {
        PopupContent()
          .environmentObject(audioManager)
      }
      .popupBarStyle(.floating)
      .popupBarProgressViewStyle(audioManager.isRadioMode ? .none : .bottom)
      .popupCloseButtonStyle(.none)
      .popupInteractionStyle(.drag)
      .popupBarMarqueeScrollEnabled(false)
  }
}

private struct PopupContent: View {
  @EnvironmentObject var audioManager: AudioPlayerManager
  var body: some View {
    FullScreenPlayerView()
      .environmentObject(audioManager)
      .modifier(
        PopupTitleModifier(
          title: audioManager.currentSong?.title ?? "",
          subtitle: audioManager.currentSong?.displayArtist ?? "")
      )
      .modifier(PopupImageModifier(artwork: audioManager.nowPlayingArtwork))
      .modifier(
        PopupProgressModifier(
          progress: audioManager.isRadioMode ? 0 : Float(min(max(audioManager.progress, 0), 1))
        )
      )
      .popupBarButtons({
        PopupBarTrailingItems(
          isPlaying: audioManager.isPlaying,
          isRadioMode: audioManager.isRadioMode,
          onTogglePlayPause: { [weak audioManager] in audioManager?.togglePlayPause() },
          onNext: { [weak audioManager] in audioManager?.playNextOrRandom() })
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
