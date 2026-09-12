import SwiftUI

struct PlayerVolumeRow: View {
    var horizontalPadding: CGFloat = 32

    var body: some View {
        #if canImport(UIKit)
            SystemVolumeBridge()
                .frame(height: 32)
                .padding(.horizontal, horizontalPadding)
        #endif
    }
}
