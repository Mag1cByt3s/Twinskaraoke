import Combine
import SwiftUI

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
