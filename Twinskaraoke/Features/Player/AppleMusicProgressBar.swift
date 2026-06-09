import SwiftUI

struct AppleMusicProgressBar: View {
  @Binding var progress: Double
  @Binding var isScrubbing: Bool
  let onSeekEnd: (Double) -> Void
  var trackColor: Color = Color.primary.opacity(0.22)
  var fillColor: Color = .primary
  var idleHeight: CGFloat = 5
  var activeHeight: CGFloat = 9
  var accessibilityLabel: String = "Progress"
  var accessibilityValueText: String? = nil
  var accessibilityHint: String = "Swipe up or down to adjust."
  var scrubValueText: String? = nil
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var didBeginScrubbing = false

  private var clampedProgress: Double {
    min(max(progress, 0), 1)
  }

  private var controlHeight: CGFloat {
    scrubValueText == nil ? 24 : 42
  }

  var body: some View {
    GeometryReader { geo in
      let height: CGFloat = isScrubbing ? activeHeight : idleHeight
      let width = max(geo.size.width, 1)
      let thumbDiameter: CGFloat = isScrubbing ? 14 : 8
      let thumbCenterX = min(
        max(width * CGFloat(clampedProgress), thumbDiameter / 2),
        width - thumbDiameter / 2
      )
      let bubbleWidth: CGFloat = 64
      let bubbleCenterX = min(max(thumbCenterX, bubbleWidth / 2), width - bubbleWidth / 2)
      let barCenterY = scrubValueText == nil ? controlHeight / 2 : controlHeight - 11
      ZStack(alignment: .topLeading) {
        ZStack(alignment: .leading) {
          Capsule().fill(trackColor)
          Capsule()
            .fill(fillColor)
            .frame(width: max(0, width * CGFloat(clampedProgress)))
          Circle()
            .fill(fillColor)
            .frame(width: thumbDiameter, height: thumbDiameter)
            .shadow(color: .black.opacity(isScrubbing ? 0.22 : 0), radius: 5, x: 0, y: 2)
            .offset(x: thumbCenterX - thumbDiameter / 2)
            .opacity(isScrubbing ? 1 : 0)
            .scaleEffect(reduceMotion ? 1 : (isScrubbing ? 1 : 0.72))
        }
        .frame(width: width, height: height)
        .position(x: width / 2, y: barCenterY)

        if let scrubValueText, isScrubbing {
          Text(scrubValueText)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .frame(width: bubbleWidth, height: 22)
            .background(
              Capsule()
                .fill(Color.appGlassFillStrong)
                .shadow(color: Color.appShadow, radius: 8, y: 4)
            )
            .position(x: bubbleCenterX, y: 9)
            .transition(scrubBubbleTransition)
            .accessibilityHidden(true)
        }
      }
      .frame(width: width, height: controlHeight)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            if !isScrubbing {
              isScrubbing = true
            }
            if !didBeginScrubbing {
              didBeginScrubbing = true
              AppHaptic.selection.play()
            }
            progress = max(0, min(1, value.location.x / width))
          }
          .onEnded { _ in
            let finalProgress = clampedProgress
            onSeekEnd(finalProgress)
            isScrubbing = false
            didBeginScrubbing = false
            AppHaptic.light.play()
          }
      )
      .animation(scrubAnimation, value: isScrubbing)
    }
    .frame(height: controlHeight)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityValue(accessibilityValueText ?? "\(Int(clampedProgress * 100)) percent")
    .accessibilityHint(accessibilityHint)
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment:
        adjustProgress(by: 0.05)
      case .decrement:
        adjustProgress(by: -0.05)
      @unknown default:
        break
      }
    }
  }

  private func adjustProgress(by delta: Double) {
    let nextProgress = min(max(progress + delta, 0), 1)
    progress = nextProgress
    onSeekEnd(nextProgress)
    AppHaptic.selection.play()
  }

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }

  private var scrubAnimation: Animation? {
    reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)
  }

  private var scrubBubbleTransition: AnyTransition {
    reduceMotion ? .opacity : .scale(scale: 0.86).combined(with: .opacity)
  }
}
