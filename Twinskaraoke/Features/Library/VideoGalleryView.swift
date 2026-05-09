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

struct GalleryVideo: Codable, Identifiable, Equatable {
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

private struct VideosResponse: Codable {
  let items: [GalleryVideo]
  let totalCount: Int
  let page: Int
  let pageSize: Int
}

class VideoGalleryViewModel: ObservableObject {
  @Published var videos: [GalleryVideo] = []
  @Published var isLoading = false
  @Published var canLoadMore = true
  private var page = 1
  private let pageSize = 25
  func fetchInitial() {
    guard videos.isEmpty else { return }
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
    guard let url = URL(string: urlString) else { return }
    isLoading = true
    var request = URLRequest(url: url)
    GuestIdentity.applyIfNeeded(to: &request)
    URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
      guard let self = self else { return }
      if let data, let decoded = try? JSONDecoder().decode(VideosResponse.self, from: data) {
        DispatchQueue.main.async {
          if reset { self.videos = decoded.items } else { self.videos += decoded.items }
          self.page += 1
          self.canLoadMore = self.videos.count < decoded.totalCount
          self.isLoading = false
        }
      } else {
        DispatchQueue.main.async { self.isLoading = false }
      }
    }.resume()
  }
}

struct VideoGalleryView: View {
  @StateObject private var viewModel = VideoGalleryViewModel()
  private let cols = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
  var body: some View {
    ScrollView {
      if viewModel.videos.isEmpty && viewModel.isLoading {
        LoadingIndicator(size: 64)
          .frame(maxWidth: .infinity)
          .padding(.top, 120)
      } else if let featured = viewModel.videos.first {
        VStack(alignment: .leading, spacing: 24) {
          NavigationLink {
            VideoPlayerScreen(video: featured)
          } label: {
            FeaturedVideoCard(video: featured)
          }
          .buttonStyle(PressableButtonStyle())
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
                  .buttonStyle(PressableButtonStyle())
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
    .navigationTitle("Video Gallery")
    .navigationBarTitleDisplayMode(.large)
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

class SimilarVideosViewModel: ObservableObject {
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
      guard let self = self else { return }
      if let data, let decoded = try? JSONDecoder().decode(VideosResponse.self, from: data) {
        DispatchQueue.main.async {
          self.videos = decoded.items.filter { $0.id != currentID }
          self.isLoading = false
        }
      } else {
        DispatchQueue.main.async { self.isLoading = false }
      }
    }.resume()
  }
}

struct VideoPlayerScreen: View {
  let video: GalleryVideo
  @State private var player: AVPlayer?
  @StateObject private var similar = SimilarVideosViewModel()
  @EnvironmentObject var audioManager: AudioPlayerManager
  private let audioWillPlay = NotificationCenter.default.publisher(
    for: MediaPlaybackCoordinator.audioWillPlay)
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
        VStack(alignment: .leading, spacing: 10) {
          Text(video.songTitle ?? video.name)
            .font(.title3.bold())
          Text(video.name)
            .font(.system(size: 14))
            .foregroundColor(.secondary)
          if let creator = video.createdBy, !creator.isEmpty {
            Label(creator, systemImage: "person.fill")
              .font(.system(size: 13))
              .foregroundColor(.secondary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        if !similar.videos.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            Text("Similar Videos")
              .font(.system(size: 20, weight: .bold))
              .padding(.horizontal, 16)
            LazyVStack(spacing: 0) {
              ForEach(Array(similar.videos.enumerated()), id: \.element.id) { idx, item in
                NavigationLink {
                  VideoPlayerScreen(video: item)
                } label: {
                  SimilarVideoRow(video: item)
                }
                .buttonStyle(.plain)
                if idx < similar.videos.count - 1 {
                  Divider().padding(.leading, 16 + 140 + 12)
                }
              }
            }
          }
          .padding(.top, 8)
          .padding(.bottom, 16)
        } else if similar.isLoading {
          LoadingIndicator(size: 32)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
      }
    }
    .navigationTitle(video.songTitle ?? "Video")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      if player == nil, let url = video.streamURL ?? video.embedURL {
        audioManager.pauseIfPlaying()
        let p = AVPlayer(url: url)
        NotificationCenter.default.post(
          name: MediaPlaybackCoordinator.videoWillPlay, object: nil)
        p.play()
        player = p
      }
      similar.fetch(excluding: video.id)
    }
    .onDisappear {
      player?.pause()
      player = nil
    }
    .onReceive(audioWillPlay) { _ in
      player?.pause()
    }
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
