import SwiftUI

#if canImport(UIKit)
    import UIKit

    struct ClearPresentationBackground: UIViewRepresentable {
        func makeUIView(context _: Context) -> UIView {
            let view = UIView(frame: .zero)
            view.isUserInteractionEnabled = false
            clearPresentationBackground(from: view)
            return view
        }

        func updateUIView(_ uiView: UIView, context _: Context) {
            clearPresentationBackground(from: uiView)
        }

        private func clearPresentationBackground(from view: UIView) {
            DispatchQueue.main.async {
                var current: UIView? = view.superview
                while let candidate = current {
                    candidate.backgroundColor = .clear
                    current = candidate.superview
                }
            }
        }
    }
#else
    struct ClearPresentationBackground: View {
        var body: some View {
            Color.clear
        }
    }
#endif
