import SwiftUI

struct EqualizerBars: View {
    let isAnimating: Bool
    @Environment(\.appReduceEffects) private var reduceEffects
    @Environment(\.scenePhase) private var scenePhase
    private let scrollState = ScrollPerformanceState.shared
    @State private var startDate = Date()
    @State private var isVisible: Bool = false

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: DisplayRefreshRate.decorativeAnimationInterval,
                paused: !shouldAnimateBars
            )
        ) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startDate))
            // Draw into a fixed surface so each tick does not relayout song rows.
            Canvas { context, size in
                let barWidth = size.width / 5
                for index in 0..<3 {
                    let height = barHeight(for: index, total: size.height, elapsed: elapsed)
                    let rect = CGRect(
                        x: barWidth / 2 + CGFloat(index) * barWidth * 1.5,
                        y: size.height - height,
                        width: barWidth,
                        height: height
                    )
                    context.fill(Capsule().path(in: rect), with: .color(.appAccent))
                }
            }
        }
        .accessibilityHidden(true)
        .onAppear {
            isVisible = true
            startDate = Date()
        }
        .onDisappear { isVisible = false }
        .onChange(of: isAnimating) { _, new in
            if new { startDate = Date() }
        }
    }

    private func barHeight(for index: Int, total: CGFloat, elapsed: TimeInterval) -> CGFloat {
        guard isAnimating && !reduceEffects else { return total * 0.3 }
        let speeds: [Double] = [3.4, 2.7, 4.1]
        let offsets: [Double] = [0.0, 0.45, 0.9]
        let v = (sin(elapsed * speeds[index] + offsets[index] * .pi * 2) + 1) / 2
        return total * (0.3 + 0.7 * v)
    }

    private var shouldAnimateBars: Bool {
        isAnimating && isVisible && !reduceEffects && scenePhase == .active && !scrollState.isScrolling
    }
}
