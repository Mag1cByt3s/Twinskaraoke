import Combine
import SwiftUI

@MainActor
final class ScrollPerformanceState: ObservableObject {
  static let shared = ScrollPerformanceState()

  @Published private(set) var isScrolling = false

  private var activeScrollIDs = Set<UUID>()
  private var scrollEndTask: Task<Void, Never>?

  private init() {}

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

extension View {

  func smoothScrolling(bounceBehavior: ScrollBounceBehavior = .basedOnSize) -> some View {
    modifier(SmoothScrollingModifier(bounceBehavior: bounceBehavior))
  }

}

private struct SmoothScrollingModifier: ViewModifier {
  let bounceBehavior: ScrollBounceBehavior
  @State private var scrollID = UUID()

  func body(content: Content) -> some View {
    let configured = content
      .scrollBounceBehavior(bounceBehavior)
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
