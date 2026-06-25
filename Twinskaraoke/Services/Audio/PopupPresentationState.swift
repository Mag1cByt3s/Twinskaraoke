import Combine
import SwiftUI

@MainActor
final class PopupPresentationState: ObservableObject {
    static let shared = PopupPresentationState()

    @Published private(set) var isExpanded = false

    private init() {}

    func setExpanded(_ isExpanded: Bool) {
        self.isExpanded = isExpanded
    }

    func collapse() {
        setExpanded(false)
    }
}
