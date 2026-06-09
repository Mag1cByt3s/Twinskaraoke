import SwiftUI

struct ArtDetailView: View {
  let art: GalleryArt
  let artist: GalleryArtist
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var showFullScreen = false
  @State private var saveStatus: ArtworkSaveStatus = .idle
  @State private var appeared = false
  private var fullResURL: URL? {
    art.fullHDImageURL ?? art.imageURL
  }
  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        ArtworkDetailHero(
          art: art,
          artist: artist,
          fullResURL: fullResURL,
          onOpen: openFullScreen,
          onSave: saveImage
        )
        .scaleEffect(reduceMotion ? 1 : (appeared ? 1 : 0.97))
        .opacity(appeared ? 1 : 0)

        VStack(alignment: .leading, spacing: 18) {
          ArtworkActionStrip(
            url: fullResURL,
            saveStatus: saveStatus,
            onOpen: openFullScreen,
            onSave: saveImage
          )

          ArtworkDetailMetadata(art: art)
        }
        .padding(.horizontal, 16)
        .offset(y: reduceMotion ? 0 : (appeared ? 0 : 16))
        .opacity(appeared ? 1 : 0)
      }
      .padding(.bottom, 24)
    }
    .navigationTitle(artist.name)
    .navigationBarTitleDisplayMode(.inline)
    .background {
      ArtworkDetailAmbientBackground(art: art)
        .ignoresSafeArea()
    }
    .toolbar {
      if let url = fullResURL {
        ToolbarItem(placement: .topBarTrailing) {
          ShareLink(item: url) {
            Image(systemName: "square.and.arrow.up")
          }
          .accessibilityLabel("Share artwork")
        }
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          saveImage()
        } label: {
          switch saveStatus {
          case .saving:
            ProgressView()
          case .success:
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
          case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
          case .idle:
            Image(systemName: "square.and.arrow.down")
          }
        }
        .disabled(saveStatus.isSaving)
        .accessibilityLabel(saveStatus.accessibilityLabel)
      }
    }
    .fullScreenCover(isPresented: $showFullScreen) {
      ZoomableImageViewer(
        url: fullResURL,
        lowResURL: art.blurPreviewURL,
        saveStatus: $saveStatus,
        onSave: saveImage,
        title: artist.name,
        subtitle: artist.socialLink
      )
    }
    .onAppear {
      guard !reduceMotion else {
        appeared = true
        return
      }
      withAnimation(.spring(response: 0.48, dampingFraction: 0.82)) {
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
    .onChange(of: saveStatus) { _, status in
      switch status {
      case .success:
        AppHaptic.success.play()
      case .failed:
        AppHaptic.error.play()
      case .saving, .idle:
        break
      }
    }
  }

  private func openFullScreen() {
    AppHaptic.medium.play()
    showFullScreen = true
  }

  private func saveImage() {
    guard !saveStatus.isSaving else { return }
    guard let url = fullResURL else { return }
    AppHaptic.selection.play()
    saveStatus = .saving
    URLSession.shared.dataTask(with: url) { data, _, error in
      DispatchQueue.main.async {
        #if canImport(UIKit)
          if let data, let image = UIImage(data: data) {
            ImageSaver.shared.save(image: image) { result in
              DispatchQueue.main.async {
                switch result {
                case .success:
                  saveStatus = .success
                case .failure(let err):
                  saveStatus = .failed(err.localizedDescription)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                  saveStatus = .idle
                }
              }
            }
            return
          }
        #endif
        saveStatus = .failed(error?.localizedDescription ?? "Couldn't save")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saveStatus = .idle }
      }
    }.resume()
  }
}

enum ArtworkSaveStatus: Equatable {
  case idle
  case saving
  case success
  case failed(String)

  var isSaving: Bool {
    if case .saving = self { return true }
    return false
  }

  var accessibilityLabel: String {
    switch self {
    case .saving:
      return "Saving artwork"
    case .success:
      return "Artwork saved"
    case .failed:
      return "Artwork save failed"
    case .idle:
      return "Save artwork"
    }
  }
}

private struct ArtworkDetailHero: View {
  let art: GalleryArt
  let artist: GalleryArtist
  let fullResURL: URL?
  let onOpen: () -> Void
  let onSave: () -> Void

  var body: some View {
    ZStack {
      ArtworkDetailAmbientBackground(art: art)

      LinearGradient(
        colors: [
          Color.appBackground.opacity(0.08),
          Color.appBackground.opacity(0.72),
          Color.appBackground
        ],
        startPoint: .top,
        endPoint: .bottom
      )

      VStack(spacing: 16) {
        Button(action: onOpen) {
          heroArtwork
        }
        .buttonStyle(PressableButtonStyle(scale: 0.985, dim: 0.86))
        .contextMenu {
          if let fullResURL {
            ShareLink(item: fullResURL) {
              Label("Share Artwork", systemImage: "square.and.arrow.up")
            }
          }
          Button(action: onSave) {
            Label("Save Artwork", systemImage: "square.and.arrow.down")
          }
          if let upvotes = art.upvotes, upvotes > 0 {
            Label("\(upvotes) likes", systemImage: "heart.fill")
          }
        } preview: {
          ArtworkDetailContextPreview(art: art, artist: artist)
        }

        VStack(spacing: 6) {
          Text(artist.name)
            .font(.system(size: 30, weight: .bold))
            .multilineTextAlignment(.center)
            .lineLimit(2)
          if let social = trimmed(artist.socialLink) {
            Text(social)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }

        HStack(spacing: 8) {
          if let upvotes = art.upvotes, upvotes > 0 {
            ArtworkDetailPill(systemImage: "heart.fill", title: "\(upvotes)", tint: .pink)
          }
          if trimmed(art.credit) != nil {
            ArtworkDetailPill(systemImage: "person.crop.square", title: "Credits", tint: .blue)
          }
          if fullResURL != nil {
            ArtworkDetailPill(systemImage: "photo", title: "HD", tint: Color.appAccent)
          }
        }
      }
      .padding(.horizontal, 22)
      .padding(.top, 28)
      .padding(.bottom, 26)
    }
    .frame(maxWidth: .infinity)
    .frame(minHeight: 430)
  }

  @ViewBuilder
  private var heroArtwork: some View {
    if let url = fullResURL {
      LoadingImage(
        url: url,
        cornerRadius: 20,
        contentMode: .fit,
        showsLoading: false,
        lowResURL: art.blurPreviewURL,
        transparentBackground: true
      )
      .aspectRatio(1, contentMode: .fit)
      .frame(maxWidth: 285)
      .shadow(color: Color.appHeroShadowPlaying, radius: 24, y: 12)
      .overlay(alignment: .bottomTrailing) {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 34, height: 34)
          .background(Color.black.opacity(0.46), in: Circle())
          .padding(12)
      }
    } else {
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(Color.appControlInactiveFill)
        .frame(maxWidth: 285)
        .aspectRatio(1, contentMode: .fit)
        .overlay {
          Image(systemName: "photo")
            .font(.system(size: 48, weight: .semibold))
            .foregroundStyle(.secondary)
        }
    }
  }
}

private struct ArtworkDetailAmbientBackground: View {
  let art: GalleryArt

  var body: some View {
    ZStack {
      Color.appBackground
      if let url = art.imageURL {
        LoadingImage(
          url: url,
          cornerRadius: 0,
          contentMode: .fill,
          showsLoading: false,
          lowResURL: art.blurPreviewURL,
          transparentBackground: true
        )
        .blur(radius: 28)
        .opacity(0.36)
        .scaleEffect(1.12)
      }
    }
    .clipped()
  }
}

private struct ArtworkActionStrip: View {
  let url: URL?
  let saveStatus: ArtworkSaveStatus
  let onOpen: () -> Void
  let onSave: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Button(action: onOpen) {
        ArtworkActionLabel(systemImage: "arrow.up.left.and.arrow.down.right", title: "View")
      }
      .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78, haptic: .selection))

      Button(action: onSave) {
        ArtworkSaveActionLabel(status: saveStatus)
      }
      .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78))
      .disabled(saveStatus.isSaving)

      if let url {
        ShareLink(item: url) {
          ArtworkActionLabel(systemImage: "square.and.arrow.up", title: "Share")
        }
        .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78, haptic: .selection))
      }
    }
  }
}

private struct ArtworkActionLabel: View {
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

private struct ArtworkSaveActionLabel: View {
  let status: ArtworkSaveStatus

  var body: some View {
    Group {
      switch status {
      case .saving:
        Label {
          Text("Saving")
        } icon: {
          ProgressView()
            .controlSize(.small)
        }
      case .success:
        Label("Saved", systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)
      case .failed:
        Label("Retry", systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
      case .idle:
        Label("Save", systemImage: "square.and.arrow.down")
      }
    }
    .font(.system(size: 15, weight: .semibold))
    .lineLimit(1)
    .minimumScaleFactor(0.82)
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
    .background(Color.appControlInactiveFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}

private struct ArtworkDetailMetadata: View {
  let art: GalleryArt

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if let description = trimmed(art.description) {
        ArtworkDetailSection(title: "About", text: description)
      }
      if let credit = trimmed(art.credit) {
        ArtworkDetailSection(title: "Credits", text: credit)
      }
      if let fileName = trimmed(art.fileName) {
        ArtworkDetailSection(title: "File", text: fileName)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct ArtworkDetailContextPreview: View {
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

private struct ArtworkDetailSection: View {
  let title: String
  let text: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
      Text(text)
        .font(.system(size: 15, weight: .regular))
        .foregroundStyle(.primary.opacity(0.88))
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(Color.appDivider, lineWidth: 1)
    }
  }
}

private struct ArtworkDetailPill: View {
  let systemImage: String
  let title: String
  let tint: Color

  var body: some View {
    Label(title, systemImage: systemImage)
      .font(.caption.weight(.bold))
      .foregroundStyle(tint)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(Color.appControlInactiveFill, in: Capsule())
  }
}

private func trimmed(_ value: String?) -> String? {
  guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
    return nil
  }
  return trimmed
}

#if canImport(UIKit)
  import UIKit

  final class ImageSaver: NSObject {
    static let shared = ImageSaver()
    private var completion: ((Result<Void, Error>) -> Void)?
    func save(image: UIImage, completion: @escaping (Result<Void, Error>) -> Void) {
      self.completion = completion
      UIImageWriteToSavedPhotosAlbum(
        image, self, #selector(didFinishSaving(_:didFinishSavingWithError:contextInfo:)), nil)
    }
    @objc private func didFinishSaving(
      _ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer
    ) {
      if let error = error {
        completion?(.failure(error))
      } else {
        completion?(.success(()))
      }
      completion = nil
    }
  }
#endif

struct ZoomableImageViewer: View {
  let url: URL?
  let lowResURL: URL?
  @Binding var saveStatus: ArtworkSaveStatus
  let onSave: () -> Void
  var title: String?
  var subtitle: String?
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var scale: CGFloat = 1
  @State private var lastScale: CGFloat = 1
  @State private var offset: CGSize = .zero
  @State private var lastOffset: CGSize = .zero
  @State private var showOverlay = true
  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }
  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      if let url {
        LoadingImage(
          url: url, cornerRadius: 0, contentMode: .fit, showsLoading: true,
          lowResURL: lowResURL, transparentBackground: true, fullResolution: true
        )
        .scaleEffect(scale)
        .offset(offset)
        .modifier(
          PinchToZoomModifier(
            scale: $scale,
            lastScale: $lastScale,
            offset: $offset,
            lastOffset: $lastOffset,
            reduceMotion: reduceMotion
          )
        )
        .simultaneousGesture(
          DragGesture()
            .onChanged { value in
              guard scale > 1 else { return }
              offset = CGSize(
                width: lastOffset.width + value.translation.width,
                height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in lastOffset = offset }
        )
        .simultaneousGesture(imageTapGesture)
      }
      if showOverlay {
        VStack {
          HStack {
            Button {
              AppHaptic.light.play()
              dismiss()
            } label: {
              Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 36, height: 36)
            }
            .modifier(GlassCircle())
            Spacer()
            Button {
              AppHaptic.selection.play()
              onSave()
            } label: {
              saveButtonLabel
            }
            .disabled(saveStatus.isSaving)
            .accessibilityLabel(saveAccessibilityLabel)
          }
          .padding()
          Spacer()
          if visibleTitle != nil || visibleSubtitle != nil {
            VStack(spacing: 4) {
              if let title = visibleTitle {
                Text(title)
                  .font(.system(size: 17, weight: .bold))
                  .foregroundColor(.white)
                  .lineLimit(2)
                  .multilineTextAlignment(.center)
              }
              if let subtitle = visibleSubtitle {
                Text(subtitle)
                  .font(.system(size: 14))
                  .foregroundColor(.white.opacity(0.7))
                  .lineLimit(1)
              }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
              LinearGradient(
                colors: [.clear, .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
              )
              .ignoresSafeArea()
            )
          }
        }
        .transition(.opacity)
      }
    }
    .statusBarHidden(true)
  }

  private var imageTapGesture: some Gesture {
    TapGesture(count: 2)
      .exclusively(before: TapGesture(count: 1))
      .onEnded { value in
        switch value {
        case .first:
          toggleZoom()
        case .second:
          toggleOverlay()
        }
      }
  }

  private func toggleZoom() {
    AppHaptic.medium.play()
    let update = {
      if scale > 1 {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
      } else {
        scale = 2
        lastScale = 2
      }
    }
    if reduceMotion {
      update()
    } else {
      withAnimation(.spring()) {
        update()
      }
    }
  }

  private func toggleOverlay() {
    AppHaptic.selection.play()
    if reduceMotion {
      showOverlay.toggle()
    } else {
      withAnimation(.easeInOut(duration: 0.25)) {
        showOverlay.toggle()
      }
    }
  }

  private var visibleTitle: String? {
    guard let title, !title.isEmpty else { return nil }
    return title
  }

  private var visibleSubtitle: String? {
    guard let subtitle, !subtitle.isEmpty else { return nil }
    return subtitle
  }

  @ViewBuilder
  private var saveButtonLabel: some View {
    Group {
      switch saveStatus {
      case .saving:
        ProgressView()
          .progressViewStyle(.circular)
          .tint(.white)
      case .success:
        Image(systemName: "checkmark.circle.fill")
          .foregroundColor(.green)
      case .failed:
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundColor(.orange)
      case .idle:
        Image(systemName: "square.and.arrow.down")
          .foregroundColor(.white)
      }
    }
    .font(.system(size: 16, weight: .semibold))
    .frame(width: 36, height: 36)
    .background(Color.black.opacity(0.4))
    .clipShape(Circle())
  }

  private var saveAccessibilityLabel: String {
    switch saveStatus {
    case .saving:
      return "Saving image"
    case .success:
      return "Image saved"
    case .failed:
      return "Image save failed"
    case .idle:
      return "Save image"
    }
  }
}

private struct PinchToZoomModifier: ViewModifier {
  @Binding var scale: CGFloat
  @Binding var lastScale: CGFloat
  @Binding var offset: CGSize
  @Binding var lastOffset: CGSize
  let reduceMotion: Bool

  @ViewBuilder
  func body(content: Content) -> some View {
    content.gesture(
      MagnifyGesture()
        .onChanged { value in
          scale = max(1, min(5, lastScale * value.magnification))
        }
        .onEnded { _ in
          finishZoom()
        }
    )
  }

  private func finishZoom() {
    lastScale = scale
    if scale <= 1 {
      if reduceMotion {
        offset = .zero
        lastOffset = .zero
      } else {
        withAnimation(.spring()) {
          offset = .zero
          lastOffset = .zero
        }
      }
    }
  }
}
