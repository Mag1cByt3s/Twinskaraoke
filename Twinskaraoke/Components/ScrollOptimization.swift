import Combine
import SwiftUI

@MainActor
final class ScrollPerformanceState: ObservableObject {
  static let shared = ScrollPerformanceState()

  @Published private(set) var isScrolling = false

  private var activeScrollIDs = Set<UUID>()
  private var scrollEndTask: Task<Void, Never>?

  private init() {}

  /// Publish only scroll start/end transitions. Per-frame scroll offsets stay out of
  /// SwiftUI state so image placeholders and row chrome do not invalidate every frame.
  func update(id: UUID, isScrolling scrolling: Bool) {
    if scrolling {
      scrollEndTask?.cancel()
      scrollEndTask = nil
      activeScrollIDs.insert(id)
    } else {
      activeScrollIDs.remove(id)
    }
    scheduleScrollStateUpdate()
  }

  private func scheduleScrollStateUpdate() {
    scrollEndTask?.cancel()
    if !activeScrollIDs.isEmpty {
      setScrolling(true)
      return
    }
    scrollEndTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 140_000_000)
      guard !Task.isCancelled else { return }
      await MainActor.run {
        self?.setScrolling(false)
      }
    }
  }

  private func setScrolling(_ scrolling: Bool) {
    guard isScrolling != scrolling else { return }
    isScrolling = scrolling
  }
}

/// Smooth scrolling optimizations for SwiftUI ScrollView and List.
extension View {
  /// Apply scroll defaults that match native-feeling touch tracking and mark active
  /// scrolls so decorative work can pause during high-velocity gestures.
  func smoothScrolling() -> some View {
    modifier(SmoothScrollingModifier())
  }

}

private struct SmoothScrollingModifier: ViewModifier {
  @State private var scrollID = UUID()

  func body(content: Content) -> some View {
    let configured = content
      .scrollBounceBehavior(.basedOnSize)
      .scrollDismissesKeyboard(.interactively)

    if #available(iOS 18.0, *) {
      configured
        .onScrollPhaseChange { _, phase in
          ScrollPerformanceState.shared.update(id: scrollID, isScrolling: phase.isScrolling)
        }
        .onDisappear {
          ScrollPerformanceState.shared.update(id: scrollID, isScrolling: false)
        }
    } else {
      configured
    }
  }
}

/// Preference-based scroll tracking should publish coarse changes only; sub-point
/// jitter creates unnecessary SwiftUI invalidations while the finger is moving.
struct SmoothScrollOffsetPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    let next = nextValue()
    if abs(next - value) >= 1 {
      value = next
    }
  }
}

extension ScrollView {
  /// Track scroll offset for coarse UI chrome changes.
  func trackScrollOffset(_ offset: Binding<CGFloat>, coordinateSpace: String = "scroll") -> some View {
    self
      .coordinateSpace(name: coordinateSpace)
      .background(
        GeometryReader { proxy in
          Color.clear.preference(
            key: SmoothScrollOffsetPreferenceKey.self,
            value: proxy.frame(in: .named(coordinateSpace)).minY
          )
        }
      )
      .onPreferenceChange(SmoothScrollOffsetPreferenceKey.self) { value in
        offset.wrappedValue = value
      }
  }
}
