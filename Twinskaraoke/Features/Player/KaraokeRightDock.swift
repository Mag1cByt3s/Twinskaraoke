import SwiftUI

struct KaraokeRightDock: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @ObservedObject private var vocalSeparator = VocalSeparator.shared
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
    @Binding var showKaraokeControls: Bool

    private var currentSongID: String? {
        audioManager.currentSong?.id
    }

    private var isProcessing: Bool {
        vocalSeparator.processingSongID == currentSongID
    }

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

    private var vocalRemovalPercent: Int {
        Int((Double(audioManager.aiVocalStrength) * 100).rounded())
    }

    private var dockAccessibilityValue: String {
        if audioManager.karaokeMode {
            return "On, removal level \(vocalRemovalPercent)%"
        }
        if shouldShowProcessingIndicator {
            return "Preparing, \(processingPercentText)"
        }
        return "Off"
    }

    var body: some View {
        VStack(spacing: 4) {
            if showKaraokeControls, audioManager.karaokeMode {
                karaokeVerticalSlider
                    .transition(sliderTransition)
            }
            karaokeMicButton
            if shouldShowProcessingIndicator {
                processingIndicator
            }
        }
        .animation(dockAnimation, value: showKaraokeControls)
        .animation(dockAnimation, value: audioManager.karaokeMode)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Karaoke controls")
        .accessibilityValue(dockAccessibilityValue)
    }

    private var karaokeMicButton: some View {
        Button {
            if audioManager.karaokeMode {
                AppHaptic.selection.play()
                audioManager.karaokeMode = false
                showKaraokeControls = false
            } else {
                guard canActivateKaraoke else { return }
                AppHaptic.medium.play()
                audioManager.karaokeMode = true
                showKaraokeControls = true
            }
        } label: {
            ZStack {
                if isProcessing {
                    Circle()
                        .trim(from: 0, to: processingRingFraction)
                        .stroke(Color.appAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(3)
                }

                Image(systemName: audioManager.karaokeMode ? "mic.fill" : "mic")
                    .font(.headline)
                    .foregroundStyle(audioManager.karaokeMode ? Color.appAccent : Color.primary.opacity(0.85))
            }
            .frame(width: 44, height: 44)
            .modifier(GlassCircle())
            .opacity(canActivateKaraoke ? 1 : 0.6)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.9, dim: 0.7))
        .disabled(!canActivateKaraoke)
        .animation(dockAnimation, value: processingFraction)
        .accessibilityLabel(audioManager.karaokeMode ? "Turn Off Vocal Removal" : "Vocal Removal")
        .accessibilityValue(karaokeButtonAccessibilityValue)
        .accessibilityHint(karaokeButtonAccessibilityHint)
    }

    private var karaokeVerticalSlider: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
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
            .accessibilityLabel("Vocal removal level")
            .accessibilityValue("\(vocalRemovalPercent)%")
            .accessibilityHint("Swipe up or down to adjust vocal removal.")
            .accessibilityAdjustableAction { direction in
                adjustVocalRemoval(direction)
            }
            Image(systemName: "person.wave.2")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .modifier(GlassRoundedRect(cornerRadius: 18))
    }

    private var processingIndicator: some View {
        VStack(spacing: 4) {
            Text(processingPercentText)
                .font(.caption.monospacedDigit())
                .bold()
                .foregroundStyle(isProcessing ? Color.appAccent : .secondary)
                .monospacedDigit()
        }
        .padding(.top, -2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preparing karaoke")
        .accessibilityValue(processingPercentText)
    }

    private var reduceMotion: Bool {
        AppMotion.reduceMotion(
            systemReduceMotion: systemReduceMotion,
            respectPreference: respectReducedMotion
        )
    }

    private var dockAnimation: Animation? {
        reduceMotion ? nil : AppMotion.spring(response: 0.4, dampingFraction: 0.85)
    }

    private var sliderTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    private var karaokeButtonAccessibilityValue: String {
        if audioManager.karaokeMode { return "On" }
        if shouldShowProcessingIndicator { return "Preparing, \(processingPercentText)" }
        return "Off"
    }

    private var karaokeButtonAccessibilityHint: String {
        if canActivateKaraoke {
            return audioManager.karaokeMode
                ? "Disables vocal removal."
                : "Enables vocal removal and opens the removal level control."
        }
        return "Karaoke is preparing for this song."
    }

    private func adjustVocalRemoval(_ direction: AccessibilityAdjustmentDirection) {
        guard audioManager.karaokeMode else { return }
        let step: Float = 0.05
        switch direction {
        case .increment:
            audioManager.aiVocalStrength = min(1, audioManager.aiVocalStrength + step)
            AppHaptic.selection.play()
        case .decrement:
            audioManager.aiVocalStrength = max(0, audioManager.aiVocalStrength - step)
            AppHaptic.selection.play()
        @unknown default:
            break
        }
    }
}
