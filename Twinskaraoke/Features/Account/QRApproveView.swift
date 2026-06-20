import AVFoundation
import SwiftUI

struct QRApproveView: View {
  @ObservedObject var auth: AuthManager
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var phase: Phase = .scanning
  @State private var permission: CameraPermission = .unknown
  @State private var scannerIsActive = false

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
          GlassXButton(action: {
            AppHaptic.light.play()
            dismiss()
          })
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
    .animation(phaseAnimation, value: phaseKey)
    .animation(permissionAnimation, value: permissionKey)
  }

  private var content: some View {
    Group {
      switch phase {
      case .scanning:
        scanner
      case .confirming(let sid):
        confirmCard(sessionId: sid)
      case .approving:
        statusCard(
          icon: "hourglass",
          tint: .appAccent,
          title: "Approving...",
          subtitle: "Keep this screen open while the web session is confirmed."
        )
      case .success:
        statusCard(
          icon: "checkmark.circle.fill",
          tint: .green,
          title: "Signed in on web",
          subtitle: "You can return to your browser."
        )
      case .failure(let msg):
        statusCard(
          icon: "exclamationmark.triangle.fill",
          tint: .orange,
          title: "Couldn't sign in",
          subtitle: msg,
          retry: true
        )
      }
    }
    .id(phaseKey)
    .transition(contentTransition)
  }

  @ViewBuilder
  private var scanner: some View {
    switch permission {
    case .unknown:
      QRPermissionLoadingView()
    case .denied:
      QRPermissionDeniedView {
        AppHaptic.selection.play()
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url)
        }
      }
    case .granted:
      ZStack {
        QRCameraView(onScan: handleScan)
          .ignoresSafeArea()
        QRScannerChrome(isActive: scannerIsActive)
        VStack {
          Spacer()
          QRScannerInstructionPanel()
            .padding(.horizontal, 20)
            .padding(.bottom, 34)
        }
      }
      .onAppear {
        scannerIsActive = true
      }
    }
  }

  private var phaseKey: String {
    switch phase {
    case .scanning:
      return "scanning-\(permissionKey)"
    case .confirming:
      return "confirming"
    case .approving:
      return "approving"
    case .success:
      return "success"
    case .failure:
      return "failure"
    }
  }

  private var permissionKey: String {
    switch permission {
    case .unknown: return "unknown"
    case .granted: return "granted"
    case .denied: return "denied"
    }
  }

  private func confirmCard(sessionId: String) -> some View {
    VStack(spacing: 22) {
      QRHeroGlyph(systemImage: "lock.shield.fill", tint: .appAccent)

      VStack(spacing: 8) {
        Text("Sign in on web?")
          .font(.title2.weight(.bold))
          .foregroundStyle(.primary)
        Text(
          "Approving signs in \(auth.currentUsername ?? "your account") on the device showing this QR code."
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      }

      VStack(spacing: 0) {
        QRInfoRow(
          symbol: "person.crop.circle",
          title: "Account",
          value: auth.currentUsername ?? "Current user"
        )
        Divider().padding(.leading, 40)
        QRInfoRow(
          symbol: "display",
          title: "Web session",
          value: String(sessionId.prefix(8)).uppercased()
        )
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .background(Color.appControlInactiveFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

      VStack(spacing: 10) {
        Button {
          AppHaptic.medium.play()
          Task { await approve(sessionId: sessionId) }
        } label: {
          QRActionLabel(title: "Approve", systemImage: "checkmark.circle.fill", isPrimary: true)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78))

        Button {
          AppHaptic.light.play()
          withOptionalAnimation(phaseAnimation) {
            phase = .scanning
          }
        } label: {
          QRActionLabel(title: "Cancel", systemImage: "xmark.circle", isPrimary: false)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78))
      }
    }
    .padding(24)
    .frame(maxWidth: 390)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 26, style: .continuous)
        .stroke(Color.appDivider, lineWidth: 1)
    )
    .shadow(color: Color.appShadow, radius: 24, y: 12)
    .padding(.horizontal, 22)
  }

  private func statusCard(
    icon: String,
    tint: Color,
    title: String,
    subtitle: String?,
    retry: Bool = false
  ) -> some View {
    VStack(spacing: 20) {
      QRHeroGlyph(systemImage: icon, tint: tint, isSpinning: icon == "hourglass")

      VStack(spacing: 8) {
        Text(title)
          .font(.title2.weight(.bold))
          .foregroundStyle(.primary)
          .multilineTextAlignment(.center)
        if let subtitle {
          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      Button {
        if retry {
          AppHaptic.selection.play()
          withOptionalAnimation(phaseAnimation) {
            phase = .scanning
          }
        } else {
          AppHaptic.light.play()
          dismiss()
        }
      } label: {
        QRActionLabel(
          title: retry ? "Try Again" : "Done",
          systemImage: retry ? "arrow.clockwise" : "checkmark",
          isPrimary: true
        )
      }
      .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78))
    }
    .padding(24)
    .frame(maxWidth: 390)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 26, style: .continuous)
        .stroke(Color.appDivider, lineWidth: 1)
    )
    .shadow(color: Color.appShadow, radius: 24, y: 12)
    .padding(.horizontal, 22)
  }

  private var isApproving: Bool {
    if case .approving = phase { return true }
    return false
  }

  private func qrConfirmAction() {
    switch phase {
    case .scanning:
      AppHaptic.light.play()
      dismiss()
    case .confirming(let sessionId):
      AppHaptic.medium.play()
      Task { await approve(sessionId: sessionId) }
    case .approving:
      break
    case .success:
      AppHaptic.light.play()
      dismiss()
    case .failure:
      AppHaptic.selection.play()
      withOptionalAnimation(phaseAnimation) {
        phase = .scanning
      }
    }
  }

  private func handleScan(_ value: String) {
    guard case .scanning = phase else { return }
    guard let sessionId = parseSessionId(from: value) else { return }
    AppHaptic.success.play()
    withOptionalAnimation(phaseAnimation) {
      phase = .confirming(sessionId: sessionId)
    }
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
    withOptionalAnimation(phaseAnimation) {
      phase = .approving(sessionId: sessionId)
    }
    do {
      try await auth.approveQRSession(sessionId: sessionId)
      AppHaptic.success.play()
      withOptionalAnimation(phaseAnimation) {
        phase = .success
      }
    } catch let AuthManager.AuthError.http(code, _) {
      let msg: String
      switch code {
      case 404: msg = "This QR code expired. Refresh it and try again."
      case 401: msg = "Your session expired. Sign in again."
      default: msg = "Server error (\(code))."
      }
      AppHaptic.error.play()
      withOptionalAnimation(phaseAnimation) {
        phase = .failure(msg)
      }
    } catch {
      AppHaptic.error.play()
      withOptionalAnimation(phaseAnimation) {
        phase = .failure(error.localizedDescription)
      }
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

  private var contentTransition: AnyTransition {
    reduceMotion
      ? .opacity
      : .asymmetric(
        insertion: .opacity.combined(with: .scale(scale: 0.97)).combined(with: .move(edge: .bottom)),
        removal: .opacity.combined(with: .scale(scale: 1.02))
      )
  }

  private var phaseAnimation: Animation? {
    reduceMotion ? nil : AppMotion.spring(response: 0.36, dampingFraction: 0.84)
  }

  private var permissionAnimation: Animation? {
    reduceMotion ? nil : AppMotion.spring(response: 0.2, dampingFraction: 0.9)
  }

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }
}

private struct QRPermissionLoadingView: View {
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var pulse = false

  var body: some View {
    VStack(spacing: 18) {
      QRHeroGlyph(systemImage: "camera.viewfinder", tint: .appAccent, isPulsing: pulse)
      VStack(spacing: 6) {
        Text("Checking Camera Access")
          .font(.title3.weight(.bold))
        Text("The scanner will open as soon as access is ready.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      ProgressView()
        .controlSize(.regular)
    }
    .padding(24)
    .frame(maxWidth: 360)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 26, style: .continuous)
        .stroke(Color.appDivider, lineWidth: 1)
    )
    .shadow(color: Color.appShadow, radius: 22, y: 10)
    .padding(.horizontal, 24)
    .onAppear {
      withOptionalAnimation(pulseAnimation) {
        pulse = true
      }
    }
  }

  private var pulseAnimation: Animation? {
    reduceMotion ? nil : AppMotion.spring(response: 1.15, dampingFraction: 0.82).repeatForever(autoreverses: true)
  }

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }
}

private struct QRPermissionDeniedView: View {
  let openSettings: () -> Void

  var body: some View {
    VStack(spacing: 18) {
      QRHeroGlyph(systemImage: "video.slash", tint: Color.secondary)
      VStack(spacing: 8) {
        Text("Camera Access Is Off")
          .font(.title3.weight(.bold))
          .foregroundStyle(.primary)
        Text("Enable camera access in Settings to scan a sign-in code.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      Button(action: openSettings) {
        QRActionLabel(title: "Open Settings", systemImage: "gearshape.fill", isPrimary: true)
      }
      .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78))
    }
    .padding(24)
    .frame(maxWidth: 380)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 26, style: .continuous)
        .stroke(Color.appDivider, lineWidth: 1)
    )
    .shadow(color: Color.appShadow, radius: 22, y: 10)
    .padding(.horizontal, 24)
  }
}

private struct QRScannerChrome: View {
  let isActive: Bool
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true

  var body: some View {
    GeometryReader { proxy in
      let side = min(proxy.size.width, proxy.size.height) * 0.7
      ZStack {
        Color.black.opacity(0.28)
          .ignoresSafeArea()
        RoundedRectangle(cornerRadius: 30, style: .continuous)
          .fill(Color.clear)
          .frame(width: side, height: side)
          .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
              .stroke(Color.white.opacity(0.68), lineWidth: 1)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
              .stroke(Color.appAccent.opacity(isActive ? 0.36 : 0.12), lineWidth: 6)
              .blur(radius: 8)
          )
          .overlay(QRCornerBrackets().padding(4))
          .overlay(QRScanLine(isActive: isActive).padding(.horizontal, 18))
          .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
          .shadow(color: .black.opacity(0.35), radius: 22, y: 10)
      }
      .animation(chromeAnimation, value: isActive)
    }
    .allowsHitTesting(false)
  }

  private var chromeAnimation: Animation? {
    reduceMotion ? nil : AppMotion.spring(response: 1.6, dampingFraction: 0.86).repeatForever(autoreverses: true)
  }

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }
}

private struct QRScanLine: View {
  let isActive: Bool
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true

  var body: some View {
    GeometryReader { proxy in
      Capsule()
        .fill(
          LinearGradient(
            colors: [
              .clear,
              .appAccent.opacity(0.75),
              .white.opacity(0.88),
              .appAccent.opacity(0.75),
              .clear,
            ],
            startPoint: .leading,
            endPoint: .trailing
          )
        )
        .frame(height: 2)
        .shadow(color: Color.appAccent.opacity(0.55), radius: 8, y: 0)
        .offset(y: reduceMotion ? proxy.size.height / 2 : (isActive ? proxy.size.height - 38 : 36))
        .animation(scanLineAnimation, value: isActive)
    }
  }

  private var scanLineAnimation: Animation? {
    reduceMotion ? nil : AppMotion.spring(response: 1.7, dampingFraction: 0.86).repeatForever(autoreverses: true)
  }

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }
}

private struct QRCornerBrackets: View {
  var body: some View {
    ZStack {
      QRCornerShape(corner: .topLeading)
        .stroke(Color.white.opacity(0.96), style: stroke)
      QRCornerShape(corner: .topTrailing)
        .stroke(Color.white.opacity(0.96), style: stroke)
      QRCornerShape(corner: .bottomLeading)
        .stroke(Color.white.opacity(0.96), style: stroke)
      QRCornerShape(corner: .bottomTrailing)
        .stroke(Color.white.opacity(0.96), style: stroke)
    }
  }

  private var stroke: StrokeStyle {
    StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
  }
}

private struct QRCornerShape: Shape {
  enum Corner {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
  }

  let corner: Corner

  func path(in rect: CGRect) -> Path {
    let length = min(rect.width, rect.height) * 0.17
    var path = Path()
    switch corner {
    case .topLeading:
      path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))
    case .topTrailing:
      path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))
    case .bottomLeading:
      path.move(to: CGPoint(x: rect.minX, y: rect.maxY - length))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.minX + length, y: rect.maxY))
    case .bottomTrailing:
      path.move(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
    }
    return path
  }
}

private struct QRScannerInstructionPanel: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label {
        Text("Scan Web Sign-In Code")
          .font(.headline)
      } icon: {
        Image(systemName: "qrcode.viewfinder")
          .font(.headline)
          .foregroundStyle(Color.appAccent)
      }
      Text("Point the camera at the QR code shown on twinskaraoke.com.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 8) {
        Image(systemName: "lock.fill")
          .font(.caption.bold())
          .foregroundStyle(.secondary)
        Text("You will approve the session before signing in.")
          .font(.caption.weight(.medium))
          .foregroundStyle(.secondary)
      }
    }
    .padding(16)
    .frame(maxWidth: 420, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(Color.white.opacity(0.16), lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
  }
}

private struct QRHeroGlyph: View {
  let systemImage: String
  let tint: Color
  var isSpinning = false
  var isPulsing = false
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var animate = false

  var body: some View {
    Image(systemName: systemImage)
      .font(.largeTitle.bold())
      .foregroundStyle(tint)
      .frame(width: 86, height: 86)
      .background(tint.opacity(0.12), in: Circle())
      .overlay(Circle().stroke(tint.opacity(0.22), lineWidth: 1))
      .scaleEffect(isPulsing && animate ? 1.06 : 1)
      .rotationEffect(.degrees(isSpinning && animate ? 360 : 0))
      .shadow(color: tint.opacity(0.18), radius: 16, y: 8)
      .animation(heroAnimation, value: animate)
      .onAppear {
        animate = !reduceMotion && (isSpinning || isPulsing)
      }
  }

  private var heroAnimation: Animation? {
    guard !reduceMotion else { return nil }
    return isSpinning
      ? AppMotion.spring(response: 1.3, dampingFraction: 0.9).repeatForever(autoreverses: false)
      : AppMotion.spring(response: 1.05, dampingFraction: 0.82).repeatForever(autoreverses: true)
  }

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }
}

private struct QRInfoRow: View {
  let symbol: String
  let title: String
  let value: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.headline)
        .foregroundStyle(Color.appAccent)
        .frame(width: 44, height: 44)
        .background(Color.appAccent.opacity(0.12), in: Circle())
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(value)
          .font(.body.bold())
          .foregroundStyle(.primary)
          .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 8)
  }
}

private struct QRActionLabel: View {
  let title: String
  let systemImage: String
  let isPrimary: Bool

  var body: some View {
    Label(title, systemImage: systemImage)
      .font(.headline)
      .foregroundStyle(isPrimary ? Color.appControlActiveForeground : Color.appAccent)
      .frame(maxWidth: .infinity)
      .frame(height: 50)
      .background(
        isPrimary ? Color.appControlActiveFill : Color.appControlInactiveFill,
        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
      )
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
    stopSession()
  }
  deinit {
    stopSession()
  }
  private func stopSession() {
    let capturedSession = session
    guard capturedSession.isRunning else { return }
    DispatchQueue.global(qos: .userInitiated).async {
      capturedSession.stopRunning()
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
