import SwiftUI

struct ArtDetailView: View {
  let art: GalleryArt
  let artist: GalleryArtist
  @State private var showFullScreen = false
  @State private var saveStatus: ArtworkSaveStatus = .idle
  private var fullResURL: URL? {
    art.fullHDImageURL ?? art.imageURL
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        if let url = fullResURL {
          Button {
            showFullScreen = true
          } label: {
            LoadingImage(
              url: url, cornerRadius: 12, contentMode: .fit, showsLoading: false,
              lowResURL: art.blurPreviewURL, transparentBackground: true
            )
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
          }
          .buttonStyle(PressableButtonStyle())
        }
        VStack(alignment: .leading, spacing: 8) {
          Text(artist.name)
            .font(.title3.bold())
          if let social = artist.socialLink, !social.isEmpty {
            Text(social)
              .font(.system(size: 13))
              .foregroundColor(.secondary)
          }
          if let upvotes = art.upvotes, upvotes > 0 {
            Label("\(upvotes)", systemImage: "heart.fill")
              .font(.system(size: 13))
              .foregroundColor(.secondary)
              .padding(.top, 2)
          }
          if let desc = art.description, !desc.isEmpty {
            Text(desc)
              .font(.system(size: 14))
              .foregroundColor(.primary.opacity(0.85))
              .padding(.top, 4)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
      }
      .padding(.vertical)
    }
    .navigationTitle(artist.name)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
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
  }
  private func saveImage() {
    guard !saveStatus.isSaving else { return }
    guard let url = fullResURL else { return }
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
  @State private var scale: CGFloat = 1
  @State private var lastScale: CGFloat = 1
  @State private var offset: CGSize = .zero
  @State private var lastOffset: CGSize = .zero
  @State private var showOverlay = true
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
            lastOffset: $lastOffset
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
    withAnimation(.spring()) {
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
  }

  private func toggleOverlay() {
    withAnimation(.easeInOut(duration: 0.25)) {
      showOverlay.toggle()
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
      withAnimation(.spring()) {
        offset = .zero
        lastOffset = .zero
      }
    }
  }
}
