import SwiftUI

struct DownloadedSongsView: View {
  @StateObject private var downloads = DownloadManager.shared
  @StateObject private var recentlyPlayed = RecentlyPlayedStore.shared
  @EnvironmentObject var audioManager: AudioPlayerManager
  @State private var localSongs: [Song] = []
  @State private var scrollOffset: CGFloat = 0
  var body: some View {
    GeometryReader { geo in
      ScrollView {
        if localSongs.isEmpty {
          emptyState
            .frame(width: geo.size.width, height: geo.size.height - 100)
        } else {
          VStack(spacing: 18) {
            heroHeader(width: geo.size.width)
            VStack(spacing: 4) {
              Text("Downloaded")
                .font(.title2.bold())
              Text("\(localSongs.count) songs")
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            actionButtons
              .padding(.horizontal)
            LazyVStack(spacing: 0) {
              ForEach(localSongs) { song in
                Button {
                  audioManager.play(song: song, context: localSongs)
                } label: {
                  SongRow(song: song, size: .regular)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .buttonStyle(PressableButtonStyle())
                Divider().padding(.leading, 76)
              }
            }
          }
          .padding(.bottom, 16)
          .background(
            GeometryReader { proxy in
              Color.clear.preference(
                key: DownloadedScrollOffsetKey.self,
                value: proxy.frame(in: .named("downloadedScroll")).minY
              )
            }
          )
        }
      }
      .coordinateSpace(name: "downloadedScroll")
      .onPreferenceChange(DownloadedScrollOffsetKey.self) { scrollOffset = $0 }
    }
    .navigationTitle(scrollOffset < -180 ? "Downloaded" : "")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(scrollOffset < -180 ? .visible : .hidden, for: .navigationBar)
    .animation(.easeInOut(duration: 0.2), value: scrollOffset < -180)
    .refreshable { refresh() }
    .onAppear { refresh() }
    .onChange(of: downloads.downloadedIDs) { refresh() }
  }
  private var emptyState: some View {
    VStack(spacing: 8) {
      Image(systemName: "arrow.down.circle")
        .font(.system(size: 36))
        .foregroundColor(.secondary)
      Text("No downloads")
        .foregroundColor(.secondary)
      Text("Use the menu on a song to download it")
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.top, 4)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
  @ViewBuilder
  private func heroHeader(width: CGFloat) -> some View {
    let baseSize: CGFloat = 240
    let stretch = max(0, scrollOffset)
    let shrink = max(0, -scrollOffset * 0.4)
    let size = max(140, baseSize + stretch * 0.6 - shrink)
    mosaicArtwork
      .frame(width: size, height: size)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
      .frame(width: width)
      .padding(.top, 12)
  }
  @ViewBuilder
  private var mosaicArtwork: some View {
    let arts = Array(localSongs.prefix(4).compactMap { $0.imageURL })
    if arts.count >= 4 {
      LazyVGrid(
        columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)],
        spacing: 0
      ) {
        ForEach(0..<4, id: \.self) { i in
          LoadingImage(url: arts[i], cornerRadius: 0)
            .aspectRatio(1, contentMode: .fill)
        }
      }
    } else if let url = arts.first {
      LoadingImage(url: url, cornerRadius: 0)
    } else {
      LinearGradient(
        colors: [Color.appAccent.opacity(0.85), Color.purple.opacity(0.85)],
        startPoint: .topLeading, endPoint: .bottomTrailing
      )
      .overlay(
        Image(systemName: "arrow.down.circle.fill")
          .font(.system(size: 64, weight: .medium))
          .foregroundColor(.white.opacity(0.85))
      )
    }
  }
  private var actionButtons: some View {
    HStack(spacing: 12) {
      Button {
        if let first = localSongs.first {
          audioManager.playInOrder(song: first, context: localSongs)
        }
      } label: {
        actionLabel(symbol: "play.fill", text: "Play")
      }
      .buttonStyle(PressableButtonStyle())
      Button {
        audioManager.playShuffled(from: localSongs)
      } label: {
        actionLabel(symbol: "shuffle", text: "Shuffle")
      }
      .buttonStyle(PressableButtonStyle())
    }
  }
  private func actionLabel(symbol: String, text: String) -> some View {
    HStack(spacing: 6) {
      Image(systemName: symbol)
      Text(text).fontWeight(.semibold)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
    .foregroundColor(.appAccent)
    .background(Color(.tertiarySystemFill))
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
  private func refresh() {
    let ids = downloads.downloadedIDs
    let cached = recentlyPlayed.playlists.flatMap { $0.songListDTOs ?? [] }
    var seen = Set<String>()
    var matched: [Song] = []
    for song in cached where ids.contains(song.id) && !seen.contains(song.id) {
      matched.append(song)
      seen.insert(song.id)
    }
    localSongs = matched
  }
}

private struct DownloadedScrollOffsetKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
