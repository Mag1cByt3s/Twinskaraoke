import SDWebImageSwiftUI
import SwiftUI

struct ProfileDetailView: View {
  let displayName: String
  let avatarUrl: String?
  let profile: Profile?
  let badges: [Badge]
  let uploadLimits: UploadLimits?
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var selected: Badge?
  private let cols = AM.Layout.adaptiveGridColumns(minimum: 96, spacing: 14)
  private var unlocked: [Badge] { badges.filter { $0.unlocked } }
  private var locked: [Badge] { badges.filter { !$0.unlocked } }
  private var unlockedBadgeCount: Int { profile?.unlockedBadges ?? unlocked.count }
  private var totalBadgeCount: Int { max(profile?.totalBadges ?? badges.count, badges.count) }
  private var nextBadge: Badge? {
    locked.first { $0.conditionValue > 0 } ?? locked.first
  }
  private var contentMaxWidth: CGFloat {
    horizontalSizeClass == .regular ? 760 : .infinity
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        ProfileDetailHeader(
          displayName: displayName,
          avatarUrl: avatarUrl,
          profile: profile,
          unlockedCount: unlocked.count,
          totalCount: badges.count
        )
        if !badges.isEmpty {
          ProfileAchievementStrip(
            unlockedCount: unlockedBadgeCount,
            totalCount: totalBadgeCount,
            nextBadge: nextBadge,
            onSelect: selectBadge
          )
          .transition(bottomTransition)
        }
        if let uploadLimits {
          StorageSection(limits: uploadLimits)
        }
        if unlocked.isEmpty && locked.isEmpty {
          MusicEmptyState(
            title: "No Badges Yet",
            message: "Sing more songs to start unlocking profile badges."
          )
          .padding(.vertical, 28)
          .transition(emptyStateTransition)
        }
        if !unlocked.isEmpty {
          BadgeGridSection(
            title: "Unlocked",
            items: unlocked,
            headerCount: profile?.unlockedBadges,
            cols: cols,
            onSelect: selectBadge
          )
          .transition(bottomTransition)
        }
        if !locked.isEmpty {
          BadgeGridSection(
            title: "Locked",
            items: locked,
            headerCount: nil,
            cols: cols,
            onSelect: selectBadge
          )
          .transition(bottomTransition)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 20)
      .frame(maxWidth: contentMaxWidth, alignment: .top)
      .accessibilityIdentifier(horizontalSizeClass == .regular ? "Profile.WideOverview" : "Profile.CompactOverview")
    }
    .frame(maxWidth: .infinity)
    .scrollIndicators(.hidden)
    .smoothScrolling()
    .musicScreenBackground()
    .navigationTitle("Profile")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $selected) { badge in
      BadgeDetailSheet(badge: badge)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
    .animation(profileAnimation, value: badges.count)
    .animation(profileAnimation, value: unlocked.count)
  }

  private func selectBadge(_ badge: Badge) {
    guard !reduceMotion else {
      selected = badge
      return
    }
    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
      selected = badge
    }
  }

  private var profileAnimation: Animation? {
    reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.82)
  }

  private var bottomTransition: AnyTransition {
    reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom))
  }

  private var emptyStateTransition: AnyTransition {
    reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98))
  }

  private var reduceMotion: Bool {
    respectReducedMotion && systemReduceMotion
  }
}

private struct ProfileDetailHeader: View {
  let displayName: String
  let avatarUrl: String?
  let profile: Profile?
  let unlockedCount: Int
  let totalCount: Int
  var body: some View {
    VStack(spacing: 14) {
      ProfileAvatar(displayName: displayName, avatarUrl: avatarUrl, size: 96)
        .overlay(Circle().strokeBorder(Color(hex: "B47BFF").opacity(0.6), lineWidth: 2))
      VStack(spacing: 6) {
        Text(displayName)
          .font(.title2.weight(.bold))
        if let level = profile?.level {
          LevelChipLarge(level: level, title: profile?.levelTitle)
        }
      }
      if let progress = profile?.levelProgress {
        XPBar(
          progress: progress,
          totalXP: profile?.totalXP,
          xpToNextLevel: profile?.xpToNextLevel
        )
      }
      ProfileStatsCard(
        unlocked: profile?.unlockedBadges ?? unlockedCount,
        total: profile?.totalBadges ?? totalCount,
        level: profile?.level ?? 0
      )
    }
  }
}

private struct ProfileAvatar: View {
  let displayName: String
  let avatarUrl: String?
  let size: CGFloat
  var body: some View {
    Group {
      if let urlStr = avatarUrl, let url = URL(string: urlStr), !urlStr.isEmpty {
        WebImage(url: url, options: ImageCacheConfig.defaultOptions) { image in
          image.resizable().scaledToFill()
        } placeholder: {
          fallback
        }
      } else {
        fallback
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
  }
  private var fallback: some View {
    ZStack {
      Circle().fill(Color.appPlaceholderSecondary)
      if let first = displayName.first {
        Text(String(first).uppercased())
          .font(.system(size: size * 0.42, weight: .bold))
          .foregroundStyle(.secondary)
      } else {
        MusicCircularPlaceholder()
      }
    }
  }
}

private struct LevelChipLarge: View {
  let level: Int
  let title: String?
  var body: some View {
    HStack(spacing: 8) {
      Text("LV \(level)")
        .font(.caption.weight(.bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(ProfileTheme.gradient, in: Capsule())
      if let title, !title.isEmpty {
        Text(title)
          .font(.subheadline.weight(.medium))
          .foregroundStyle(.secondary)
      }
    }
  }
}

private struct XPBar: View {
  let progress: Double
  let totalXP: Int?
  let xpToNextLevel: Int?
  var body: some View {
    VStack(spacing: 6) {
      GradientProgressBar(progress: progress / 100, height: 6)
      HStack {
        if let totalXP {
          Text("\(totalXP) XP")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Spacer()
        if let xpToNextLevel, xpToNextLevel > 0 {
          Text("\(xpToNextLevel) to next level")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}

private struct ProfileStatsCard: View {
  let unlocked: Int
  let total: Int
  let level: Int
  var body: some View {
    HStack(spacing: 0) {
      stat(value: "\(unlocked)", label: "Unlocked")
      Divider().frame(height: 32)
      stat(value: "\(total)", label: "Total")
      Divider().frame(height: 32)
      stat(value: "\(level)", label: "Level")
    }
    .padding(.vertical, 12)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Color(.secondarySystemBackground))
    )
  }
  private func stat(value: String, label: String) -> some View {
    VStack(spacing: 2) {
      Text(value)
        .font(.system(size: 18, weight: .bold))
      Text(label)
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
  }
}

private struct ProfileAchievementStrip: View {
  let unlockedCount: Int
  let totalCount: Int
  let nextBadge: Badge?
  let onSelect: (Badge) -> Void
  private var completion: Double {
    guard totalCount > 0 else { return 0 }
    return min(1, Double(unlockedCount) / Double(totalCount))
  }
  private var completionText: String {
    "\(unlockedCount) of \(totalCount)"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .center, spacing: 14) {
        AchievementMeter(progress: completion)
          .frame(width: 74, height: 74)
        VStack(alignment: .leading, spacing: 5) {
          Text("Achievements")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.primary)
          Text("\(completionText) badges unlocked")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Text("Keep singing to complete your profile collection.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
      }

      if let nextBadge {
        Button {
          onSelect(nextBadge)
        } label: {
          NextBadgeCallout(badge: nextBadge)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98, dim: 0.82, haptic: .selection))
        .contextMenu {
          Button {
            onSelect(nextBadge)
          } label: {
            Label("View Badge", systemImage: "info.circle")
          }
        }
      }
    }
    .padding(16)
    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Color.appDivider, lineWidth: 1)
    )
  }
}

private struct AchievementMeter: View {
  let progress: Double
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var animatedProgress = 0.0

  var body: some View {
    ZStack {
      Circle()
        .stroke(Color.appControlInactiveFill, lineWidth: 8)
      Circle()
        .trim(from: 0, to: animatedProgress)
        .stroke(
          Color.appAccent,
          style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
        )
        .rotationEffect(.degrees(-90))
      VStack(spacing: 1) {
        Text("\(Int((animatedProgress * 100).rounded()))%")
          .font(.system(size: 16, weight: .bold))
          .monospacedDigit()
        Text("done")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(.secondary)
      }
    }
    .onAppear {
      setProgress(progress)
    }
    .onChange(of: progress) { _, newValue in
      setProgress(newValue)
    }
    .onChange(of: reduceMotion) { _, _ in
      setProgress(progress)
    }
  }

  private func setProgress(_ newValue: Double) {
    guard !reduceMotion else {
      animatedProgress = newValue
      return
    }
    withAnimation(.spring(response: 0.7, dampingFraction: 0.86)) {
      animatedProgress = newValue
    }
  }

  private var reduceMotion: Bool {
    respectReducedMotion && systemReduceMotion
  }
}

private struct NextBadgeCallout: View {
  let badge: Badge
  private var progressRatio: Double {
    guard badge.conditionValue > 0 else { return 0 }
    return min(1, Double(badge.currentProgress) / Double(badge.conditionValue))
  }
  private var progressText: String {
    guard badge.conditionValue > 0 else { return "View badge details" }
    return "\(badge.currentProgress) / \(badge.conditionValue)"
  }

  var body: some View {
    HStack(spacing: 12) {
      BadgeMiniIcon(badge: badge)
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          Text("Next Badge")
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.appAccent)
            .textCase(.uppercase)
          Spacer(minLength: 0)
          Text(progressText)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        Text(badge.name)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.primary)
          .lineLimit(1)
        if badge.conditionValue > 0 {
          GradientProgressBar(progress: progressRatio, height: 5)
        }
      }
      Image(systemName: "chevron.right")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.tertiary)
    }
    .padding(12)
    .background(Color.appControlInactiveFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .contentShape(Rectangle())
  }
}

private struct BadgeMiniIcon: View {
  let badge: Badge
  private var ringColor: Color { ProfileTheme.rarityColor(badge.rarity) }

  var body: some View {
    ZStack {
      Circle().fill(Color.appBackground)
      if let url = badge.iconURL {
        WebImage(url: url, options: ImageCacheConfig.defaultOptions) { image in
          image
            .resizable()
            .scaledToFit()
            .padding(8)
            .saturation(badge.unlocked ? 1 : 0)
            .opacity(badge.unlocked ? 1 : 0.45)
        } placeholder: {
          placeholder
        }
      } else {
        placeholder
      }
    }
    .frame(width: 46, height: 46)
    .overlay(Circle().strokeBorder(ringColor.opacity(0.55), lineWidth: 2))
    .overlay(alignment: .bottomTrailing) {
      if !badge.unlocked {
        Image(systemName: "lock.fill")
          .font(.system(size: 8, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 17, height: 17)
          .background(Color.primary.opacity(0.76), in: Circle())
          .overlay(Circle().strokeBorder(Color.appSecondaryBackground, lineWidth: 2))
      }
    }
  }

  private var placeholder: some View {
    MusicCircularPlaceholder()
  }
}

private struct BadgeGridSection: View {
  let title: String
  let items: [Badge]
  let headerCount: Int?
  let cols: [GridItem]
  let onSelect: (Badge) -> Void
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(title)
          .font(.system(size: 17, weight: .bold))
        Spacer()
        Text("\(headerCount ?? items.count)")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(.secondary)
      }
      LazyVGrid(columns: cols, spacing: 18) {
        ForEach(items) { badge in
          Button {
            onSelect(badge)
          } label: {
            BadgeGridCell(badge: badge)
          }
          .buttonStyle(PressableButtonStyle(scale: 0.94, dim: 0.82, haptic: .selection))
          .contextMenu {
            Button {
              AppHaptic.selection.play()
              onSelect(badge)
            } label: {
              Label("View Details", systemImage: "info.circle")
            }
          }
          .transition(cellTransition)
        }
      }
    }
  }

  private var cellTransition: AnyTransition {
    reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94))
  }

  private var reduceMotion: Bool {
    respectReducedMotion && systemReduceMotion
  }
}

struct BadgeGridCell: View {
  let badge: Badge
  private var ringColor: Color { ProfileTheme.rarityColor(badge.rarity) }
  private var progressRatio: Double {
    guard badge.conditionValue > 0 else { return 0 }
    return min(1, Double(badge.currentProgress) / Double(badge.conditionValue))
  }
  var body: some View {
    VStack(spacing: 6) {
      ZStack {
        Circle().fill(Color.appSecondaryBackground)
        if let url = badge.iconURL {
          WebImage(url: url, options: ImageCacheConfig.defaultOptions) { image in
            image
              .resizable()
              .scaledToFit()
              .padding(8)
              .saturation(badge.unlocked ? 1 : 0)
              .opacity(badge.unlocked ? 1 : 0.4)
          } placeholder: {
            MusicCircularPlaceholder()
          }
        } else {
          MusicCircularPlaceholder()
        }
      }
      .frame(width: 64, height: 64)
      .overlay(
        Circle().strokeBorder(ringColor.opacity(badge.unlocked ? 1 : 0.4), lineWidth: 2)
      )
      .overlay {
        if !badge.unlocked && badge.conditionValue > 0 {
          Circle()
            .trim(from: 0, to: progressRatio)
            .stroke(ringColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .padding(-2)
        }
      }
      .overlay(alignment: .bottomTrailing) {
        if !badge.unlocked {
          Image(systemName: "lock.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 19, height: 19)
            .background(Color.primary.opacity(0.72), in: Circle())
            .overlay(Circle().strokeBorder(Color.appBackground, lineWidth: 2))
        }
      }
      .shadow(color: ringColor.opacity(badge.unlocked ? 0.22 : 0.08), radius: 8, y: 4)
      Text(badge.name)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(badge.unlocked ? .primary : .secondary)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .frame(height: 28)
      Group {
        if !badge.unlocked && badge.conditionValue > 0 {
          Text("\(badge.currentProgress) / \(badge.conditionValue)")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
        } else if badge.unlocked {
          Text("Unlocked")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(ringColor)
        }
      }
      .frame(height: 12)
    }
    .contentShape(Rectangle())
  }
}

struct BadgeDetailSheet: View {
  let badge: Badge
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    ZStack(alignment: .topTrailing) {
      LinearGradient(
        colors: [Color.appSheetGradientTop, Color.appSheetGradientBottom],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()
      VStack(spacing: 20) {
        Spacer(minLength: 0)
        BadgeDetailIcon(badge: badge)
        BadgeDetailInfo(badge: badge)
        if badge.conditionValue > 0 {
          BadgeDetailProgress(badge: badge)
            .padding(.horizontal, 32)
        }
        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      Button {
        AppHaptic.light.play()
        dismiss()
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(.secondary)
          .frame(width: 30, height: 30)
          .background(Color(.tertiarySystemBackground), in: Circle())
      }
      .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.72))
      .padding(.top, 14)
      .padding(.trailing, 14)
    }
  }
}

private struct BadgeDetailIcon: View {
  let badge: Badge
  var body: some View {
    ZStack {
      Circle().fill(Color.appSecondaryBackground)
      if let url = badge.iconURL {
        WebImage(url: url, options: ImageCacheConfig.defaultOptions) { image in
          image
            .resizable()
            .scaledToFit()
            .padding(16)
            .saturation(badge.unlocked ? 1 : 0)
            .opacity(badge.unlocked ? 1 : 0.4)
        } placeholder: {
          placeholder
        }
      } else {
        placeholder
      }
    }
    .frame(width: 128, height: 128)
    .overlay(
      Circle().strokeBorder(ProfileTheme.rarityColor(badge.rarity).opacity(0.85), lineWidth: 3)
    )
    .overlay(alignment: .bottomTrailing) {
      if !badge.unlocked {
        Image(systemName: "lock.fill")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 30, height: 30)
          .background(Color.primary.opacity(0.76), in: Circle())
          .overlay(Circle().strokeBorder(Color.appBackground, lineWidth: 3))
      }
    }
    .shadow(color: ProfileTheme.rarityColor(badge.rarity).opacity(0.22), radius: 16, y: 8)
  }
  private var placeholder: some View {
    MusicCircularPlaceholder()
  }
}

private struct BadgeDetailInfo: View {
  let badge: Badge
  var body: some View {
    VStack(spacing: 8) {
      Text(badge.name)
        .font(.title3.weight(.bold))
        .multilineTextAlignment(.center)
      HStack(spacing: 8) {
        BadgeStatusPill(unlocked: badge.unlocked)
        BadgeRarityPill(rarity: badge.rarity)
      }
      if let description = badge.description, !description.isEmpty {
        Text(description)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 24)
      }
    }
  }
}

private struct BadgeStatusPill: View {
  let unlocked: Bool
  var body: some View {
    Label(
      unlocked ? "Unlocked" : "Locked",
      systemImage: unlocked ? "checkmark.circle.fill" : "lock.fill"
    )
      .font(.caption.weight(.semibold))
      .foregroundStyle(unlocked ? Color.green : Color.secondary)
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(Color.appControlInactiveFill, in: Capsule())
  }
}

private struct BadgeRarityPill: View {
  let rarity: Int
  private var label: String {
    switch rarity {
    case 0: return "Common"
    case 1: return "Rare"
    case 2: return "Epic"
    default: return "Legendary"
    }
  }
  var body: some View {
    Text(label)
      .font(.caption.weight(.semibold))
      .foregroundStyle(ProfileTheme.rarityColor(rarity))
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(ProfileTheme.rarityColor(rarity).opacity(0.12), in: Capsule())
  }
}

private struct BadgeDetailProgress: View {
  let badge: Badge
  private var ratio: Double {
    guard badge.conditionValue > 0 else { return 0 }
    return min(1, Double(badge.currentProgress) / Double(badge.conditionValue))
  }
  var body: some View {
    VStack(spacing: 8) {
      GradientProgressBar(progress: ratio, height: 7)
      Text("\(badge.currentProgress) / \(badge.conditionValue)")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
  }
}
