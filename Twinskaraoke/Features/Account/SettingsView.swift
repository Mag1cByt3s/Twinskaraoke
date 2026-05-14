import SwiftUI

struct SettingsView: View {
  @StateObject private var audioManager = AudioPlayerManager.shared
  @StateObject private var cacheManager = CacheManager.shared
  @AppStorage("nk.streamingQuality") private var streamingQuality: String = "high"
  @AppStorage("nk.downloadOnPlay") private var downloadOnPlay: Bool = false
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @AppStorage("nk.debugLogging") private var debugLogging: Bool = false
  @State private var pendingAction: SettingsDestructiveAction?
  @State private var showAutoAnalyzeAlert = false
  var body: some View {
    List {
      Section {
        Toggle("Auto Mix", isOn: $audioManager.autoMixEnabled)
          .tint(.appAccent)
        Toggle("Crossfade", isOn: $audioManager.crossfadeEnabled)
          .tint(.appAccent)
        if audioManager.crossfadeEnabled {
          CrossfadeDurationRow(
            seconds: Binding(
              get: { audioManager.crossfadeSeconds },
              set: { audioManager.crossfadeSeconds = $0 }
            )
          )
        }
        Toggle(
          "Autoplay Similar Songs",
          isOn: Binding(
            get: { audioManager.autoplayEnabled },
            set: { _ in audioManager.toggleAutoplay() }
          )
        )
        .tint(.appAccent)
        Picker("Audio Quality", selection: $streamingQuality) {
          Text("High Efficiency").tag("low")
          Text("High Quality").tag("medium")
          Text("Lossless").tag("high")
        }
      } header: {
        Text("Playback")
      } footer: {
        Text(
          "Auto Mix uses beat detection to blend tracks seamlessly — songs with similar tempos get a smooth crossfade, while different tempos get a quick cut. Crossfade uses a fixed duration you choose."
        )
      }
      Section {
        Toggle("Auto-Download Played Songs", isOn: $downloadOnPlay)
          .tint(.appAccent)
      } header: {
        Text("Downloads")
      } footer: {
        Text("When enabled, songs you play are saved for offline listening.")
      }
      if DeviceCapability.supportsKaraoke {
        aiAudioSection
        if audioManager.aiEnabled {
          karaokeSection
        }
      }
      Section {
        Toggle("Equalizer", isOn: $audioManager.eqEnabled)
          .tint(.appAccent)
        if audioManager.eqEnabled {
          Picker("Preset", selection: $audioManager.eqPreset) {
            ForEach(EQPreset.allCases.filter { $0 != .custom || audioManager.eqPreset == .custom })
            { preset in
              Text(preset.rawValue).tag(preset)
            }
          }
          EqualizerBands(gainsDB: $audioManager.eqGainsDB)
            .padding(.vertical, 8)
          Button("Reset Equalizer") {
            audioManager.eqPreset = .flat
          }
          .foregroundStyle(Color.appAccent)
        }
      } header: {
        Text("Equalizer")
      } footer: {
        Text("10-band parametric EQ. Drag each band between −12 dB and +12 dB.")
      }
      Section("Appearance") {
        Toggle("Respect Reduce Motion", isOn: $respectReducedMotion)
          .tint(.appAccent)
      }
      storageSection
      Section("Developer") {
        Toggle("Debug Logging", isOn: $debugLogging)
          .tint(.appAccent)
        if debugLogging {
          Button("Export Debug Logs") {
            exportDebugLogs()
          }
          .foregroundStyle(Color.appAccent)
        }
      }
    }
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.inline)
    .alert(
      pendingAction?.title ?? "",
      isPresented: Binding(
        get: { pendingAction != nil },
        set: { if !$0 { pendingAction = nil } }
      ),
      presenting: pendingAction
    ) { action in
      Button("Cancel", role: .cancel) {}
        .tint(Color(uiColor: .systemBlue))
      Button(action.actionLabel, role: .destructive) {
        perform(action)
      }
    } message: { action in
      Text(action.message)
    }
    .alert(
      "Auto-Analyze During Playback",
      isPresented: $showAutoAnalyzeAlert
    ) {
      Button("Enable") {
        audioManager.aiAutoAnalyze = true
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "Music is pre-analyzed in the background so you can instantly switch between karaoke modes without processing delay.\n\nUses additional battery and processing power during playback. Separated stems are cached within the 4 GB music cache limit."
      )
    }
  }

  // MARK: - AI Audio Section

  @ViewBuilder
  private var aiAudioSection: some View {
    Section {
      Toggle("AI Audio Processing", isOn: $audioManager.aiEnabled)
        .tint(.appAccent)

      if audioManager.aiEnabled {
        Toggle("Auto-Analyze During Playback", isOn: Binding(
          get: { audioManager.aiAutoAnalyze },
          set: { newValue in
            if newValue {
              showAutoAnalyzeAlert = true
            } else {
              audioManager.aiAutoAnalyze = false
            }
          }
        ))
        .tint(.appAccent)
      }
    } header: {
      Text("AI Audio")
    } footer: {
      if audioManager.aiEnabled && !audioManager.aiAutoAnalyze {
        Text(
          "Real-time mode: audio is processed on-the-fly when you activate a karaoke feature. Only the unplayed portion is processed for faster results."
        )
      } else if !audioManager.aiEnabled {
        Text(
          "Enable AI Audio Processing to access vocal removal, bass enhance, and other AI-powered audio features."
        )
      } else {
        Text(
          "Powered by on-device AI. Audio is separated into vocals and instrumentals using a neural network model."
        )
      }
    }
  }

  @ViewBuilder
  private var karaokeSection: some View {
    Section {
      Toggle(
        "Vocal Removal",
        isOn: Binding(
          get: { audioManager.karaokeMode },
          set: { audioManager.karaokeMode = $0 }
        )
      )
        .tint(.appAccent)
        .disabled(audioManager.isBackgroundKaraokeLocked)
      if audioManager.isBackgroundKaraokeLocked {
        Text("Available after background processing finishes for the current song.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      if audioManager.karaokeMode {
        HStack {
          Text("Removal Level")
          Spacer()
          Text(aiStrengthLabel)
            .foregroundStyle(.secondary)
        }
        StrengthSlider(value: $audioManager.aiVocalStrength)
      }
      Toggle("Bass Enhance", isOn: $audioManager.bassEnhanceMode)
        .tint(.appAccent)
      if audioManager.bassEnhanceMode {
        HStack {
          Text("Strength")
          Spacer()
          Text(bassStrengthLabel)
            .foregroundStyle(.secondary)
        }
        StrengthSlider(value: $audioManager.bassEnhanceStrength)
      }
      Toggle("Vocal Enhance", isOn: $audioManager.vocalEnhanceMode)
        .tint(.appAccent)
      if audioManager.vocalEnhanceMode {
        HStack {
          Text("Strength")
          Spacer()
          Text(vocalEnhanceStrengthLabel)
            .foregroundStyle(.secondary)
        }
        StrengthSlider(value: $audioManager.vocalEnhanceStrength)
      }
      Toggle("Instrumental Enhance", isOn: $audioManager.instrumentalEnhanceMode)
        .tint(.appAccent)
      if audioManager.instrumentalEnhanceMode {
        HStack {
          Text("Strength")
          Spacer()
          Text(instrumentalEnhanceStrengthLabel)
            .foregroundStyle(.secondary)
        }
        StrengthSlider(value: $audioManager.instrumentalEnhanceStrength)
      }
    } header: {
      Text("Karaoke")
    } footer: {
      Text(
        "Karaoke effects use on-device AI to separate vocals and instrumentals in real time. For best results, use headphones or external speakers."
      )
    }
  }

  // MARK: - Storage Section

  @ViewBuilder
  private var storageSection: some View {
    Section {
      Button {
        pendingAction = .clearImageCache
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "photo")
            .font(.system(size: 16))
            .foregroundColor(.appAccent)
            .frame(width: 24)
          Text("Image Cache")
            .foregroundColor(.primary)
          Spacer()
          Text("\(cacheManager.formattedImageCacheSize()) / 2 GB")
            .font(.subheadline.weight(.medium))
            .foregroundColor(.secondary)
        }
      }
      Button {
        pendingAction = .clearMusicCache
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "music.note")
            .font(.system(size: 16))
            .foregroundColor(.appAccent)
            .frame(width: 24)
          Text("Music Cache")
            .foregroundColor(.primary)
          Spacer()
          Text("\(cacheManager.formattedMusicCacheSize()) / 4 GB")
            .font(.subheadline.weight(.medium))
            .foregroundColor(.secondary)
        }
      }
      Button {
        pendingAction = .clearLyricsCache
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "text.quote")
            .font(.system(size: 16))
            .foregroundColor(.appAccent)
            .frame(width: 24)
          Text("Lyrics Cache")
            .foregroundColor(.primary)
          Spacer()
          Text("\(cacheManager.formattedLyricsCacheSize()) / 2 GB")
            .font(.subheadline.weight(.medium))
            .foregroundColor(.secondary)
        }
      }
      Button(role: .destructive) {
        pendingAction = .removeDownloads
      } label: {
        Text("Remove All Downloads")
      }
      Button(role: .destructive) {
        pendingAction = .clearRecentlyPlayed
      } label: {
        Text("Clear Recently Played")
      }
    } header: {
      Text("Storage")
    } footer: {
      Text(
        "Tap an indicator to clear that cache. Image cache is limited to 2 GB, music cache (including AI stems) to 4 GB, and lyrics cache to 2 GB. Items older than 6 months are automatically cleaned. Downloads are exempt from these limits."
      )
    }
  }

  // MARK: - Actions

  private func perform(_ action: SettingsDestructiveAction) {
    switch action {
    case .removeDownloads:
      DownloadManager.shared.removeAll()
    case .clearImageCache:
      cacheManager.clearImageCache()
    case .clearMusicCache:
      audioManager.clearCache()
      cacheManager.clearMusicCache()
    case .clearLyricsCache:
      cacheManager.clearLyricsCache()
    case .clearRecentlyPlayed:
      RecentlyPlayedStore.shared.reset()
    }
  }

  private func exportDebugLogs() {
    #if canImport(UIKit)
      let logs = DebugLogger.exportLogs()
      let av = UIActivityViewController(activityItems: [logs], applicationActivities: nil)
      if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
        let root = windowScene.windows.first?.rootViewController
      {
        root.present(av, animated: true)
      }
    #endif
  }

  // MARK: - Labels

  private var aiStrengthLabel: String {
    let s = audioManager.aiVocalStrength
    if s >= 0.99 { return "Maximum" }
    if s >= 0.75 { return "Strong" }
    if s >= 0.45 { return "Medium" }
    if s >= 0.15 { return "Light" }
    return "Off"
  }
  private var bassStrengthLabel: String {
    strengthText(audioManager.bassEnhanceStrength)
  }
  private var vocalEnhanceStrengthLabel: String {
    strengthText(audioManager.vocalEnhanceStrength)
  }
  private var instrumentalEnhanceStrengthLabel: String {
    strengthText(audioManager.instrumentalEnhanceStrength)
  }
  private func strengthText(_ v: Float) -> String {
    if v < 0.15 { return "Almost off" }
    if v < 0.45 { return "Light" }
    if v < 0.75 { return "Medium" }
    if v < 0.95 { return "Strong" }
    return "Maximum"
  }
}

private struct StrengthSlider: View {
  @Binding var value: Float
  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(Color.primary.opacity(0.15))
        Capsule()
          .fill(Color.appAccent)
          .frame(width: max(8, geo.size.width * CGFloat(value)))
      }
      .frame(height: 6)
      .frame(maxHeight: .infinity, alignment: .center)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { drag in
            let v = max(0, min(1, drag.location.x / geo.size.width))
            value = Float(v)
          }
      )
    }
    .frame(height: 28)
  }
}

private struct EqualizerBands: View {
  @Binding var gainsDB: [Float]
  private let range: ClosedRange<Float> = -12...12
  var body: some View {
    HStack(alignment: .bottom, spacing: 6) {
      ForEach(0..<AudioKitPlayback.eqBandCount, id: \.self) { i in
        VStack(spacing: 6) {
          Text(gainLabel(gainsDB[i]))
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(height: 12)
          EqualizerBand(value: bandBinding(i), range: range)
            .frame(maxWidth: .infinity)
            .frame(height: 140)
          Text(frequencyLabel(Double(AudioKitPlayback.bandFrequencies[i])))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(height: 12)
        }
      }
    }
  }
  private func bandBinding(_ i: Int) -> Binding<Float> {
    Binding(
      get: { gainsDB.indices.contains(i) ? gainsDB[i] : 0 },
      set: { newValue in
        guard gainsDB.indices.contains(i) else { return }
        var copy = gainsDB
        copy[i] = newValue
        gainsDB = copy
      }
    )
  }
  private func gainLabel(_ db: Float) -> String {
    if abs(db) < 0.05 { return "0" }
    return String(format: "%+.0f", db)
  }
  private func frequencyLabel(_ hz: Double) -> String {
    if hz >= 1000 {
      let k = hz / 1000
      if k.truncatingRemainder(dividingBy: 1) == 0 {
        return "\(Int(k))k"
      }
      return String(format: "%.1fk", k)
    }
    return "\(Int(hz))"
  }
}

private struct EqualizerBand: View {
  @Binding var value: Float
  let range: ClosedRange<Float>
  var body: some View {
    GeometryReader { geo in
      let span = range.upperBound - range.lowerBound
      let normalized = (value - range.lowerBound) / span
      let trackHeight = geo.size.height
      let knobY = trackHeight - CGFloat(normalized) * trackHeight
      let zeroY = trackHeight - CGFloat((0 - range.lowerBound) / span) * trackHeight
      ZStack(alignment: .top) {
        Capsule()
          .fill(Color.primary.opacity(0.15))
          .frame(width: 4)
          .frame(maxWidth: .infinity)
        if value >= 0 {
          Capsule()
            .fill(Color.appAccent)
            .frame(width: 4, height: max(0, zeroY - knobY))
            .offset(y: knobY)
        } else {
          Capsule()
            .fill(Color.appAccent)
            .frame(width: 4, height: max(0, knobY - zeroY))
            .offset(y: zeroY)
        }
        Circle()
          .fill(Color.appAccent)
          .frame(width: 18, height: 18)
          .offset(y: knobY - 9)
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { drag in
            let y = max(0, min(trackHeight, drag.location.y))
            let n = 1 - (y / trackHeight)
            value = Float(range.lowerBound) + Float(n) * span
          }
      )
    }
  }
}

private enum SettingsDestructiveAction {
  case removeDownloads
  case clearImageCache
  case clearMusicCache
  case clearLyricsCache
  case clearRecentlyPlayed
  var title: String {
    switch self {
    case .removeDownloads: return "Remove all downloads?"
    case .clearImageCache: return "Clear image cache?"
    case .clearMusicCache: return "Clear music cache?"
    case .clearLyricsCache: return "Clear lyrics cache?"
    case .clearRecentlyPlayed: return "Clear recently played?"
    }
  }
  var message: String {
    switch self {
    case .removeDownloads:
      return "All offline downloads will be deleted from this device."
    case .clearImageCache:
      return "Cached artwork and images will be removed. They will redownload as you use the app."
    case .clearMusicCache:
      return
        "Cached audio files and AI stems will be removed. Songs will re-buffer as you play them."
    case .clearLyricsCache:
      return "Cached lyrics and translated lyrics will be removed."
    case .clearRecentlyPlayed:
      return "Your recently played history will be cleared."
    }
  }
  var actionLabel: String {
    switch self {
    case .removeDownloads: return "Remove All Downloads"
    case .clearImageCache: return "Clear Image Cache"
    case .clearMusicCache: return "Clear Music Cache"
    case .clearLyricsCache: return "Clear Lyrics Cache"
    case .clearRecentlyPlayed: return "Clear Recently Played"
    }
  }
}

private struct CrossfadeDurationRow: View {
  @Binding var seconds: Double
  private let range: ClosedRange<Double> = 1...15
  private var displayLabel: String {
    let s = Int(seconds.rounded())
    return "\(s) Second\(s == 1 ? "" : "s")"
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Duration")
        Spacer()
        Text(displayLabel)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      Slider(
        value: Binding(
          get: { seconds },
          set: { seconds = $0.rounded() }
        ),
        in: range,
        step: 1
      ) {
        Text("Crossfade Duration")
      } minimumValueLabel: {
        Text("1s")
          .font(.caption2)
          .foregroundStyle(.secondary)
      } maximumValueLabel: {
        Text("15s")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .tint(.appAccent)
    }
    .padding(.vertical, 2)
  }
}
