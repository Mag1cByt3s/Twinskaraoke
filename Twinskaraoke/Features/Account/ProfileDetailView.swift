import SDWebImageSwiftUI
import SwiftUI

struct ProfileDetailView: View {
  let displayName: String
  let avatarUrl: String?
  let profile: Profile?
  let badges: [Badge]
  let uploadLimits: UploadLimits?
  @State private var selected: Badge?
  private let cols = [
    GridItem(.flexible(), spacing: 14),
    GridItem(.flexible(), spacing: 14),
    GridItem(.flexible(), spacing: 14),
  ]
  private var unlocked: [Badge] { badges.filter { $0.unlocked } }
  private var locked: [Badge] { badges.filter { !$0.unlocked } }
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
        if let uploadLimits {
          StorageSection(limits: uploadLimits)
        }
        if !unlocked.isEmpty {
          BadgeGridSection(
            title: "Unlocked",
            items: unlocked,
            headerCount: profile?.unlockedBadges,
            cols: cols,
            onSelect: { selected = $0 }
          )
        }
        if !locked.isEmpty {
          BadgeGridSection(
            title: "Locked",
            items: locked,
            headerCount: nil,
            cols: cols,
            onSelect: { selected = $0 }
          )
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 20)
    }
    .navigationTitle("Profile")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $selected) { badge in
      BadgeDetailSheet(badge: badge)
        .presentationDetents([.medium])
    }
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
      ProfileTheme.radialGradient
      Text(String(displayName.prefix(1).uppercased()))
        .font(.system(size: size * 0.42, weight: .bold))
        .foregroundStyle(.white)
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

private struct BadgeGridSection: View {
  let title: String
  let items: [Badge]
  let headerCount: Int?
  let cols: [GridItem]
  let onSelect: (Badge) -> Void
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
          .buttonStyle(.plain)
        }
      }
    }
  }
}

struct BadgeGridCell: View {
  let badge: Badge
  private var ringColor: Color { ProfileTheme.rarityColor(badge.rarity) }
  var body: some View {
    VStack(spacing: 6) {
      ZStack {
        Circle().fill(Color(.secondarySystemBackground))
        if let url = badge.iconURL {
          WebImage(url: url, options: ImageCacheConfig.defaultOptions) { image in
            image
              .resizable()
              .scaledToFit()
              .padding(8)
              .saturation(badge.unlocked ? 1 : 0)
              .opacity(badge.unlocked ? 1 : 0.4)
          } placeholder: {
            Image(systemName: "rosette")
              .font(.system(size: 22))
              .foregroundStyle(.secondary)
          }
        } else {
          Image(systemName: "rosette")
            .font(.system(size: 22))
            .foregroundStyle(.secondary)
        }
      }
      .frame(width: 64, height: 64)
      .overlay(
        Circle().strokeBorder(ringColor.opacity(badge.unlocked ? 1 : 0.4), lineWidth: 2)
      )
      Text(badge.name)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(badge.unlocked ? .primary : .secondary)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .frame(height: 28)
      if !badge.unlocked && badge.conditionValue > 0 {
        Text("\(badge.currentProgress) / \(badge.conditionValue)")
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(.secondary)
      }
    }
  }
}

struct BadgeDetailSheet: View {
  let badge: Badge
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    ZStack(alignment: .topTrailing) {
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
        dismiss()
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(.secondary)
          .frame(width: 30, height: 30)
          .background(Color(.tertiarySystemBackground), in: Circle())
      }
      .buttonStyle(.plain)
        .padding(.top, 14)
        .padding(.trailing, 14)
    }
  }
}

private struct BadgeDetailIcon: View {
  let badge: Badge
  var body: some View {
    ZStack {
      Circle().fill(Color(.secondarySystemBackground))
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
  }
  private var placeholder: some View {
    Image(systemName: "rosette")
      .font(.system(size: 40))
      .foregroundStyle(.secondary)
  }
}

private struct BadgeDetailInfo: View {
  let badge: Badge
  var body: some View {
    VStack(spacing: 8) {
      Text(badge.name)
        .font(.title3.weight(.bold))
        .multilineTextAlignment(.center)
      if let description = badge.description, !description.isEmpty {
        Text(description)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
    }
    .padding(.horizontal, 24)
  }
}

private struct BadgeDetailProgress: View {
  let badge: Badge
  private var ratio: Double {
    guard badge.conditionValue > 0 else { return 0 }
    return Double(badge.currentProgress) / Double(badge.conditionValue)
  }
  var body: some View {
    VStack(spacing: 6) {
      GradientProgressBar(progress: ratio, height: 6)
      Text("\(badge.currentProgress) / \(badge.conditionValue)")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}
