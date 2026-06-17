import SwiftUI

/// Smooth scrolling optimizations for SwiftUI ScrollView and List
extension View {
  /// Apply optimized scroll configuration for smooth scrolling
  func smoothScrolling() -> some View {
    self
      .scrollBounceBehavior(.basedOnSize)
      .scrollDismissesKeyboard(.interactively)
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
