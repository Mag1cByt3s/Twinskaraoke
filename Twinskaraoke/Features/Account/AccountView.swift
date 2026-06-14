import SwiftUI

struct AccountView: View {
  @StateObject private var auth = AuthManager()
  @EnvironmentObject var audioManager: AudioPlayerManager
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var showLoginSheet = false
  @State private var showQRApprove = false
  @State private var showSignOutConfirm = false
  @State private var profile: Profile?
  @State private var badges: [Badge] = []
  @State private var uploadLimits: UploadLimits?
  @State private var levelUpAnnouncement: LevelUpAnnouncement?

  private var usesWideOverview: Bool {
    horizontalSizeClass == .regular
  }

  var body: some View {
    NavigationStack {
      accountContent
      .navigationTitle("Account")
      .navigationBarTitleDisplayMode(.large)
      .sheet(isPresented: $showLoginSheet) {
        LoginSheet(auth: auth)
      }
      .sheet(isPresented: $showQRApprove) {
        QRApproveView(auth: auth)
      }
      .sheet(item: $levelUpAnnouncement) { announcement in
        LevelUpSheet(announcement: announcement)
          .presentationDetents([.medium])
          .presentationBackground(.clear)
      }
      .task(id: auth.isLoggedIn) {
        if auth.isLoggedIn {
          await loadData()
          FavoritesManager.shared.reload()
        } else {
          profile = nil
          badges = []
          uploadLimits = nil
          levelUpAnnouncement = nil
          FavoritesManager.shared.clear()
        }
      }
    }
  }

  @ViewBuilder
  private var accountContent: some View {
    if usesWideOverview {
      ZStack(alignment: .top) {
        Color.appGroupedBackground.ignoresSafeArea()
        accountList
          .frame(maxWidth: 640, maxHeight: .infinity, alignment: .top)
          .padding(.horizontal, AM.Spacing.screenMargin)
          .accessibilityIdentifier("Account.WideOverview")
      }
    } else {
      accountList
    }
  }

  private var accountList: some View {
    List {
      profileSection
      generalSection
      if auth.isLoggedIn { signOutSection }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(Color.appGroupedBackground.ignoresSafeArea())
    .refreshable {
      if auth.isLoggedIn {
        AppHaptic.selection.play()
        await loadData()
      }
    }
  }

  @ViewBuilder
  private var profileSection: some View {
    if auth.isLoggedIn {
      Section {
        NavigationLink {
          ProfileDetailView(
            displayName: profile?.displayName ?? auth.currentUsername ?? "",
            avatarUrl: profile?.avatarUrl ?? auth.currentAvatar,
            profile: profile,
            badges: badges,
            uploadLimits: uploadLimits
          )
        } label: {
          ProfileHeaderRow(
            displayName: profile?.displayName ?? auth.currentUsername ?? "",
            avatarUrl: profile?.avatarUrl ?? auth.currentAvatar,
            level: profile?.level,
            levelTitle: profile?.levelTitle,
            levelProgress: profile?.levelProgress,
            xpToNextLevel: profile?.xpToNextLevel
          )
        }
        if !unlockedBadges.isEmpty {
          UnlockedBadgesRow(
            badges: unlockedBadges,
            unlockedCount: profile?.unlockedBadges ?? unlockedBadges.count,
            totalCount: profile?.totalBadges ?? badges.count
          )
        }
      }
    } else {
      Section {
        Button {
          AppHaptic.selection.play()
          showLoginSheet = true
        } label: {
          SignInPromptRow()
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98, dim: 0.82))
        .accessibilityLabel("Sign In")
        .accessibilityHint("Opens account sign-in.")
      }
    }
  }
  private var generalSection: some View {
    Section {
      if auth.isLoggedIn {
        Button {
          AppHaptic.selection.play()
          showQRApprove = true
        } label: {
          Label("Sign in on web", systemImage: "qrcode.viewfinder")
            .foregroundStyle(.primary)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98, dim: 0.82))
        .accessibilityLabel("Sign in on web")
        .accessibilityHint("Shows a QR code to authorize a browser session.")
      }
      NavigationLink {
        NotificationsView()
      } label: {
        Label("Notifications", systemImage: "bell")
      }
      NavigationLink {
        SettingsView()
      } label: {
        Label("Settings", systemImage: "gearshape")
      }
      NavigationLink {
        AboutView()
      } label: {
        Label("About", systemImage: "info.circle")
      }
    }
  }
  private var signOutSection: some View {
    Section {
      Button(role: .destructive) {
        AppHaptic.warning.play()
        showSignOutConfirm = true
      } label: {
        HStack {
          Spacer()
          Text("Sign Out")
            .foregroundStyle(Color.appAccent)
          Spacer()
        }
      }
      .alert("Sign out?", isPresented: $showSignOutConfirm) {
        Button("Cancel", role: .cancel) {}
          .tint(Color(uiColor: .systemBlue))
        Button("Sign Out", role: .destructive) {
          AppHaptic.warning.play()
          auth.logout()
        }
      } message: {
        Text("You'll need to sign in again to access your library and account features.")
      }
      .accessibilityLabel("Sign Out")
      .accessibilityHint("Asks for confirmation before signing out.")
    }
  }
  private var unlockedBadges: [Badge] {
    badges.filter { $0.unlocked }
  }
  private func loadData() async {
    guard let token = auth.authToken else { return }
    async let badgeData = fetchAuthorized(path: "/api/badge/profile", token: token)
    async let limitData = fetchAuthorized(path: "/api/user/upload-limits", token: token)
    if let data = await badgeData,
      let decoded = try? JSONDecoder().decode(ProfileResponse.self, from: data)
    {
      handleLevelChange(with: decoded.profile)
      profile = decoded.profile
      badges = decoded.badges ?? []
    }
    if let data = await limitData,
      let decoded = try? JSONDecoder().decode(UploadLimits.self, from: data)
    {
      uploadLimits = decoded
    }
  }
  private func fetchAuthorized(path: String, token: String) async -> Data? {
    guard let url = URL(string: "\(StorageHost.api)\(path)") else { return nil }
    var req = URLRequest(url: url)
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    return try? await URLSession.shared.data(for: req).0
  }

  private func handleLevelChange(with newProfile: Profile) {
    guard let level = newProfile.level, level > 0 else { return }
    guard let identity = auth.currentUserId ?? auth.currentUsername, !identity.isEmpty else {
      return
    }

    let key = "nk.lastSeenLevel.\(identity)"
    let defaults = UserDefaults.standard

    if defaults.object(forKey: key) == nil {
      defaults.set(level, forKey: key)
      return
    }

    let previousLevel = defaults.integer(forKey: key)
    if level > previousLevel {
      levelUpAnnouncement = LevelUpAnnouncement(
        previousLevel: previousLevel,
        currentLevel: level,
        levelTitle: newProfile.levelTitle
      )
    }
    defaults.set(level, forKey: key)
  }
}

private struct SignInPromptRow: View {
  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: "person.circle.fill")
        .font(.system(size: 60))
        .foregroundStyle(Color(.systemGray3))
      VStack(alignment: .leading, spacing: 3) {
        Text("Sign In")
          .font(.title3.weight(.semibold))
          .foregroundStyle(.primary)
        Text("Sign in to access your library")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Image(systemName: "chevron.right")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color(.systemGray3))
    }
    .padding(.vertical, 6)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Sign In")
    .accessibilityHint("Sign in to access your library.")
  }
}

private struct NotificationsView: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @AppStorage("nk.notifications.newSongs") private var newSongs = true
  @AppStorage("nk.notifications.radio") private var radio = true
  @AppStorage("nk.notifications.downloads") private var downloads = true
  @AppStorage("nk.notifications.account") private var account = true

  private var enabledCount: Int {
    [newSongs, radio, downloads, account].filter { $0 }.count
  }

  var body: some View {
    notificationsContent
      .navigationTitle("Notifications")
      .navigationBarTitleDisplayMode(.inline)
  }

  @ViewBuilder
  private var notificationsContent: some View {
    if horizontalSizeClass == .regular {
      ZStack(alignment: .top) {
        Color.appGroupedBackground.ignoresSafeArea()
        notificationsList
          .frame(maxWidth: 640, maxHeight: .infinity, alignment: .top)
          .padding(.horizontal, AM.Spacing.screenMargin)
          .accessibilityIdentifier("Notifications.WideOverview")
      }
    } else {
      notificationsList
    }
  }

  private var notificationsList: some View {
    List {
      Section {
        summaryRow
          .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
      }
      Section {
        NotificationPreferenceToggle(
          symbol: "music.note",
          color: .appAccent,
          title: "New Songs",
          subtitle: "Karaoke releases and new additions",
          isOn: $newSongs
        )
        NotificationPreferenceToggle(
          symbol: "dot.radiowaves.left.and.right",
          color: .purple,
          title: "Radio",
          subtitle: "Live station changes and featured shows",
          isOn: $radio
        )
        NotificationPreferenceToggle(
          symbol: "arrow.down.circle",
          color: .blue,
          title: "Downloads",
          subtitle: "Completed offline saves and storage updates",
          isOn: $downloads
        )
        NotificationPreferenceToggle(
          symbol: "person.crop.circle.badge.checkmark",
          color: .green,
          title: "Account",
          subtitle: "Badges, levels, and sign-in activity",
          isOn: $account
        )
      } header: {
        Text("Alerts")
      } footer: {
        Text("Preferences are saved on this device and use the same account settings style as Music.")
      }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(Color.appGroupedBackground.ignoresSafeArea())
  }

  private var summaryRow: some View {
    HStack(spacing: 14) {
      Image(systemName: "bell.badge.fill")
        .font(.system(size: 24, weight: .semibold))
        .foregroundColor(.white)
        .frame(width: 52, height: 52)
        .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      VStack(alignment: .leading, spacing: 3) {
        Text("Notification Preferences")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(.primary)
        Text("\(enabledCount) alert\(enabledCount == 1 ? "" : "s") enabled")
          .font(.system(size: 14))
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      Spacer()
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Notification Preferences")
    .accessibilityValue("\(enabledCount) alert\(enabledCount == 1 ? "" : "s") enabled")
  }
}

private struct NotificationPreferenceToggle: View {
  let symbol: String
  let color: Color
  let title: String
  let subtitle: String
  @Binding var isOn: Bool

  var body: some View {
    Toggle(isOn: $isOn) {
      HStack(spacing: 12) {
        Image(systemName: symbol)
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.white)
          .frame(width: 30, height: 30)
          .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.system(size: 16))
            .foregroundStyle(.primary)
          Text(subtitle)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }
      .padding(.vertical, 3)
    }
    .tint(.appAccent)
    .accessibilityLabel(title)
    .accessibilityValue(isOn ? "On" : "Off")
    .accessibilityHint(subtitle)
    .onChange(of: isOn) { _, enabled in
      enabled ? AppHaptic.selection.play() : AppHaptic.light.play()
    }
  }
}
