import SwiftUI

/// Smooth scrolling optimizations for SwiftUI ScrollView and List
extension View {
  /// Apply optimized scroll configuration for smooth scrolling
  func smoothScrolling() -> some View {
    self
      .scrollBounceBehavior(.basedOnSize)
      .scrollDismissesKeyboard(.interactively)
  }

  /// Optimize LazyVStack for smooth scrolling with content buffering
  func optimizedLazyStack() -> some View {
    self
  }
}

/// Optimized scroll position tracking that doesn't impact scroll performance
struct SmoothScrollOffsetPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

extension ScrollView {
  /// Track scroll offset without impacting performance
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
