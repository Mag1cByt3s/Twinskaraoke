import AVFoundation
import SwiftUI

struct QRApproveView: View {
  @ObservedObject var auth: AuthManager
  @Environment(\.dismiss) private var dismiss
  @State private var phase: Phase = .scanning
  @State private var permission: CameraPermission = .unknown
  enum Phase {
    case scanning
    case confirming(sessionId: String)
    case approving(sessionId: String)
    case success
    case failure(String)
  }

  enum CameraPermission { case unknown, granted, denied }
  var body: some View {
    NavigationStack {
      ZStack {
        Color(.systemBackground).ignoresSafeArea()
        content
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          Text("Sign in on web")
            .font(.headline)
            .foregroundStyle(.primary)
        }
        ToolbarItem(placement: .cancellationAction) {
          GlassXButton(action: { dismiss() })
        }
        ToolbarItem(placement: .confirmationAction) {
          GlassCheckmarkButton(
            action: { qrConfirmAction() },
            isEnabled: !isApproving
          )
        }
      }
      .toolbarBackground(.hidden, for: .navigationBar)
    }
    .task { await checkPermission() }
  }
  @ViewBuilder
  private var content: some View {
    switch phase {
    case .scanning:
      scanner
    case .confirming(let sid):
      confirmCard(sessionId: sid)
    case .approving:
      statusCard(icon: "hourglass", tint: .white, title: "Approving…", subtitle: nil)
    case .success:
      statusCard(
        icon: "checkmark.circle.fill", tint: .green,
        title: "Signed in on web",
        subtitle: "You can return to your browser.")
    case .failure(let msg):
      statusCard(
        icon: "exclamationmark.triangle.fill", tint: .orange,
        title: "Couldn't sign in", subtitle: msg, retry: true)
    }
  }
  @ViewBuilder
  private var scanner: some View {
    switch permission {
    case .unknown:
      ProgressView().tint(.appAccent)
    case .denied:
      VStack(spacing: 16) {
        Image(systemName: "video.slash")
          .font(.system(size: 56))
          .foregroundStyle(.secondary)
        Text("Camera access is off")
          .font(.title3.weight(.semibold))
          .foregroundStyle(.primary)
        Text("Enable camera access in Settings to scan a sign-in code.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
        Button("Open Settings") {
          if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
          }
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(hex: "7C5CFC"))
      }
      .padding(.horizontal, 32)
    case .granted:
      ZStack {
        QRCameraView(onScan: handleScan)
          .ignoresSafeArea()
        viewfinder
        VStack {
          Spacer()
          Text("Point at the QR code shown on neurokaraoke.com")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color.appGlassFillStrong, in: Capsule())
            .padding(.bottom, 40)
        }
      }
    }
  }
  private var viewfinder: some View {
    GeometryReader { proxy in
      let side = min(proxy.size.width, proxy.size.height) * 0.7
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .strokeBorder(.primary.opacity(0.85), lineWidth: 3)
        .frame(width: side, height: side)
        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
    }
    .allowsHitTesting(false)
  }
  private func confirmCard(sessionId: String) -> some View {
    VStack(spacing: 22) {
      Image(systemName: "lock.shield.fill")
        .font(.system(size: 56))
        .foregroundStyle(Color(hex: "B47BFF"))
      VStack(spacing: 8) {
        Text("Sign in on web?")
          .font(.title2.weight(.bold))
          .foregroundStyle(.primary)
        Text(
          "Approving will sign you in as \(auth.currentUsername ?? "yourself") on the device showing this QR code."
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      }
      VStack(spacing: 10) {
        Button {
          Task { await approve(sessionId: sessionId) }
        } label: {
          Text("Approve")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
              LinearGradient(
                colors: [Color(hex: "7C5CFC"), Color(hex: "B47BFF")],
                startPoint: .leading, endPoint: .trailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        Button {
          phase = .scanning
        } label: {
          Text("Cancel")
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.primary.opacity(0.85))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(28)
    .frame(maxWidth: 380)
    .background(
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .fill(Color.appGlassFill)
        .overlay(
          RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(Color.appDivider, lineWidth: 1))
    )
    .padding(.horizontal, 24)
  }
  private func statusCard(
    icon: String, tint: Color, title: String, subtitle: String?, retry: Bool = false
  ) -> some View {
    VStack(spacing: 18) {
      Image(systemName: icon)
        .font(.system(size: 56))
        .foregroundStyle(tint)
      Text(title)
        .font(.title2.weight(.bold))
        .foregroundStyle(.primary)
      if let subtitle {
        Text(subtitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      Button {
        if retry { phase = .scanning } else { dismiss() }
      } label: {
        Text(retry ? "Try Again" : "Done")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity)
          .frame(height: 50)
          .background(
            LinearGradient(
              colors: [Color(hex: "7C5CFC"), Color(hex: "B47BFF")],
              startPoint: .leading, endPoint: .trailing)
          )
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      }
      .buttonStyle(.plain)
    }
    .padding(28)
    .frame(maxWidth: 380)
    .padding(.horizontal, 24)
  }
  private var isApproving: Bool {
    if case .approving = phase { return true }
    return false
  }
  private func qrConfirmAction() {
    switch phase {
    case .scanning:
      dismiss()
    case .confirming(let sessionId):
      Task { await approve(sessionId: sessionId) }
    case .approving:
      break
    case .success:
      dismiss()
    case .failure:
      phase = .scanning
    }
  }
  private func handleScan(_ value: String) {
    guard case .scanning = phase else { return }
    guard let sessionId = parseSessionId(from: value) else { return }
    UINotificationFeedbackGenerator().notificationOccurred(.success)
    phase = .confirming(sessionId: sessionId)
  }
  private func parseSessionId(from raw: String) -> String? {
    if let url = URL(string: raw),
      let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let id = comps.queryItems?.first(where: { $0.name == "sessionId" })?.value,
      !id.isEmpty
    {
      return id
    }
    if let comps = URLComponents(string: "?\(raw)"),
      let id = comps.queryItems?.first(where: { $0.name == "sessionId" })?.value,
      !id.isEmpty
    {
      return id
    }
    return nil
  }
  private func approve(sessionId: String) async {
    phase = .approving(sessionId: sessionId)
    do {
      try await auth.approveQRSession(sessionId: sessionId)
      UINotificationFeedbackGenerator().notificationOccurred(.success)
      phase = .success
    } catch let AuthManager.AuthError.http(code, _) {
      let msg: String
      switch code {
      case 404: msg = "This QR code expired. Refresh it and try again."
      case 401: msg = "Your session expired. Sign in again."
      default: msg = "Server error (\(code))."
      }
      UINotificationFeedbackGenerator().notificationOccurred(.error)
      phase = .failure(msg)
    } catch {
      UINotificationFeedbackGenerator().notificationOccurred(.error)
      phase = .failure(error.localizedDescription)
    }
  }
  private func checkPermission() async {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      permission = .granted
    case .notDetermined:
      let granted = await AVCaptureDevice.requestAccess(for: .video)
      permission = granted ? .granted : .denied
    case .denied, .restricted:
      permission = .denied
    @unknown default:
      permission = .denied
    }
  }
}

private struct QRCameraView: UIViewControllerRepresentable {
  let onScan: (String) -> Void
  func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }
  func makeUIViewController(context: Context) -> QRCameraController {
    let vc = QRCameraController()
    vc.delegate = context.coordinator
    return vc
  }
  func updateUIViewController(_ uiViewController: QRCameraController, context: Context) {}

  final class Coordinator: NSObject, QRCameraControllerDelegate {
    let onScan: (String) -> Void
    init(onScan: @escaping (String) -> Void) { self.onScan = onScan }
    func qrCameraController(_ controller: QRCameraController, didScan value: String) {
      onScan(value)
    }
  }
}

private protocol QRCameraControllerDelegate: AnyObject {
  func qrCameraController(_ controller: QRCameraController, didScan value: String)
}

private final class QRCameraController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
  weak var delegate: QRCameraControllerDelegate?
  private let session = AVCaptureSession()
  private var previewLayer: AVCaptureVideoPreviewLayer?
  private var hasReported = false
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    configureSession()
  }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    if !session.isRunning {
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        self?.session.startRunning()
      }
    }
  }
  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    if session.isRunning {
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        self?.session.stopRunning()
      }
    }
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewLayer?.frame = view.layer.bounds
  }
  private func configureSession() {
    guard let device = AVCaptureDevice.default(for: .video),
      let input = try? AVCaptureDeviceInput(device: device),
      session.canAddInput(input)
    else { return }
    session.addInput(input)
    let output = AVCaptureMetadataOutput()
    guard session.canAddOutput(output) else { return }
    session.addOutput(output)
    output.setMetadataObjectsDelegate(self, queue: .main)
    output.metadataObjectTypes = [.qr]
    let preview = AVCaptureVideoPreviewLayer(session: session)
    preview.videoGravity = .resizeAspectFill
    preview.frame = view.layer.bounds
    view.layer.addSublayer(preview)
    previewLayer = preview
  }
  func metadataOutput(
    _ output: AVCaptureMetadataOutput,
    didOutput metadataObjects: [AVMetadataObject],
    from connection: AVCaptureConnection
  ) {
    guard !hasReported,
      let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
      obj.type == .qr,
      let value = obj.stringValue
    else { return }
    hasReported = true
    delegate?.qrCameraController(self, didScan: value)
  }
}
