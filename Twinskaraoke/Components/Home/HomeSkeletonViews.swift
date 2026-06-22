import SwiftUI

struct HomeSkeletonView: View {
    var body: some View {
        CenteredLoadingView(label: "Loading Home")
    }
}

struct NewSkeletonView: View {
    var body: some View {
        CenteredLoadingView(label: "Loading New")
    }
}
