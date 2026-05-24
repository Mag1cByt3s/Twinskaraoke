import SwiftUI

struct ArtDetailView: View {
  let art: GalleryArt
  let artist: GalleryArtist
  @State private var showFullScreen = false
  @State private var saveStatus: SaveStatus = .idle
  enum SaveStatus {
    case idle, saving, success
    case failed(String)
  }
  private var fullResURL: URL? {
    guard let path = art.absolutePath else { return art.imageURL }
    return URL(string: StorageHost.images + path + "/quality=95")
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
        .disabled({ if case .saving = saveStatus { return true } else { return false } }())
      }
    }
    .fullScreenCover(isPresented: $showFullScreen) {
      ZoomableImageViewer(url: fullResURL, lowResURL: art.blurPreviewURL, onSave: saveImage)
    }
  }
  private func saveImage() {
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
          url: url, cornerRadius: 0, contentMode: .fit, showsLoading: false,
          lowResURL: lowResURL, transparentBackground: true
        )
        .scaleEffect(scale)
        .offset(offset)
        .gesture(
          MagnificationGesture()
            .onChanged { value in
              scale = max(1, min(5, lastScale * value))
            }
            .onEnded { _ in
              lastScale = scale
              if scale <= 1 {
                withAnimation(.spring()) {
                  offset = .zero
                  lastOffset = .zero
                }
              }
            }
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
        .onTapGesture(count: 2) {
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
        .onTapGesture(count: 1) {
          withAnimation(.easeInOut(duration: 0.25)) {
            showOverlay.toggle()
          }
        }
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
              Image(systemName: "square.and.arrow.down")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Color.black.opacity(0.4))
                .clipShape(Circle())
            }
          }
          .padding()
          Spacer()
          if title != nil || subtitle != nil {
            VStack(spacing: 4) {
              if let title {
                Text(title)
                  .font(.system(size: 17, weight: .bold))
                  .foregroundColor(.white)
                  .lineLimit(2)
                  .multilineTextAlignment(.center)
              }
              if let subtitle {
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
}
