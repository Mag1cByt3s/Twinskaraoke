import SwiftUI

struct BrowseSongCollectionView: View {
    let title: String
    let songs: [Song]
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
    @State private var scrollOffset: CGFloat = 0

    private var showsArtwork: Bool {
        songs.count <= 200
    }

    private func usesWideOverview(availableWidth: CGFloat) -> Bool {
        AM.Layout.usesWideCanvas(
            horizontalSizeClass: horizontalSizeClass,
            availableWidth: availableWidth
        )
    }

    private var reduceMotion: Bool {
        AppMotion.reduceMotion(
            systemReduceMotion: systemReduceMotion,
            respectPreference: respectReducedMotion
        )
    }

    init(title: String, songs: [Song]) {
        self.title = title
        self.songs = songs
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                collectionOverview(width: geo.size.width)
                    .tabBarBottomPadding()
                    .animation(
                        reduceMotion ? nil : AppMotion.spring(response: 0.34, dampingFraction: 0.84),
                        value: songs.count
                    )
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: BrowseScrollOffsetKey.self,
                                value: proxy.frame(in: .named("browseScroll")).minY
                            )
                        }
                    )
            }
            .smoothScrolling()
            .coordinateSpace(name: "browseScroll")
            .onPreferenceChange(BrowseScrollOffsetKey.self) { scrollOffset = quantizedScrollOffset($0) }
        }
        .navigationTitle(scrollOffset < -180 ? title : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(scrollOffset < -180 ? .visible : .hidden, for: .navigationBar)
        .animation(
            reduceMotion ? nil : AppMotion.spring(response: 0.34, dampingFraction: 0.84),
            value: scrollOffset < -180
        )
    }

    @ViewBuilder
    private func collectionOverview(width: CGFloat) -> some View {
        if usesWideOverview(availableWidth: width) {
            wideCollectionOverview
        } else {
            compactCollectionOverview(width: width)
        }
    }

    private func compactCollectionOverview(width: CGFloat) -> some View {
        VStack(spacing: 18) {
            parallaxHero(width: width)
            collectionTitleBlock(alignment: .center)
            songsContent()
        }
    }

    private var wideCollectionOverview: some View {
        HStack(alignment: .top, spacing: AM.Spacing.xxl) {
            VStack(alignment: .leading, spacing: AM.Spacing.l) {
                heroArtwork
                    .frame(width: 280, height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous))
                    .amShadow(AM.Shadow.heroIdle)
                collectionTitleBlock(alignment: .leading)
                if !songs.isEmpty {
                    actionButtons(horizontalPadding: 0)
                }
            }
            .frame(width: 320, alignment: .topLeading)

            songsContent(isWideOverview: true, rowHorizontalPadding: 0)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: 1120, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.horizontal, AM.Spacing.screenMargin)
        .padding(.top, AM.Spacing.m)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("BrowseSongCollection.WideOverview")
    }

    private func play(_ song: Song) {
        AppHaptic.selection.play()
        AudioPlayerManager.shared.play(song: song, context: songs)
    }

    @ViewBuilder
    private func parallaxHero(width _: CGFloat) -> some View {
        let baseSize: CGFloat = 240
        let stretch = reduceMotion ? 0 : max(0, scrollOffset)
        let shrink = reduceMotion ? 0 : max(0, -scrollOffset * 0.4)
        let size = max(140, baseSize + stretch * 0.6 - shrink)
        let yOffset = reduceMotion ? 0 : (scrollOffset > 0 ? -scrollOffset / 2 : 0)
        heroArtwork
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous))
            .amShadow(AM.Shadow.heroIdle)
            .offset(y: yOffset)
            .frame(maxWidth: .infinity)
            .frame(height: baseSize)
            .padding(.top, 8)
    }

    private func collectionTitleBlock(alignment: TextAlignment) -> some View {
        VStack(alignment: alignment == .leading ? .leading : .center, spacing: 4) {
            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(alignment)
            Text(songCountText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
        .padding(.horizontal, alignment == .leading ? 0 : AM.Spacing.screenMargin)
    }

    private var songCountText: String {
        songs.count == 1 ? "1 song" : "\(songs.count) songs"
    }

    @ViewBuilder
    private var heroArtwork: some View {
        let artURL = songs.first(where: { $0.hasOwnArtwork })?.imageURL ?? FallbackArtProvider.shared.randomURL
        RemoteArtworkImage(url: artURL, cornerRadius: 0, contentMode: .fill)
    }

    @ViewBuilder
    private func songsContent(
        isWideOverview: Bool = false,
        rowHorizontalPadding: CGFloat = AM.Spacing.screenMargin
    ) -> some View {
        if !songs.isEmpty {
            VStack(spacing: 0) {
                if !isWideOverview {
                    actionButtons()
                }
                LazyVStack(spacing: 0) {
                    ForEach(songs) { song in
                        Button {
                            play(song)
                        } label: {
                            SongRow(song: song, size: .regular, showsArtwork: showsArtwork)
                                .padding(.horizontal, rowHorizontalPadding)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                                .songRowAccessibility(song: song) {
                                    play(song)
                                }
                        }
                        .buttonStyle(PressableButtonStyle(scale: 0.985, dim: 0.78, haptic: .selection))
                        .accessibilityHint("Starts playback.")
                        .accessibilityIdentifier("BrowseSongCollection.song.\(song.id)")
                        Divider().padding(.leading, rowHorizontalPadding + (showsArtwork ? 60 : 12))
                    }
                }
            }
        } else {
            MusicEmptyState(
                title: "No Songs",
                message: "This collection does not have playable songs yet."
            )
            .padding(.top, AM.Spacing.s)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
        }
    }

    private func actionButtons(horizontalPadding: CGFloat = AM.Spacing.screenMargin) -> some View {
        HStack(spacing: AM.Spacing.m) {
            Button {
                if let first = songs.first {
                    AppHaptic.medium.play()
                    AudioPlayerManager.shared.playInOrder(song: first, context: songs)
                }
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.08))
                    .foregroundStyle(Color.appAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.82))
            .accessibilityLabel("Play \(title)")
            .accessibilityValue("\(songs.count) songs")
            Button {
                AppHaptic.selection.play()
                AudioPlayerManager.shared.playShuffled(from: songs)
            } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.08))
                    .foregroundStyle(Color.appAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.82))
            .accessibilityLabel("Shuffle \(title)")
            .accessibilityValue("\(songs.count) songs")
        }
        .padding(.horizontal, horizontalPadding)
    }
}

private struct BrowseScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private func quantizedScrollOffset(_ offset: CGFloat) -> CGFloat {
    (offset / 8).rounded() * 8
}
