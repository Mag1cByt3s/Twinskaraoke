#if canImport(UIKit)
    import MediaPlayer
    import SwiftUI

    enum SystemVolumeReconciliation {
        static func value(
            currentVolume: Double,
            systemVolume: Float,
            isUserScrubbing: Bool
        ) -> Double {
            isUserScrubbing ? currentVolume : Double(systemVolume)
        }
    }

    /// Let the system own volume interaction, routing, and accessibility.
    /// MPVolumeView's internal slider hierarchy is not a supported API.
    struct SystemVolumeBridge: UIViewRepresentable {
        func makeUIView(context _: Context) -> MPVolumeView {
            MPVolumeView(frame: .zero)
        }

        func updateUIView(_: MPVolumeView, context _: Context) {}
    }
#endif
