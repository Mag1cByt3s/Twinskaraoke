#if canImport(UIKit)
    import MediaPlayer
    import SwiftUI

    struct SystemVolumeBridge: UIViewRepresentable {
        @Binding var volume: Double
        @Binding var isUserScrubbing: Bool
        func makeUIView(context _: Context) -> MPVolumeView {
            let view = MPVolumeView(frame: .zero)
            view.alpha = 0.0001
            return view
        }

        func updateUIView(_ uiView: MPVolumeView, context _: Context) {
            guard isUserScrubbing else { return }
            DispatchQueue.main.async {
                guard let slider = uiView.subviews.compactMap({ $0 as? UISlider }).first else { return }
                let target = Float(max(0, min(1, volume)))
                if abs(slider.value - target) > 0.005 {
                    slider.setValue(target, animated: false)
                    slider.sendActions(for: .valueChanged)
                }
            }
        }
    }
#endif
