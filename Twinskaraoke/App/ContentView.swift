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
  @State private var showCaptcha = false
  var body: some View {
    rootTabs
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
  private var rootTabs: some View {
    TabView {
      HomeView()
        .tabItem { Label("Home", systemImage: "house.fill") }
      RadioView()
        .tabItem { Label("Radio", systemImage: "dot.radiowaves.left.and.right") }
      LibraryView()
        .tabItem { Label("Library", systemImage: "music.note.list") }
      SearchView()
        .tabItem { Label("Search", systemImage: "magnifyingglass") }
      AccountView()
        .tabItem { Label("Account", systemImage: "person") }
    }
    .tint(.appAccent)
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
        Image(systemName: playPauseSymbol)
          .font(.system(size: 24, weight: .regular))
          .foregroundColor(.primary)
          .frame(width: 32, height: 32)
          .contentShape(Rectangle())
      }
      if !isRadioMode {
        Button(action: onNext) {
          Image(systemName: "forward.fill")
            .font(.system(size: 22, weight: .regular))
            .foregroundColor(.primary)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
      }
    }
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
