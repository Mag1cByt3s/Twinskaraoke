import AVKit
import Combine
import SwiftUI

#if canImport(UIKit)
  import UIKit

  struct FullscreenAVPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
      let vc = AVPlayerViewController()
      vc.player = player
      vc.allowsPictureInPicturePlayback = true
      vc.canStartPictureInPictureAutomaticallyFromInline = true
      vc.entersFullScreenWhenPlaybackBegins = false
      vc.exitsFullScreenWhenPlaybackEnds = false
      vc.showsPlaybackControls = true
      vc.videoGravity = .resizeAspect
      return vc
    }
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
      if uiViewController.player !== player {
        uiViewController.player = player
      }
    }
  }
#endif

nonisolated struct GalleryVideo: Codable, Identifiable, Equatable, Sendable {
  let id: String
  let name: String
  let songTitle: String?
  let url: String?
  let thumbnailUrl: String?
  let createdBy: String?
  let createdDate: String?
  var thumbnailURL: URL? { thumbnailUrl.flatMap(URL.init(string:)) }
  var embedURL: URL? { url.flatMap(URL.init(string:)) }
  var streamURL: URL? {
    guard let thumb = thumbnailUrl, let comps = URLComponents(string: thumb),
      let host = comps.host
    else { return nil }
    let trimmed = thumb.replacingOccurrences(of: "/thumbnail.jpg", with: "")
    if let trimmedComps = URLComponents(string: trimmed), let path = Optional(trimmedComps.path),
      !path.isEmpty
    {
      return URL(string: "https://\(host)\(path)/playlist.m3u8")
    }
    return nil
  }
}

nonisolated private struct VideosResponse: Codable, Sendable {
  let items: [GalleryVideo]
  let totalCount: Int
  let page: Int
  let pageSize: Int
}

@MainActor
final class VideoGalleryViewModel: ObservableObject {
  @Published var videos: [GalleryVideo] = []
  @Published var isLoading = false
  @Published var errorMessage: String?
  @Published var canLoadMore = true
  private var page = 1
  private let pageSize = 25

  func fetchInitial() {
    guard videos.isEmpty else { return }
    page = 1
    canLoadMore = true
    load(reset: true)
  }

  func refresh() {
    page = 1
    canLoadMore = true
    load(reset: true)
  }

  func loadMoreIfNeeded(current: GalleryVideo) {
    guard let idx = videos.firstIndex(of: current) else { return }
    if idx >= videos.count - 5 && !isLoading && canLoadMore {
      load(reset: false)
    }
  }

  private func load(reset: Bool) {
    let urlString =
      "\(StorageHost.api)/api/videos?page=\(page)&pageSize=\(pageSize)&sortBy=UploadedAt&sortDescending=True"
    guard let url = URL(string: urlString) else {
      errorMessage = "The video gallery endpoint is unavailable."
      return
    }
    isLoading = true
    if reset { errorMessage = nil }
    var request = URLRequest(url: url)
    GuestIdentity.applyIfNeeded(to: &request)
    URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      Task { @MainActor [weak self, data, response, error, reset] in
        self?.applyVideosResponse(data, response: response, error: error, reset: reset)
      }
    }.resume()
  }

  private func applyVideosResponse(
    _ data: Data?,
    response: URLResponse?,
    error: Error?,
    reset: Bool
  ) {
    defer { isLoading = false }

    if let error {
      errorMessage = error.localizedDescription
      return
    }
    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
      errorMessage = "The server returned HTTP \(http.statusCode)."
      return
    }
    guard let data, let decoded = try? JSONDecoder().decode(VideosResponse.self, from: data) else {
      errorMessage = "The video response could not be read."
      return
    }

    if reset {
      videos = decoded.items
    } else {
      videos += decoded.items
    }
    page += 1
    canLoadMore = videos.count < decoded.totalCount
    errorMessage = nil
  }
}

struct VideoGalleryView: View {
  @StateObject private var viewModel = VideoGalleryViewModel()
  private let cols = AM.Layout.adaptiveGridColumns(minimum: 164, spacing: 16)
  var body: some View {
    ScrollView {
      if viewModel.videos.isEmpty && viewModel.isLoading {
        VideoGallerySkeleton(cols: cols)
          .padding(.top, 16)
      } else if let message = viewModel.errorMessage, viewModel.videos.isEmpty {
        VideoGalleryStateView(
          systemImage: "wifi.exclamationmark",
          title: "Couldn't Load Videos",
          message: message,
          buttonTitle: "Try Again"
        ) {
          viewModel.refresh()
        }
        .frame(maxWidth: .infinity, minHeight: 420)
      } else if viewModel.videos.isEmpty {
        VideoGalleryStateView(
          systemImage: "play.rectangle",
          title: "No Videos",
          message: "Recent Twinskaraoke videos will appear here.",
          buttonTitle: "Refresh"
        ) {
          viewModel.refresh()
        }
        .frame(maxWidth: .infinity, minHeight: 420)
      } else if let featured = viewModel.videos.first {
        VStack(alignment: .leading, spacing: 24) {
          NavigationLink {
            VideoPlayerScreen(video: featured)
          } label: {
            FeaturedVideoCard(video: featured)
          }
          .buttonStyle(PressableButtonStyle(haptic: .selection))
          .contextMenu {
            VideoActionsMenu(video: featured)
          } preview: {
            VideoContextPreview(video: featured, isFeatured: true)
          }
          .padding(.horizontal, 16)
          if viewModel.videos.count > 1 {
            VStack(alignment: .leading, spacing: 12) {
              HStack(alignment: .firstTextBaseline) {
                Text("Recent Videos")
                  .font(.system(size: 22, weight: .bold))
                Spacer()
              }
              .padding(.horizontal, 16)
              LazyVGrid(columns: cols, spacing: 20) {
                ForEach(viewModel.videos.dropFirst()) { video in
                  NavigationLink {
                    VideoPlayerScreen(video: video)
                  } label: {
                    VideoGalleryCell(video: video)
                  }
                  .buttonStyle(PressableButtonStyle(haptic: .selection))
                  .contextMenu {
                    VideoActionsMenu(video: video)
                  } preview: {
                    VideoContextPreview(video: video)
                  }
                  .onAppear { viewModel.loadMoreIfNeeded(current: video) }
                }
              }
              .padding(.horizontal, 16)
            }
          }
          if viewModel.isLoading {
            LoadingIndicator(size: 28)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 16)
          }
        }
        .padding(.vertical, 16)
      }
    }
    .scrollIndicators(.hidden)
    .musicScreenBackground()
    .navigationTitle("Video Gallery")
    .navigationBarTitleDisplayMode(.large)
    .refreshable {
      AppHaptic.selection.play()
      viewModel.refresh()
    }
    .onAppear { viewModel.fetchInitial() }
  }
}

private struct VideoThumbnail: View {
  let url: URL?
  var cornerRadius: CGFloat = 10
  var body: some View {
    Color.clear
      .aspectRatio(16 / 9, contentMode: .fit)
      .overlay(
        Group {
          if let url {
            LoadingImage(url: url, cornerRadius: cornerRadius, showsLoading: false)
          } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
              .fill(Color(.tertiarySystemFill))
          }
        }
      )
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }
}

private struct FeaturedVideoCard: View {
  let video: GalleryVideo
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ZStack(alignment: .bottomLeading) {
        VideoThumbnail(url: video.thumbnailURL, cornerRadius: 14)
          .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        LinearGradient(
          colors: [.clear, .black.opacity(0.55)],
          startPoint: .center, endPoint: .bottom
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .allowsHitTesting(false)
        HStack(spacing: 8) {
          Image(systemName: "play.circle.fill")
            .font(.system(size: 28))
            .foregroundColor(.white)
          VStack(alignment: .leading, spacing: 2) {
            Text("LATEST VIDEO")
              .font(.system(size: 11, weight: .bold))
              .foregroundColor(.white.opacity(0.85))
              .tracking(0.5)
            Text(video.songTitle ?? video.name)
              .font(.system(size: 17, weight: .semibold))
              .foregroundColor(.white)
              .lineLimit(2)
              .multilineTextAlignment(.leading)
          }
        }
        .padding(16)
      }
    }
  }
}

private struct VideoGalleryCell: View {
  let video: GalleryVideo
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      VideoThumbnail(url: video.thumbnailURL, cornerRadius: 10)
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
      VStack(alignment: .leading, spacing: 2) {
        Text(video.songTitle ?? video.name)
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(.primary)
          .lineLimit(1)
          .truncationMode(.tail)
        if let creator = video.createdBy, !creator.isEmpty {
          Text(creator)
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct VideoGallerySkeleton: View {
  let cols: [GridItem]

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      VStack(alignment: .leading, spacing: 10) {
        VideoPlaceholderThumbnail(cornerRadius: 14)
          .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
        RoundedRectangle(cornerRadius: 3, style: .continuous)
          .fill(Color.appPlaceholderSecondary)
          .frame(width: 220, height: 14)
        RoundedRectangle(cornerRadius: 3, style: .continuous)
          .fill(Color.appPlaceholderPrimary)
          .frame(width: 128, height: 11)
      }
      .padding(.horizontal, 16)

      VStack(alignment: .leading, spacing: 12) {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(Color.appPlaceholderSecondary)
          .frame(width: 152, height: 20)
          .padding(.horizontal, 16)
        LazyVGrid(columns: cols, spacing: 20) {
          ForEach(0..<6, id: \.self) { _ in
            VStack(alignment: .leading, spacing: 8) {
              VideoPlaceholderThumbnail(cornerRadius: 10)
                .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
              RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.appPlaceholderSecondary)
                .frame(height: 12)
              RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.appPlaceholderPrimary)
                .frame(width: 78, height: 10)
            }
          }
        }
        .padding(.horizontal, 16)
      }
    }
    .redacted(reason: .placeholder)
    .accessibilityLabel("Loading videos")
  }
}

private struct VideoPlaceholderThumbnail: View {
  var cornerRadius: CGFloat

  var body: some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      .fill(
        LinearGradient(
          colors: [
            Color.appPlaceholderSecondary,
            Color.appPlaceholderPrimary,
            Color.appPlaceholderQuaternary,
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .aspectRatio(16 / 9, contentMode: .fit)
      .overlay {
        Image(systemName: "play.fill")
          .font(.system(size: 18, weight: .bold))
          .foregroundColor(.appAccent.opacity(0.82))
      }
  }
}

private struct VideoGalleryStateView: View {
  let systemImage: String
  let title: String
  let message: String
  let buttonTitle: String
  let onRefresh: () -> Void
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var isPulsing = false
  @State private var hasAppeared = false

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  var body: some View {
    VStack(spacing: AM.Spacing.xl) {
      ZStack {
        RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous)
          .fill(
            LinearGradient(
              colors: [
                Color(red: 0.08, green: 0.09, blue: 0.12),
                Color.appAccent.opacity(0.92),
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .frame(width: 168, height: 104)
          .shadow(color: Color.appAccent.opacity(0.24), radius: 16, y: 8)

        RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous)
          .strokeBorder(.white.opacity(0.22), lineWidth: 1)
          .frame(width: 126, height: 70)
          .scaleEffect(reduceMotion ? 1 : (isPulsing ? 1.06 : 0.96))
          .opacity(isPulsing ? 0.55 : 1)

        Image(systemName: systemImage)
          .font(.system(size: 42, weight: .semibold))
          .foregroundColor(.white)
          .symbolRenderingMode(.hierarchical)
      }
      .scaleEffect(reduceMotion ? 1 : (hasAppeared ? 1 : 0.94))
      .opacity(hasAppeared ? 1 : 0)

      VStack(spacing: AM.Spacing.s) {
        Text(title)
          .font(.system(size: 23, weight: .bold))
          .foregroundColor(.primary)
          .multilineTextAlignment(.center)
        Text(message)
          .font(.system(size: 15))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .lineLimit(3)
      }
      .frame(maxWidth: 340)

      Button {
        AppHaptic.selection.play()
        onRefresh()
      } label: {
        Label(buttonTitle, systemImage: "arrow.clockwise")
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.white)
          .padding(.horizontal, AM.Spacing.xl)
          .padding(.vertical, 11)
          .background(Color.appAccent, in: Capsule())
          .shadow(color: Color.appAccent.opacity(0.28), radius: 10, y: 4)
      }
      .buttonStyle(PressableButtonStyle(scale: 0.94, dim: 0.78, haptic: .selection))

      VStack(spacing: AM.Spacing.s) {
        VideoGalleryHintRow(
          systemImage: "play.rectangle.on.rectangle",
          title: "Karaoke videos",
          message: "New uploads from the Twinskaraoke feed appear here."
        )
        VideoGalleryHintRow(
          systemImage: "wifi",
          title: "Refresh the feed",
          message: "Pull down or tap retry when the video service is slow."
        )
      }
      .frame(maxWidth: 360)
      .opacity(hasAppeared ? 1 : 0)
      .offset(y: reduceMotion ? 0 : (hasAppeared ? 0 : 10))
    }
    .padding(.horizontal, AM.Spacing.screenMargin)
    .onAppear {
      guard !reduceMotion else {
        hasAppeared = true
        isPulsing = false
        return
      }
      withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
        hasAppeared = true
      }
      withAnimation(.easeInOut(duration: 1.45).repeatForever(autoreverses: true)) {
        isPulsing = true
      }
    }
    .onChange(of: reduceMotion) { _, reduceMotion in
      if reduceMotion {
        withAnimation(nil) {
          isPulsing = false
          hasAppeared = true
        }
      } else {
        withAnimation(.easeInOut(duration: 1.45).repeatForever(autoreverses: true)) {
          isPulsing = true
        }
      }
    }
    .accessibilityElement(children: .contain)
  }
}

private struct VideoGalleryHintRow: View {
  let systemImage: String
  let title: String
  let message: String

  var body: some View {
    HStack(spacing: AM.Spacing.m) {
      Image(systemName: systemImage)
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.appAccent)
        .frame(width: 30, height: 30)
        .background(Color.appAccent.opacity(0.12), in: Circle())
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(.primary)
        Text(message)
          .font(.system(size: 13))
          .foregroundColor(.secondary)
          .lineLimit(2)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, AM.Spacing.m)
    .padding(.vertical, AM.Spacing.s)
    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
  }
}

private extension GalleryVideo {
  var displayTitle: String { songTitle ?? name }
  var shareURL: URL? { embedURL ?? streamURL ?? thumbnailURL }
  var trimmedCreator: String? { videoTrimmed(createdBy) }
  var trimmedCreatedDate: String? { videoTrimmed(createdDate) }
}

private func videoTrimmed(_ value: String?) -> String? {
  guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
    return nil
  }
  return trimmed
}

private struct VideoActionsMenu: View {
  let video: GalleryVideo

  var body: some View {
    if let url = video.shareURL {
      ShareLink(item: url) {
        Label("Share Video", systemImage: "square.and.arrow.up")
      }

      #if canImport(UIKit)
        Button {
          AppHaptic.selection.play()
          UIPasteboard.general.url = url
        } label: {
          Label("Copy Link", systemImage: "link")
        }
      #endif
    } else {
      Label("No Link Available", systemImage: "link.badge.plus")
    }
  }
}

private struct VideoContextPreview: View {
  let video: GalleryVideo
  var isFeatured = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VideoThumbnail(url: video.thumbnailURL, cornerRadius: 12)
        .frame(width: 252)
      VStack(alignment: .leading, spacing: 4) {
        if isFeatured {
          Text("Latest Video")
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.appAccent)
        }
        Text(video.displayTitle)
          .font(.system(size: 17, weight: .semibold))
          .foregroundColor(.primary)
          .lineLimit(2)
        if let creator = video.createdBy, !creator.isEmpty {
          Text(creator)
            .font(.system(size: 14))
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
      }
    }
    .padding(16)
    .frame(width: 284, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}

@MainActor
final class SimilarVideosViewModel: ObservableObject {
  @Published var videos: [GalleryVideo] = []
  @Published var isLoading = false

  func fetch(excluding currentID: String) {
    guard videos.isEmpty else { return }
    let urlString =
      "\(StorageHost.api)/api/videos?startIndex=0&pageSize=20&sortBy=CreatedAt&sortDescending=true"
    guard let url = URL(string: urlString) else { return }
    isLoading = true
    var request = URLRequest(url: url)
    GuestIdentity.applyIfNeeded(to: &request)
    URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
      Task { @MainActor [weak self, data, currentID] in
        self?.applySimilarVideosResponse(data, excluding: currentID)
      }
    }.resume()
  }

  private func applySimilarVideosResponse(_ data: Data?, excluding currentID: String) {
    defer { isLoading = false }

    guard let data, let decoded = try? JSONDecoder().decode(VideosResponse.self, from: data) else {
      return
    }

    videos = decoded.items.filter { $0.id != currentID }
  }
}

struct VideoPlayerScreen: View {
  let video: GalleryVideo
  @State private var player: AVPlayer?
  @State private var appeared = false
  @StateObject private var similar = SimilarVideosViewModel()
  @EnvironmentObject var audioManager: AudioPlayerManager
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  private let audioWillPlay = NotificationCenter.default.publisher(
    for: MediaPlaybackCoordinator.audioWillPlay)
  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }
  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        Group {
          #if canImport(UIKit)
            if let player {
              FullscreenAVPlayer(player: player)
            } else {
              ZStack {
                Color.black
                ProgressView().tint(.white)
              }
            }
          #else
            if let player {
              VideoPlayer(player: player)
            } else {
              ZStack {
                Color.black
                ProgressView()
              }
            }
          #endif
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 0, style: .continuous))
        .contextMenu {
          VideoActionsMenu(video: video)
        } preview: {
          VideoContextPreview(video: video, isFeatured: true)
        }

        VideoPlayerInfoPanel(video: video)
          .padding(.horizontal, 16)
          .padding(.top, 18)
          .opacity(appeared ? 1 : 0)
          .offset(y: reduceMotion ? 0 : (appeared ? 0 : 14))

        if !similar.videos.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
              Text("Similar Videos")
                .font(.system(size: 20, weight: .bold))
              Spacer()
              Text("\(similar.videos.count)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            .padding(.horizontal, 16)
            LazyVStack(spacing: 0) {
              ForEach(Array(similar.videos.enumerated()), id: \.element.id) { idx, item in
                NavigationLink {
                  VideoPlayerScreen(video: item)
                } label: {
                  SimilarVideoRow(video: item)
                }
                .buttonStyle(PressableButtonStyle(haptic: .selection))
                .contextMenu {
                  VideoActionsMenu(video: item)
                } preview: {
                  VideoContextPreview(video: item)
                }
                if idx < similar.videos.count - 1 {
                  Divider().padding(.leading, 16 + 140 + 12)
                }
              }
            }
          }
          .padding(.top, 8)
          .padding(.bottom, 16)
          .opacity(appeared ? 1 : 0)
          .offset(y: reduceMotion ? 0 : (appeared ? 0 : 10))
        } else if similar.isLoading {
          LoadingIndicator(size: 32)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
      }
    }
    .musicScreenBackground()
    .navigationTitle(video.songTitle ?? "Video")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if let url = video.shareURL {
        ToolbarItem(placement: .topBarTrailing) {
          ShareLink(item: url) {
            Image(systemName: "square.and.arrow.up")
          }
          .accessibilityLabel("Share video")
        }
      }
    }
    .onAppear {
      startPlaybackIfNeeded()
      similar.fetch(excluding: video.id)
      guard !reduceMotion else {
        appeared = true
        return
      }
      withAnimation(.spring(response: 0.44, dampingFraction: 0.84)) {
        appeared = true
      }
    }
    .onChange(of: reduceMotion) { _, reduceMotion in
      if reduceMotion {
        withAnimation(nil) {
          appeared = true
        }
      }
    }
    .onDisappear {
      player?.pause()
      player = nil
    }
    .onReceive(audioWillPlay) { _ in
      player?.pause()
    }
  }

  private func startPlaybackIfNeeded() {
    guard player == nil, let url = video.streamURL ?? video.embedURL else { return }
    audioManager.pauseIfPlaying()
    let nextPlayer = AVPlayer(url: url)
    NotificationCenter.default.post(
      name: MediaPlaybackCoordinator.videoWillPlay, object: nil)
    nextPlayer.play()
    player = nextPlayer
    AppHaptic.light.play()
  }
}

private struct VideoPlayerInfoPanel: View {
  let video: GalleryVideo

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 6) {
        Label("Now Playing", systemImage: "play.circle.fill")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(Color.appAccent)
          .textCase(.uppercase)
        Text(video.displayTitle)
          .font(.system(size: 25, weight: .bold))
          .foregroundStyle(.primary)
          .lineLimit(3)
          .multilineTextAlignment(.leading)
        if video.name != video.displayTitle {
          Text(video.name)
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }

      VideoMetadataPills(video: video)

      VideoPlayerActionRow(video: video)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct VideoMetadataPills: View {
  let video: GalleryVideo

  var body: some View {
    HStack(spacing: 8) {
      if let creator = video.trimmedCreator {
        VideoMetadataPill(systemImage: "person.fill", title: creator)
      }
      if let date = video.trimmedCreatedDate {
        VideoMetadataPill(systemImage: "calendar", title: date)
      }
      if video.streamURL != nil {
        VideoMetadataPill(systemImage: "dot.radiowaves.left.and.right", title: "Stream")
      }
    }
  }
}

private struct VideoMetadataPill: View {
  let systemImage: String
  let title: String

  var body: some View {
    Label(title, systemImage: systemImage)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .minimumScaleFactor(0.82)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(Color.appControlInactiveFill, in: Capsule())
  }
}

private struct VideoPlayerActionRow: View {
  let video: GalleryVideo

  var body: some View {
    if let url = video.shareURL {
      HStack(spacing: 10) {
        ShareLink(item: url) {
          VideoActionButtonLabel(systemImage: "square.and.arrow.up", title: "Share")
        }
        .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78, haptic: .selection))

        #if canImport(UIKit)
          Button {
            AppHaptic.selection.play()
            UIPasteboard.general.url = url
          } label: {
            VideoActionButtonLabel(systemImage: "link", title: "Copy")
          }
          .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78))
        #endif
      }
    }
  }
}

private struct VideoActionButtonLabel: View {
  let systemImage: String
  let title: String

  var body: some View {
    Label(title, systemImage: systemImage)
      .font(.system(size: 15, weight: .semibold))
      .foregroundStyle(.primary)
      .lineLimit(1)
      .minimumScaleFactor(0.82)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
      .background(Color.appControlInactiveFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}

private struct SimilarVideoRow: View {
  let video: GalleryVideo
  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      VideoThumbnail(url: video.thumbnailURL, cornerRadius: 8)
        .frame(width: 140)
      VStack(alignment: .leading, spacing: 4) {
        Text(video.songTitle ?? video.name)
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(.primary)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
        if let creator = video.createdBy, !creator.isEmpty {
          Text(creator)
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
      }
      .padding(.top, 2)
      Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .contentShape(Rectangle())
  }
}
