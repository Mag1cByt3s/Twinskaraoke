import AVFoundation
import AudioKit
import Combine
import Foundation

enum AudioKitPlaybackMode { case single, aiStems }

enum AudioKitPlaybackRampStyle {
  case equalPower  // cos/sin curve — constant perceived loudness
  case linear  // straight line — faster cuts
}

@MainActor
final class AudioKitPlayback {
  typealias Mode = AudioKitPlaybackMode
  typealias RampStyle = AudioKitPlaybackRampStyle

  let engine = AudioEngine()
  let mainPlayer = AudioPlayer()
  let crossfadePlayer = AudioPlayer()
  let stemVocals = AudioPlayer()
  let stemDrums = AudioPlayer()
  let stemBass = AudioPlayer()
  let stemOther = AudioPlayer()
  private let mixer: Mixer
  let userEQ = AVAudioUnitEQ(numberOfBands: 10)
  let bassEQ = AVAudioUnitEQ(numberOfBands: 1)

  private(set) var mode: Mode = .single
  private(set) var currentURL: URL?
  private(set) var aiStartOffset: TimeInterval = 0

  private var suppressionToken: UInt64 = 0
  private var _paused: Bool = false

  private(set) var isCrossfading = false

  private var crossfadeTimer: Timer?

  private var crossfadeDuration: TimeInterval = 0

  private var crossfadeElapsed: TimeInterval = 0

  private var crossfadeRamp: RampStyle = .equalPower

  var onCrossfadeCompleted: (() -> Void)?

  var onPlaybackEnded: (() -> Void)?
  var onPlaybackError: ((Error) -> Void)?

  static let eqBandCount = 10
  static let bandFrequencies: [Float] = [
    31.5, 63, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000,
  ]

  init() {
    mixer = Mixer(mainPlayer, crossfadePlayer, stemVocals, stemDrums, stemBass, stemOther)
    crossfadePlayer.volume = 0
    stemVocals.volume = 0
    stemDrums.volume = 0
    stemBass.volume = 0
    stemOther.volume = 0

    for i in 0..<10 {
      let band = userEQ.bands[i]
      band.filterType = .parametric
      band.frequency = AudioKitPlayback.bandFrequencies[i]
      band.bandwidth = 1.0
      band.gain = 0
      band.bypass = false
    }
    userEQ.bypass = true

    let bassBand = bassEQ.bands[0]
    bassBand.filterType = .lowShelf
    bassBand.frequency = 250
    bassBand.bandwidth = 1.0
    bassBand.gain = 0
    bassBand.bypass = true
    bassEQ.bypass = true

    let bassNode = AVAudioUnitWrapperNode(input: mixer, unit: bassEQ)
    let userNode = AVAudioUnitWrapperNode(input: bassNode, unit: userEQ)
    engine.output = userNode

    mainPlayer.completionHandler = { [weak self] in
      guard let self else { return }
      let token = self.suppressionToken
      DispatchQueue.main.async {
        guard self.suppressionToken == token else { return }
        self.onPlaybackEnded?()
      }
    }
    stemDrums.completionHandler = { [weak self] in
      guard let self else { return }
      let token = self.suppressionToken
      DispatchQueue.main.async {
        guard self.suppressionToken == token else { return }
        if self.mode == .aiStems { self.onPlaybackEnded?() }
      }
    }

    do { try engine.start() } catch {
      onPlaybackError?(error)
    }
  }

  func startEngineIfNeeded() {
    if !engine.avEngine.isRunning {
      do { try engine.start() } catch { onPlaybackError?(error) }
    }
  }

  nonisolated static func hasValidAudioHeader(at url: URL) -> Bool {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
    defer { try? handle.close() }
    guard let header = try? handle.read(upToCount: 12), header.count >= 4 else { return false }
    if header[0] == 0xFF && (header[1] & 0xE0) == 0xE0 { return true }
    if header[0] == 0x49 && header[1] == 0x44 && header[2] == 0x33 { return true }
    if header[0] == 0x52 && header[1] == 0x49 && header[2] == 0x46 && header[3] == 0x46 {
      return true
    }
    if header[0] == 0x46 && header[1] == 0x4F && header[2] == 0x52 && header[3] == 0x4D {
      return true
    }
    if header[0] == 0x63 && header[1] == 0x61 && header[2] == 0x66 && header[3] == 0x66 {
      return true
    }
    if header[0] == 0x66 && header[1] == 0x4C && header[2] == 0x61 && header[3] == 0x43 {
      return true
    }
    return false
  }

  private func loadIntoPlayer(_ player: AudioPlayer, url: URL) throws {
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw NSError(
        domain: NSOSStatusErrorDomain, code: 1_685_348_671,
        userInfo: [NSLocalizedDescriptionKey: "Audio file not found: \(url.lastPathComponent)"])
    }
    let headerOK = AudioKitPlayback.hasValidAudioHeader(at: url)
    if headerOK {
      if let file = try? AVAudioFile(forReading: url) {
        if file.processingFormat.channelCount == 2 {
          try player.load(file: file)
          return
        }
        if let stereo = AudioKitPlayback.convertToStereo(file: file) {
          player.load(buffer: stereo)
          return
        }
      }
      if let file = try? AVAudioFile(
        forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
      {
        if file.processingFormat.channelCount == 2 {
          try player.load(file: file)
          return
        }
        if let stereo = AudioKitPlayback.convertToStereo(file: file) {
          player.load(buffer: stereo)
          return
        }
      }
    }
    if let buffer = AudioKitPlayback.decodeFileToBuffer(url: url) {
      player.load(buffer: buffer)
      return
    }
    let file = try AVAudioFile(forReading: url)
    try player.load(file: file)
  }

  nonisolated static func decodeFileToBuffer(url: URL) -> AVAudioPCMBuffer? {
    let asset = AVURLAsset(url: url)
    let tracks = asset.tracks(withMediaType: .audio)
    guard let track = tracks.first else { return nil }
    guard let reader = try? AVAssetReader(asset: asset) else { return nil }
    let sampleRate: Double = 44100
    let outputSettings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: sampleRate,
      AVNumberOfChannelsKey: 2,
      AVLinearPCMBitDepthKey: 32,
      AVLinearPCMIsFloatKey: true,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: true,
    ]
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
    reader.add(output)
    guard reader.startReading() else { return nil }
    guard
      let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
        channels: 2, interleaved: false)
    else { return nil }
    let totalFrames = AVAudioFrameCount(max(1, asset.duration.seconds * sampleRate) + 8192)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames)
    else { return nil }
    buffer.frameLength = 0
    while reader.status == .reading {
      guard let sb = output.copyNextSampleBuffer(), let bb = CMSampleBufferGetDataBuffer(sb)
      else { break }
      let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sb))
      var length = 0
      var dataPtr: UnsafeMutablePointer<Int8>?
      if CMBlockBufferGetDataPointer(
        bb, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length,
        dataPointerOut: &dataPtr) != noErr
      {
        continue
      }
      guard let dataPtr else { continue }
      let writeStart = buffer.frameLength
      let writeEnd = writeStart + frames
      if writeEnd > buffer.frameCapacity { break }
      let perChannelBytes = Int(frames) * MemoryLayout<Float>.size
      if let channelData = buffer.floatChannelData {
        memcpy(
          channelData[0].advanced(by: Int(writeStart)),
          dataPtr, perChannelBytes)
        if length >= perChannelBytes * 2 {
          memcpy(
            channelData[1].advanced(by: Int(writeStart)),
            dataPtr.advanced(by: perChannelBytes), perChannelBytes)
        }
      }
      buffer.frameLength = writeEnd
    }
    if reader.status == .failed { return nil }
    return buffer.frameLength > 0 ? buffer : nil
  }

  nonisolated private static func convertToStereo(file: AVAudioFile) -> AVAudioPCMBuffer? {
    let srcFormat = file.processingFormat
    guard srcFormat.channelCount == 1 else { return nil }
    let frameCount = AVAudioFrameCount(file.length)
    guard frameCount > 0 else { return nil }
    guard let monoBuf = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: frameCount)
    else { return nil }
    do { try file.read(into: monoBuf) } catch { return nil }
    return monoToStereo(monoBuf)
  }

  nonisolated static func ensureStereo(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    guard buffer.format.channelCount == 1 else { return nil }
    return monoToStereo(buffer)
  }

  nonisolated private static func monoToStereo(_ mono: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    let frames = mono.frameLength
    guard frames > 0,
      let stereoFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: mono.format.sampleRate,
        channels: 2, interleaved: false),
      let stereo = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: frames)
    else { return nil }
    stereo.frameLength = frames
    guard let monoData = mono.floatChannelData?[0],
      let leftData = stereo.floatChannelData?[0],
      let rightData = stereo.floatChannelData?[1]
    else { return nil }
    let byteCount = Int(frames) * MemoryLayout<Float>.size
    memcpy(leftData, monoData, byteCount)
    memcpy(rightData, monoData, byteCount)
    return stereo
  }

  private func safeStart(_ startAt: TimeInterval, durations: TimeInterval...) -> TimeInterval? {
    guard startAt > 0.05, startAt.isFinite else { return nil }
    let validDurations = durations.filter { $0.isFinite && $0 > 0 }
    guard let limit = validDurations.min() else { return nil }
    let capped = limit - 0.25
    guard capped > 0.05, startAt < capped else { return nil }
    return startAt
  }

  private func resetCrossfadePlayback() {
    crossfadeTimer?.invalidate()
    crossfadeTimer = nil
    pendingCrossfadeURL = nil
    preloadedCrossfadeURL = nil
    isCrossfading = false
    crossfadeDuration = 0
    crossfadeElapsed = 0
    crossfadeStartMainVol = 1.0
    crossfadeStartVocalsVol = 0
    crossfadeStartDrumsVol = 0
    crossfadeStartBassVol = 0
    crossfadeStartOtherVol = 0
    crossfadePlayer.stop()
    crossfadePlayer.volume = 0
  }

  // MARK: - Single-track playback

  func play(url: URL, startAt: TimeInterval = 0) {
    do {
      _paused = false
      suppressionToken &+= 1
      resetCrossfadePlayback()
      stopAllStems()
      mainPlayer.stop()
      try loadIntoPlayer(mainPlayer, url: url)
      currentURL = url
      mode = .single
      aiStartOffset = 0
      mainPlayer.volume = 1
      resetBassEQ()
      startEngineIfNeeded()
      let from = safeStart(startAt, durations: mainPlayer.duration)
      mainPlayer.play(from: from)
    } catch {
      onPlaybackError?(error)
    }
  }

  // MARK: - AI stems playback

  func switchToStems(
    vocalsURL: URL, drumsURL: URL, bassURL: URL, otherURL: URL,
    startOffset: TimeInterval
  ) {
    do {
      _paused = false
      suppressionToken &+= 1
      resetCrossfadePlayback()
      let pos = mainPlayer.currentTime
      let stemPos = max(0, pos - startOffset)
      stopAllStems()
      try loadIntoPlayer(stemVocals, url: vocalsURL)
      try loadIntoPlayer(stemDrums, url: drumsURL)
      try loadIntoPlayer(stemBass, url: bassURL)
      try loadIntoPlayer(stemOther, url: otherURL)
      aiStartOffset = max(0, startOffset)
      mode = .aiStems
      startEngineIfNeeded()
      let from = safeStart(stemPos, durations: stemDrums.duration)
      stemVocals.volume = 1
      stemDrums.volume = 1
      stemBass.volume = 1
      stemOther.volume = 1
      stemVocals.play(from: from)
      stemDrums.play(from: from)
      stemBass.play(from: from)
      stemOther.play(from: from)
      mainPlayer.stop()
      mainPlayer.volume = 0
    } catch {
      onPlaybackError?(error)
    }
  }

  func revertToMain() {
    guard mode == .aiStems else { return }
    _paused = false
    let pos = stemDrums.currentTime + aiStartOffset
    suppressionToken &+= 1
    resetCrossfadePlayback()
    let from = safeStart(pos, durations: mainPlayer.duration)
    mainPlayer.volume = 1
    resetBassEQ()
    startEngineIfNeeded()
    mainPlayer.play(from: from)
    stopAllStems()
    mode = .single
    aiStartOffset = 0
  }

  private func stopAllStems() {
    stemVocals.stop()
    stemDrums.stop()
    stemBass.stop()
    stemOther.stop()
    stemVocals.volume = 0
    stemDrums.volume = 0
    stemBass.volume = 0
    stemOther.volume = 0
  }

  func setStemVolumes(vocals: Float, drums: Float, bass: Float, other: Float) {
    stemVocals.volume = AUValue(max(0, min(2, vocals)))
    stemDrums.volume = AUValue(max(0, min(2, drums)))
    stemBass.volume = AUValue(max(0, min(2, bass)))
    stemOther.volume = AUValue(max(0, min(2, other)))
  }

  // MARK: - Playback state

  var currentTime: TimeInterval {
    if mode == .aiStems {
      return aiStartOffset + stemDrums.currentTime
    }
    return mainPlayer.currentTime
  }

  var duration: TimeInterval {
    if mode == .aiStems, stemDrums.duration.isFinite, stemDrums.duration > 0 {
      return aiStartOffset + stemDrums.duration
    }
    return mainPlayer.duration
  }

  var isPlaying: Bool {
    if _paused { return false }
    if mode == .aiStems { return stemDrums.isPlaying }
    return mainPlayer.isPlaying
  }

  func pause() {
    _paused = true
    if mode == .aiStems {
      stemVocals.pause()
      stemDrums.pause()
      stemBass.pause()
      stemOther.pause()
    } else {
      mainPlayer.pause()
    }
  }

  func resume() {
    _paused = false
    startEngineIfNeeded()
    if mode == .aiStems {
      stemVocals.play()
      stemDrums.play()
      stemBass.play()
      stemOther.play()
    } else {
      mainPlayer.play()
    }
  }

  func stop() {
    _paused = false
    suppressionToken &+= 1
    resetCrossfadePlayback()
    mainPlayer.stop()
    stopAllStems()
    currentURL = nil
    aiStartOffset = 0
    mode = .single
    resetBassEQ()
  }

  @discardableResult
  func seek(to seconds: TimeInterval) -> Bool {
    guard seconds.isFinite else { return true }
    if mode == .aiStems {
      let stemTarget = seconds - aiStartOffset
      if stemTarget < 0 { return false }
      let dur = stemDrums.duration
      guard dur.isFinite, dur > 0 else { return true }
      let upper = dur - 0.5
      guard upper > 0 else { return true }
      let target = max(0, min(stemTarget, upper))
      suppressionToken &+= 1
      let delta = target - stemDrums.currentTime
      if abs(delta) > 0.01 {
        stemVocals.seek(time: delta)
        stemDrums.seek(time: delta)
        stemBass.seek(time: delta)
        stemOther.seek(time: delta)
      }
      return true
    }
    let dur = mainPlayer.duration
    guard dur.isFinite, dur > 0 else { return true }
    let upper = dur - 0.5
    guard upper > 0 else { return true }
    let target = max(0, min(seconds, upper))
    suppressionToken &+= 1
    let delta = target - mainPlayer.currentTime
    if abs(delta) > 0.01 { mainPlayer.seek(time: delta) }
    return true
  }

  func setEQEnabled(_ on: Bool) { userEQ.bypass = !on }

  func setEQGains(_ gains: [Float]) {
    for i in 0..<min(gains.count, userEQ.bands.count) {
      userEQ.bands[i].gain = gains[i]
    }
  }

  func setBassEQGain(dB: Float) {
    let band = bassEQ.bands[0]
    band.gain = dB
    let active = dB > 0.01
    band.bypass = !active
    bassEQ.bypass = !active
  }

  func resetBassEQ() {
    setBassEQGain(dB: 0)
  }

  func setMasterVolume(_ v: Float) {
    mixer.volume = AUValue(max(0, min(1, v)))
  }

  // MARK: - Crossfade

  func preloadCrossfade(url: URL) {
    guard !isCrossfading else { return }
    do {
      try loadIntoPlayer(crossfadePlayer, url: url)
      preloadedCrossfadeURL = url
      crossfadePlayer.volume = 0
    } catch {
      preloadedCrossfadeURL = nil
    }
  }

  func beginCrossfade(url: URL, duration: TimeInterval, ramp: RampStyle) {
    let alreadyPreloaded = (preloadedCrossfadeURL == url)

    crossfadeTimer?.invalidate()
    crossfadeTimer = nil
    preloadedCrossfadeURL = nil
    if isCrossfading {
      isCrossfading = false
      if !alreadyPreloaded {
        crossfadePlayer.stop()
        crossfadePlayer.volume = 0
      }
      if mode == .single {
        mainPlayer.volume = 1.0
      } else if mode == .aiStems {
        setStemVolumes(
          vocals: crossfadeStartVocalsVol,
          drums: crossfadeStartDrumsVol,
          bass: crossfadeStartBassVol,
          other: crossfadeStartOtherVol)
      }
    }

    if !alreadyPreloaded {
      do {
        try loadIntoPlayer(crossfadePlayer, url: url)
      } catch {
        onPlaybackError?(error)
        return
      }
    }
    crossfadeDuration = max(0.5, duration)
    crossfadeElapsed = 0
    crossfadeRamp = ramp
    isCrossfading = true
    pendingCrossfadeURL = url

    crossfadeStartMainVol = Float(mainPlayer.volume)
    crossfadeStartVocalsVol = Float(stemVocals.volume)
    crossfadeStartDrumsVol = Float(stemDrums.volume)
    crossfadeStartBassVol = Float(stemBass.volume)
    crossfadeStartOtherVol = Float(stemOther.volume)

    crossfadePlayer.volume = 0
    startEngineIfNeeded()
    crossfadePlayer.play()

    let interval: TimeInterval = 1.0 / 60.0
    crossfadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
      @MainActor [weak self] timer in
      guard let self else {
        timer.invalidate()
        return
      }
      self.crossfadeElapsed += interval
      let t = Float(min(1.0, self.crossfadeElapsed / self.crossfadeDuration))

      let outVol: Float
      let inVol: Float
      switch self.crossfadeRamp {
      case .equalPower:
        outVol = cos(t * .pi / 2)
        inVol = sin(t * .pi / 2)
      case .linear:
        outVol = 1.0 - t
        inVol = t
      }

      if self.mode == .aiStems {
        self.stemVocals.volume = AUValue(max(0, self.crossfadeStartVocalsVol * outVol))
        self.stemDrums.volume = AUValue(max(0, self.crossfadeStartDrumsVol * outVol))
        self.stemBass.volume = AUValue(max(0, self.crossfadeStartBassVol * outVol))
        self.stemOther.volume = AUValue(max(0, self.crossfadeStartOtherVol * outVol))
      } else {
        self.mainPlayer.volume = AUValue(max(0, outVol))
      }
      self.crossfadePlayer.volume = AUValue(max(0, inVol))

      if t >= 1.0 {
        self.finalizeCrossfade()
      }
    }
  }

  func cancelCrossfade() {
    crossfadeTimer?.invalidate()
    crossfadeTimer = nil
    preloadedCrossfadeURL = nil
    guard isCrossfading else {
      crossfadePlayer.stop()
      crossfadePlayer.volume = 0
      return
    }
    isCrossfading = false
    crossfadePlayer.stop()
    crossfadePlayer.volume = 0
    if mode == .aiStems {
      setStemVolumes(
        vocals: crossfadeStartVocalsVol,
        drums: crossfadeStartDrumsVol,
        bass: crossfadeStartBassVol,
        other: crossfadeStartOtherVol)
    } else {
      mainPlayer.volume = 1.0
    }
  }

  private func finalizeCrossfade() {
    crossfadeTimer?.invalidate()
    crossfadeTimer = nil
    isCrossfading = false

    suppressionToken &+= 1
    mainPlayer.stop()
    if mode == .aiStems {
      stopAllStems()
    }

    crossfadePlayer.volume = 1.0

    if let url = pendingCrossfadeURL {
      do {
        let resumeTime = crossfadePlayer.currentTime
        try loadIntoPlayer(mainPlayer, url: url)
        mode = .single
        aiStartOffset = 0
        stopAllStems()
        mainPlayer.volume = 1.0
        resetBassEQ()
        let from = safeStart(resumeTime, durations: mainPlayer.duration)
        mainPlayer.play(from: from)
        currentURL = url
        crossfadePlayer.stop()
        crossfadePlayer.volume = 0
      } catch {
        crossfadePlayer.stop()
        crossfadePlayer.volume = 0
        onPlaybackError?(error)
      }
    } else {
      crossfadePlayer.stop()
      crossfadePlayer.volume = 0
    }

    pendingCrossfadeURL = nil
    onCrossfadeCompleted?()
  }

  private var pendingCrossfadeURL: URL?

  private var preloadedCrossfadeURL: URL?

  private var crossfadeStartMainVol: Float = 1.0
  private var crossfadeStartVocalsVol: Float = 0
  private var crossfadeStartDrumsVol: Float = 0
  private var crossfadeStartBassVol: Float = 0
  private var crossfadeStartOtherVol: Float = 0
}

final class AVAudioUnitWrapperNode: Node {
  let avAudioNode: AVAudioNode
  let connections: [Node]
  init(input: Node, unit: AVAudioNode) {
    self.avAudioNode = unit
    self.connections = [input]
  }
}
