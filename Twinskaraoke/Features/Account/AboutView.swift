import SDWebImageSwiftUI
import SwiftUI

struct AboutView: View {
  private var appVersion: String {
    let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    return "\(v) (\(b))"
  }
  @State private var versionTapCount = 0
  @State private var showEasterEgg = false
  var body: some View {
    List {
      Section {
        VStack(spacing: 14) {
          appIconView
          Text("Twinskaraoke")
            .font(.title2.bold())
          Text("Version \(appVersion)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .onTapGesture {
              versionTapCount += 1
              if versionTapCount >= 10 {
                versionTapCount = 0
                showEasterEgg = true
              }
            }
          Text("NEUROKARAOKE.COM • EVILKARAOKE.COM • TWINSKARAOKE.COM")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.6)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .listRowBackground(Color.clear)
        .listRowInsets(.init())
      }
      Section("About Neuro & Evil Karaoke Web Player") {
        Text(AboutContent.intro)
          .font(.system(size: 14))
          .foregroundStyle(.primary)
          .padding(.vertical, 4)
        Text(AboutContent.unofficialNotice)
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
          .padding(.vertical, 4)
      }
      Section("Explore") {
        NavigationLink {
          longText("Features & Content", body: AboutContent.features)
        } label: {
          AboutLinkRow(icon: "sparkles", color: .appAccent, title: "Features & Content")
        }
        NavigationLink {
          CreditsView()
        } label: {
          AboutLinkRow(icon: "heart.fill", color: .pink, title: "Credits")
        }
        NavigationLink {
          longText("Language Support", body: AboutContent.language)
        } label: {
          AboutLinkRow(icon: "globe", color: .blue, title: "Language Support")
        }
        NavigationLink {
          iOSAppDevelopmentView()
        } label: {
          AboutLinkRow(icon: "hammer.fill", color: .orange, title: "iOS App Development")
        }
        NavigationLink {
          longText("Contact & Take-Down Requests", body: AboutContent.contact)
        } label: {
          AboutLinkRow(icon: "envelope.fill", color: .indigo, title: "Contact")
        }
      }
      Section("Resources") {
        Link(destination: URL(string: "https://radio.twinskaraoke.com")!) {
          AboutLinkRow(
            icon: "dot.radiowaves.left.and.right", color: .appAccent,
            title: "Neuro 21 Radio Station")
        }
        Link(destination: URL(string: "\(StorageHost.api)")!) {
          AboutLinkRow(icon: "server.rack", color: .blue, title: "API Service")
        }
        Link(destination: URL(string: "https://www.youtube.com/@neurokaraoke")!) {
          AboutLinkRow(
            icon: "play.rectangle.fill", color: .appAccent, title: "Video Gallery (YouTube)")
        }
        Link(destination: URL(string: "https://github.com/Evil-Project/Twinskaraoke")!) {
          AboutLinkRow(
            icon: "chevron.left.forwardslash.chevron.right", color: .black,
            title: "iOS App Source (GitHub)")
        }
      }
      Section("Legal") {
        NavigationLink {
          longText("Privacy Policy", body: AboutContent.privacy)
        } label: {
          AboutLinkRow(icon: "hand.raised.fill", color: .gray, title: "Privacy Policy")
        }
        NavigationLink {
          longText("Terms of Service", body: AboutContent.terms)
        } label: {
          AboutLinkRow(icon: "doc.text.fill", color: .gray, title: "Terms of Service")
        }
        NavigationLink {
          AcknowledgementsView()
        } label: {
          AboutLinkRow(icon: "shippingbox.fill", color: .orange, title: "Open Source Licenses")
        }
      }
      Section {
        Text("© 2026 Neuro & Evil Karaoke Web Player\nFan-made by Soul. Unofficial.")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity, alignment: .center)
          .listRowBackground(Color.clear)
      }
    }
    .navigationTitle("About")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $showEasterEgg) {
      EasterEggView()
    }
  }
  private func longText(_ title: String, body: String) -> some View {
    ScrollView {
      LinkifiedText(text: body)
        .font(.system(size: 14))
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
  }
  @ViewBuilder
  private var appIconView: some View {
    AnimatedImage(data: NSDataAsset(name: "AppLogo")?.data ?? Data())
      .resizable()
      .scaledToFill()
      .frame(width: 96, height: 96)
      .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
      .shadow(color: Color.black.opacity(0.18), radius: 14, y: 6)
  }
}

private struct EasterEggView: View {
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    ZStack {
      LinearGradient(
        colors: [.appSheetGradientTop, .appSheetGradientBottom],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()
      VStack(spacing: 20) {
        AnimatedImage(url: URL(string: "https://storage.neurokaraoke.com/media/nuero_.gif"))
          .resizable()
          .scaledToFit()
          .padding(.horizontal, 24)
        Text("404 Not Found")
          .font(.system(size: 28, weight: .bold, design: .monospaced))
          .foregroundColor(.primary)
        Text("You've reached the empty place")
          .font(.system(size: 16))
          .foregroundColor(.secondary)
      }
    }
    .onTapGesture { dismiss() }
  }
}
