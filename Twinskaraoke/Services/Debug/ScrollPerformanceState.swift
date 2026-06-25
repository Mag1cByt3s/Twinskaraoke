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
