import SwiftUI

struct AccountView: View {
  @StateObject private var auth = AuthManager()
  @EnvironmentObject var audioManager: AudioPlayerManager
  @State private var showLoginSheet = false
  @State private var showQRApprove = false
  @State private var showSignOutConfirm = false
  @State private var profile: Profile?
  @State private var badges: [Badge] = []
  @State private var uploadLimits: UploadLimits?
  @State private var levelUpAnnouncement: LevelUpAnnouncement?
  var body: some View {
    NavigationStack {
      List {
        profileSection
        generalSection
        if auth.isLoggedIn { signOutSection }
      }
      .listStyle(.insetGrouped)
      .navigationTitle("Account")
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
          showLoginSheet = true
        } label: {
          SignInPromptRow()
        }
      }
    }
  }
  private var generalSection: some View {
    Section {
      if auth.isLoggedIn {
        Button {
          showQRApprove = true
        } label: {
          Label("Sign in on web", systemImage: "qrcode.viewfinder")
            .foregroundStyle(.primary)
        }
      }
      NavigationLink {
        Text("Notifications").navigationTitle("Notifications")
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
          auth.logout()
        }
      } message: {
        Text("You'll need to sign in again to access your library.")
      }
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
    guard let identity = auth.currentUserId ?? auth.currentUsername, !identity.isEmpty else { return }

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
  }
}
