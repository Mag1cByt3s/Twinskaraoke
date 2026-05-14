import SwiftUI

struct KaraokeRightDock: View {
  @EnvironmentObject var audioManager: AudioPlayerManager
  @ObservedObject private var vocalSeparator = VocalSeparator.shared
  @Binding var showKaraokeControls: Bool

  private var currentSongID: String? { audioManager.currentSong?.id }
  private var isProcessing: Bool { vocalSeparator.processingSongID == currentSongID }
  private var processingFraction: CGFloat {
    CGFloat(min(1, max(0, vocalSeparator.progressFraction)))
  }
  private var processingRingFraction: CGFloat {
    guard isProcessing else { return 0 }
    return max(0.03, processingFraction)
  }
  private var processingPercentText: String {
    "\(Int((processingFraction * 100).rounded()))%"
  }
  private var shouldShowProcessingIndicator: Bool {
    audioManager.aiAutoAnalyze && audioManager.isBackgroundKaraokeLocked
  }
  private var canActivateKaraoke: Bool {
    !audioManager.isBackgroundKaraokeLocked
  }

  var body: some View {
    VStack(spacing: 4) {
      if showKaraokeControls && audioManager.karaokeMode {
        karaokeVerticalSlider
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
      karaokeMicButton
      if shouldShowProcessingIndicator {
        processingIndicator
      }
    }
    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showKaraokeControls)
    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: audioManager.karaokeMode)
  }

  private var karaokeMicButton: some View {
    Button {
      if audioManager.karaokeMode {
        audioManager.karaokeMode = false
        showKaraokeControls = false
      } else {
        guard canActivateKaraoke else { return }
        audioManager.karaokeMode = true
        showKaraokeControls = true
      }
    } label: {
      ZStack {
        // Progress ring when AI separation is running
        if isProcessing {
          Circle()
            .trim(from: 0, to: processingRingFraction)
            .stroke(Color.appAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .padding(3)
        }

        Image(systemName: audioManager.karaokeMode ? "mic.fill" : "mic")
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(audioManager.karaokeMode ? .appAccent : .primary.opacity(0.85))
      }
      .frame(width: 36, height: 36)
      .modifier(GlassCircle())
      .opacity(canActivateKaraoke ? 1 : 0.6)
    }
    .buttonStyle(PressableButtonStyle(scale: 0.9, dim: 0.7))
    .disabled(!canActivateKaraoke)
    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: processingFraction)
  }
  private var karaokeVerticalSlider: some View {
    VStack(spacing: 8) {
      Image(systemName: "person.slash")
        .font(.system(size: 11))
        .foregroundColor(.secondary)
      VerticalKaraokeLevel(
        value: Binding(
          get: { Double(audioManager.aiVocalStrength) },
          set: { audioManager.aiVocalStrength = Float($0) }
        ),
        enabled: audioManager.karaokeMode,
        onSet: { _ in
          if !audioManager.karaokeMode { audioManager.karaokeMode = true }
        }
      )
      .frame(width: 28, height: 180)
      Image(systemName: "person.wave.2")
        .font(.system(size: 11))
        .foregroundColor(.secondary)
    }
    .padding(.vertical, 12)
    .padding(.horizontal, 8)
    .modifier(GlassRoundedRect(cornerRadius: 18))
  }

  private var processingIndicator: some View {
    VStack(spacing: 4) {
      Text(processingPercentText)
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(isProcessing ? Color.appAccent : .secondary)
        .monospacedDigit()
    }
    .padding(.top, -2)
  }
}
