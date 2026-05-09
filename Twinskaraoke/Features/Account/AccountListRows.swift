import SDWebImageSwiftUI
import SwiftUI

struct ProfileHeaderRow: View {
  let displayName: String
  let avatarUrl: String?
  let level: Int?
  let levelTitle: String?
  let levelProgress: Double?
  let xpToNextLevel: Int?
  var body: some View {
    HStack(spacing: 16) {
      avatarView
        .frame(width: 64, height: 64)
        .clipShape(Circle())
      VStack(alignment: .leading, spacing: 6) {
        Text(displayName)
          .font(.title3.weight(.semibold))
          .foregroundStyle(.primary)
        if let level {
          levelChip(level: level, title: levelTitle)
        }
        if let progress = levelProgress {
          xpProgress(progress: progress, xpRemaining: xpToNextLevel)
        }
      }
      Spacer()
    }
    .padding(.vertical, 8)
  }
  private func levelChip(level: Int, title: String?) -> some View {
    HStack(spacing: 6) {
      Text("LV \(level)")
        .font(.caption.weight(.bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(ProfileTheme.gradient, in: Capsule())
      if let title, !title.isEmpty {
        Text(title)
          .font(.caption.weight(.medium))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
  }
  @ViewBuilder
  private func xpProgress(progress: Double, xpRemaining: Int?) -> some View {
    GradientProgressBar(progress: progress / 100, height: 4)
    if let xpRemaining, xpRemaining > 0 {
      Text("\(xpRemaining) XP to next level")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
  }
  @ViewBuilder
  private var avatarView: some View {
    if let urlStr = avatarUrl, let url = URL(string: urlStr), !urlStr.isEmpty {
      AsyncImage(url: url) { phase in
        switch phase {
        case .success(let img): img.resizable().scaledToFill()
        default: initials
        }
      }
    } else {
      initials
    }
  }
  private var initials: some View {
    ZStack {
      ProfileTheme.radialGradient
      Text(String(displayName.prefix(1).uppercased()))
        .font(.system(size: 26, weight: .bold))
        .foregroundStyle(.white)
    }
  }
}

struct UnlockedBadgesRow: View {
  let badges: [Badge]
  let unlockedCount: Int
  let totalCount: Int
  @State private var selected: Badge?
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Badges")
          .font(.system(size: 15, weight: .semibold))
        Spacer()
        Text("\(unlockedCount) / \(totalCount)")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.secondary)
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 12) {
          ForEach(badges) { badge in
            Button {
              selected = badge
            } label: {
              BadgeIcon(badge: badge)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.vertical, 2)
      }
    }
    .padding(.vertical, 8)
    .sheet(item: $selected) { badge in
      BadgeDetailSheet(badge: badge)
        .presentationDetents([.medium])
    }
  }
}

struct BadgeIcon: View {
  let badge: Badge
  var body: some View {
    VStack(spacing: 4) {
      ZStack {
        Circle().fill(Color(.secondarySystemBackground))
        if let url = badge.iconURL {
          WebImage(url: url, options: ImageCacheConfig.defaultOptions) { image in
            image.resizable().scaledToFit().padding(4)
          } placeholder: {
            Image(systemName: "rosette")
              .font(.system(size: 18))
              .foregroundStyle(.secondary)
          }
        } else {
          Image(systemName: "rosette")
            .font(.system(size: 18))
            .foregroundStyle(.secondary)
        }
      }
      .frame(width: 44, height: 44)
      .overlay(
        Circle().strokeBorder(ProfileTheme.rarityColor(badge.rarity), lineWidth: 1.5))
      Text(badge.name)
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(width: 56)
    }
  }
}
