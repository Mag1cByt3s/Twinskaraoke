import SwiftUI

struct ArtGalleryView: View {
  @StateObject private var viewModel = ArtGalleryViewModel()
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  var body: some View {
    ScrollView {
      if viewModel.isLoading && viewModel.artists.isEmpty {
        ArtGallerySkeletonView()
          .padding(.top, 16)
          .transition(.opacity)
      } else if viewModel.artists.isEmpty {
        ArtGalleryEmptyState(isError: viewModel.loadFailed) {
          viewModel.fetch(force: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 96)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
      } else {
        VStack(alignment: .leading, spacing: 28) {
          if let featured = featuredArt {
            NavigationLink {
              ArtDetailView(art: featured.art, artist: featured.artist)
            } label: {
              FeaturedArtCard(art: featured.art, artist: featured.artist)
            }
            .buttonStyle(PressableButtonStyle())
            .simultaneousGesture(TapGesture().onEnded { AppHaptic.selection.play() })
            .contextMenu {
              if let url = featured.art.fullHDImageURL ?? featured.art.imageURL {
                ShareLink(item: url) {
                  Label("Share Artwork", systemImage: "square.and.arrow.up")
                }
              }
              if let upvotes = featured.art.upvotes, upvotes > 0 {
                Label("\(upvotes) likes", systemImage: "heart.fill")
              }
            } preview: {
              GalleryArtPreview(art: featured.art, artist: featured.artist)
            }
            .padding(.horizontal, 16)
          }
          GalleryStatsStrip(
            artistCount: viewModel.artists.count,
            artworkCount: artworkCount,
            totalUpvotes: totalUpvotes
          )
          .padding(.horizontal, 16)
          if !topArtists.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
              GallerySectionHeader(title: "Featured Artists")
              ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                  ForEach(topArtists) { artist in
                    NavigationLink {
                      ArtistArtsView(artist: artist)
                    } label: {
                      ArtistCircleCard(artist: artist)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .simultaneousGesture(TapGesture().onEnded { AppHaptic.selection.play() })
                  }
                }
                .padding(.horizontal, 16)
              }
            }
          }
          VStack(alignment: .leading, spacing: 12) {
            GallerySectionHeader(title: "All Artists")
            LazyVStack(spacing: 0) {
              ForEach(Array(viewModel.artists.enumerated()), id: \.element.id) { idx, artist in
                NavigationLink {
                  ArtistArtsView(artist: artist)
                } label: {
                  ArtistListRow(artist: artist)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { AppHaptic.selection.play() })
                if idx < viewModel.artists.count - 1 {
                  Divider().padding(.leading, 78)
                }
              }
            }
            .padding(.horizontal, 16)
          }
        }
        .padding(.vertical, 16)
      }
    }
    .smoothScrolling()
    .navigationTitle("Art Gallery")
    .navigationBarTitleDisplayMode(.large)
    .refreshable {
      AppHaptic.selection.play()
      viewModel.fetch(force: true)
    }
    .onAppear { viewModel.fetch() }
    .animation(
      reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.84),
      value: viewModel.artists.count)
  }
  private var featuredArt: (art: GalleryArt, artist: GalleryArtist)? {
    for artist in viewModel.artists {
      if let art = artist.arts?.max(by: { ($0.upvotes ?? 0) < ($1.upvotes ?? 0) }) {
        return (art, artist)
      }
    }
    return nil
  }
  private var topArtists: [GalleryArtist] {
    Array(viewModel.artists.prefix(12))
  }
  private var artworkCount: Int {
    viewModel.artists.reduce(0) { $0 + ($1.arts?.count ?? 0) }
  }
  private var totalUpvotes: Int {
    viewModel.artists.reduce(0) { partial, artist in
      partial + (artist.arts ?? []).reduce(0) { $0 + ($1.upvotes ?? 0) }
    }
  }
}

private struct ArtGallerySkeletonView: View {
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var pulse = false

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 28) {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color.appPlaceholderPrimary)
        .aspectRatio(4 / 5, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottomLeading) {
          VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
              .fill(Color.appPlaceholderSecondary)
              .frame(width: 96, height: 11)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
              .fill(Color.appPlaceholderSecondary)
              .frame(width: 168, height: 22)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
              .fill(Color.appPlaceholderPrimary)
              .frame(width: 62, height: 13)
          }
          .padding(20)
        }
        .padding(.horizontal, 16)

      VStack(alignment: .leading, spacing: 12) {
        skeletonTitle(width: 154)
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(alignment: .top, spacing: 14) {
            ForEach(0..<6, id: \.self) { index in
              VStack(spacing: 8) {
                Circle()
                  .fill(Color.appPlaceholderPrimary)
                  .frame(width: 96, height: 96)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                  .fill(Color.appPlaceholderSecondary)
                  .frame(width: index == 2 ? 72 : 86, height: 13)
              }
              .frame(width: 100)
            }
          }
          .padding(.horizontal, 16)
        }
      }

      VStack(alignment: .leading, spacing: 12) {
        skeletonTitle(width: 88)
        LazyVStack(spacing: 0) {
          ForEach(0..<7, id: \.self) { index in
            HStack(spacing: 14) {
              Circle()
                .fill(Color.appPlaceholderPrimary)
                .frame(width: 50, height: 50)
              VStack(alignment: .leading, spacing: 2) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                  .fill(Color.appPlaceholderSecondary)
                  .frame(width: index == 3 ? 126 : 164, height: 16)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                  .fill(Color.appPlaceholderPrimary)
                  .frame(width: 86, height: 13)
              }
              Spacer(minLength: 12)
              RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.appPlaceholderPrimary)
                .frame(width: 7, height: 14)
            }
            .padding(.vertical, 10)
            if index < 6 {
              Divider().padding(.leading, 78)
            }
          }
        }
        .padding(.horizontal, 16)
      }
    }
    .opacity(!reduceMotion && pulse ? 0.58 : 1.0)
    .redacted(reason: .placeholder)
    .musicSkeletonShimmer(active: true)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Loading art gallery")
    .onAppear {
      guard !reduceMotion else {
        pulse = false
        return
      }
      withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
        pulse = true
      }
    }
    .onChange(of: reduceMotion) { _, reduceMotion in
      if reduceMotion {
        withAnimation(nil) {
          pulse = false
        }
      } else {
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
          pulse = true
        }
      }
    }
  }

  private func skeletonTitle(width: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: 4, style: .continuous)
      .fill(Color.appPlaceholderSecondary)
      .frame(width: width, height: 22)
      .padding(.horizontal, 16)
  }
}

private struct GallerySectionHeader: View {
  let title: String
  var body: some View {
    Text(title)
      .font(.system(size: 22, weight: .bold))
      .padding(.horizontal, 16)
  }
}

private struct ArtGalleryEmptyState: View {
  let isError: Bool
  let onRefresh: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      MusicEmptyState(
        title: isError ? "Artwork Couldn't Load" : "No Artwork Yet",
        message: isError
          ? "Check your connection and try loading the gallery again."
          : "New cover art and artist galleries will appear here."
      )
      MusicEmptyActionButton(title: isError ? "Try Again" : "Refresh") {
        onRefresh()
      }
    }
  }
}

private struct GalleryStatsStrip: View {
  let artistCount: Int
  let artworkCount: Int
  let totalUpvotes: Int

  var body: some View {
    HStack(spacing: 0) {
      stat(value: "\(artistCount)", label: artistCount == 1 ? "Artist" : "Artists")
      Divider().frame(height: 30)
      stat(value: "\(artworkCount)", label: artworkCount == 1 ? "Artwork" : "Artworks")
      Divider().frame(height: 30)
      stat(value: "\(totalUpvotes)", label: totalUpvotes == 1 ? "Like" : "Likes")
    }
    .padding(.vertical, 12)
    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Color.appDivider, lineWidth: 1)
    )
  }

  private func stat(value: String, label: String) -> some View {
    VStack(spacing: 2) {
      Text(value)
        .font(.system(size: 18, weight: .bold))
        .monospacedDigit()
      Text(label)
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
  }
}

private struct FeaturedArtCard: View {
  let art: GalleryArt
  let artist: GalleryArtist
  var body: some View {
    ZStack(alignment: .bottomLeading) {
      Group {
        if let url = art.imageURL {
          LoadingImage(
            url: url, cornerRadius: 16, showsLoading: false, lowResURL: art.blurPreviewURL,
            transparentBackground: true)
        } else {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(.tertiarySystemFill))
        }
      }
      .aspectRatio(4 / 5, contentMode: .fill)
      .frame(maxWidth: .infinity)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
      LinearGradient(
        colors: [.clear, .black.opacity(0.7)],
        startPoint: .center, endPoint: .bottom
      )
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .allowsHitTesting(false)
      VStack(alignment: .leading, spacing: 4) {
        Text("FEATURED ART")
          .font(.system(size: 11, weight: .bold))
          .foregroundColor(.white.opacity(0.85))
          .tracking(0.6)
        Text(artist.name)
          .font(.system(size: 22, weight: .bold))
          .foregroundColor(.white)
          .lineLimit(1)
        if let upvotes = art.upvotes, upvotes > 0 {
          Label("\(upvotes)", systemImage: "heart.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white.opacity(0.9))
            .padding(.top, 2)
        }
      }
      .padding(20)
    }
  }
}

private struct GalleryArtPreview: View {
  let art: GalleryArt
  let artist: GalleryArtist

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ArtThumbnail(art: art)
        .frame(width: 220, height: 220)
      VStack(alignment: .leading, spacing: 4) {
        Text(artist.name)
          .font(.system(size: 17, weight: .semibold))
          .lineLimit(1)
        if let upvotes = art.upvotes, upvotes > 0 {
          Label("\(upvotes) likes", systemImage: "heart.fill")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(14)
    .frame(width: 248, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}

private struct ArtistCircleCard: View {
  let artist: GalleryArtist
  var body: some View {
    VStack(spacing: 8) {
      ZStack {
        if let art = artist.arts?.first, let url = art.imageURL {
          LoadingImage(
            url: url, cornerRadius: 100, showsLoading: false, lowResURL: art.blurPreviewURL,
            transparentBackground: true)
        } else {
          Circle()
            .fill(
              LinearGradient(
                colors: [Color.appAccent.opacity(0.85), Color.purple.opacity(0.85)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay(
              Text(initials(artist.name))
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
            )
        }
      }
      .frame(width: 96, height: 96)
      .clipShape(Circle())
      .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
      Text(artist.name)
        .font(.system(size: 13, weight: .medium))
        .foregroundColor(.primary)
        .lineLimit(2)
        .multilineTextAlignment(.center)
        .frame(width: 100)
    }
  }
  private func initials(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    guard let first = trimmed.first else { return "?" }
    return String(first).uppercased()
  }
}

private struct ArtistListRow: View {
  let artist: GalleryArtist
  var body: some View {
    HStack(spacing: 14) {
      Group {
        if let art = artist.arts?.first, let url = art.imageURL {
          LoadingImage(
            url: url, cornerRadius: 100, showsLoading: false, lowResURL: art.blurPreviewURL,
            transparentBackground: true)
        } else {
          Circle()
            .fill(
              LinearGradient(
                colors: [Color.appAccent.opacity(0.85), Color.purple.opacity(0.85)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay(
              Text(String(artist.name.first ?? "?").uppercased())
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            )
        }
      }
      .frame(width: 50, height: 50)
      .clipShape(Circle())
      VStack(alignment: .leading, spacing: 2) {
        Text(artist.name)
          .font(.system(size: 16, weight: .medium))
          .foregroundColor(.primary)
          .lineLimit(1)
        Text("\(artist.arts?.count ?? 0) artworks")
          .font(.system(size: 13))
          .foregroundColor(.secondary)
      }
      Spacer()
      Image(systemName: "chevron.right")
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.secondary.opacity(0.6))
    }
    .padding(.vertical, 10)
    .contentShape(Rectangle())
  }
}
