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
  let stemInstrumental = AudioPlayer()
  let instEQ = AVAudioUnitEQ(numberOfBands: 1)
  private let mainMixer: Mixer
  private let instEQWrapper: AVAudioUnitWrapperNode
  let userEQ = AVAudioUnitEQ(numberOfBands: 10)

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
    instEQWrapper = AVAudioUnitWrapperNode(input: stemInstrumental, unit: instEQ)
    mainMixer = Mixer(mainPlayer, crossfadePlayer, stemVocals, instEQWrapper)
    crossfadePlayer.volume = 0
    stemVocals.volume = 0
    stemInstrumental.volume = 0

    for i in 0..<10 {
      let band = userEQ.bands[i]
      band.filterType = .parametric
      band.frequency = AudioKitPlayback.bandFrequencies[i]
      band.bandwidth = 1.0
      band.gain = 0
      band.bypass = false
    }
    userEQ.bypass = true

    let instBand = instEQ.bands[0]
    instBand.filterType = .lowShelf
    instBand.frequency = 250
    instBand.bandwidth = 1.0
    instBand.gain = 0
    instBand.bypass = true
    instEQ.bypass = true

    let userNode = AVAudioUnitWrapperNode(input: mainMixer, unit: userEQ)
    engine.output = userNode

    mainPlayer.completionHandler = { [weak self] in
      guard let self else { return }
      let token = self.suppressionToken
      DispatchQueue.main.async {
        guard self.suppressionToken == token else { return }
        if self.mode == .single { self.onPlaybackEnded?() }
      }
    }
    stemInstrumental.completionHandler = { [weak self] in
      guard let self else { return }
      let token = self.suppressionToken
      DispatchQueue.main.async {
        guard self.suppressionToken == token else { return }
        if self.mode == .aiStems { self.onPlaybackEnded?() }
      }
    }

    do { try engine.start() } catch {
      DebugLogger.log("AudioKit engine start failed: \(error)", category: .playback)
      onPlaybackError?(error)
    }
  }

  func startEngineIfNeeded() {
    if !engine.avEngine.isRunning {
      do {
        try engine.start()
        DebugLogger.log("AudioKit engine restarted", category: .playback)
      } catch {
        DebugLogger.log("AudioKit engine restart failed: \(error)", category: .playback)
        onPlaybackError?(error)
      }
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
      let err = NSError(
        domain: NSOSStatusErrorDomain, code: 1_685_348_671,
        userInfo: [NSLocalizedDescriptionKey: "Audio file not found: \(url.lastPathComponent)"])
      DebugLogger.log("Load failed — file not found: \(url.lastPathComponent)", category: .playback)
      throw err
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
    crossfadeStartInstrumentalVol = 0
    crossfadePlayer.stop()
    crossfadePlayer.volume = 0
  }

  // MARK: - Single-track playback

  func play(url: URL, startAt: TimeInterval = 0) {
    DebugLogger.log("AudioKit play single: \(url.lastPathComponent)", category: .playback)
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
      resetInstrumentalEQ()
      startEngineIfNeeded()
      let from = safeStart(startAt, durations: mainPlayer.duration)
      mainPlayer.play(from: from)
    } catch {
      onPlaybackError?(error)
    }
  }

  // MARK: - AI stems playback

  func playStems(
    originalURL: URL, vocalsURL: URL, instrumentsURL: URL,
    startOffset: TimeInterval, startAt: TimeInterval = 0
  ) {
    DebugLogger.log(
      "AudioKit play stems: vocals=\(vocalsURL.lastPathComponent), inst=\(instrumentsURL.lastPathComponent)",
      category: .playback)
    do {
      _paused = false
      suppressionToken &+= 1
      resetCrossfadePlayback()
      stopAllStems()
      mainPlayer.stop()
      try loadIntoPlayer(mainPlayer, url: originalURL)
      currentURL = originalURL
      mainPlayer.volume = 0
      try loadIntoPlayer(stemVocals, url: vocalsURL)
      try loadIntoPlayer(stemInstrumental, url: instrumentsURL)
      aiStartOffset = max(0, startOffset)
      mode = .aiStems
      resetInstrumentalEQ()
      startEngineIfNeeded()
      let stemPos = max(0, startAt - aiStartOffset)
      let from = safeStart(stemPos, durations: stemInstrumental.duration)
      stemVocals.volume = 1
      stemInstrumental.volume = 1
      stemVocals.play(from: from)
      stemInstrumental.play(from: from)
    } catch {
      onPlaybackError?(error)
    }
  }

  func switchToStems(
    vocalsURL: URL, instrumentsURL: URL,
    startOffset: TimeInterval
  ) {
    DebugLogger.log("AudioKit switching to stems at offset \(startOffset)", category: .playback)
    do {
      _paused = false
      suppressionToken &+= 1
      resetCrossfadePlayback()
      let pos = mainPlayer.currentTime
      let stemPos = max(0, pos - startOffset)
      stopAllStems()
      try loadIntoPlayer(stemVocals, url: vocalsURL)
      try loadIntoPlayer(stemInstrumental, url: instrumentsURL)
      aiStartOffset = max(0, startOffset)
      mode = .aiStems
      startEngineIfNeeded()
      let from = safeStart(stemPos, durations: stemInstrumental.duration)
      stemVocals.volume = 1
      stemInstrumental.volume = 1
      stemVocals.play(from: from)
      stemInstrumental.play(from: from)
      mainPlayer.stop()
      mainPlayer.volume = 0
    } catch {
      onPlaybackError?(error)
    }
  }

  func revertToMain() {
    guard mode == .aiStems else { return }
    DebugLogger.log("AudioKit reverting to main player", category: .playback)
    _paused = false
    let pos = stemInstrumental.currentTime + aiStartOffset
    suppressionToken &+= 1
    resetCrossfadePlayback()
    let dur = mainPlayer.duration.isFinite && mainPlayer.duration > 0
      ? mainPlayer.duration : (stemInstrumental.duration + aiStartOffset)
    mainPlayer.volume = 1
    resetInstrumentalEQ()
    startEngineIfNeeded()
    if let from = safeStart(pos, durations: dur) {
      mainPlayer.play(from: from)
    } else {
      let clamped = min(max(0, pos), max(0, dur - 0.25))
      if clamped > 0.05, clamped.isFinite {
        mainPlayer.play(from: clamped)
      } else {
        mainPlayer.play()
      }
    }
    stopAllStems()
    mode = .single
    aiStartOffset = 0
  }

  private func stopAllStems() {
    stemVocals.stop()
    stemInstrumental.stop()
    stemVocals.volume = 0
    stemInstrumental.volume = 0
  }

  func setStemVolumes(vocals: Float, instrumental: Float) {
    stemVocals.volume = AUValue(max(0, min(2, vocals)))
    stemInstrumental.volume = AUValue(max(0, min(2, instrumental)))
  }

  func setInstrumentalEQGain(dB: Float) {
    let band = instEQ.bands[0]
    band.gain = dB
    let active = dB > 0.01
    band.bypass = !active
    instEQ.bypass = !active
  }

  func resetInstrumentalEQ() {
    setInstrumentalEQGain(dB: 0)
  }

  // MARK: - Playback state

  var currentTime: TimeInterval {
    if mode == .aiStems {
      return aiStartOffset + stemInstrumental.currentTime
    }
    return mainPlayer.currentTime
  }

  var duration: TimeInterval {
    if mode == .aiStems, stemInstrumental.duration.isFinite, stemInstrumental.duration > 0 {
      return aiStartOffset + stemInstrumental.duration
    }
    return mainPlayer.duration
  }

  var isPlaying: Bool {
    if _paused { return false }
    if mode == .aiStems { return stemInstrumental.isPlaying }
    return mainPlayer.isPlaying
  }

  func pause() {
    _paused = true
    suppressionToken &+= 1
    if mode == .aiStems {
      stemVocals.pause()
      stemInstrumental.pause()
    } else {
      mainPlayer.pause()
    }
  }

  func resume() {
    _paused = false
    suppressionToken &+= 1
    startEngineIfNeeded()
    if mode == .aiStems {
      stemVocals.play()
      stemInstrumental.play()
    } else {
      mainPlayer.play()
    }
  }

  func stop() {
    DebugLogger.log("AudioKit stop", category: .playback)
    _paused = false
    suppressionToken &+= 1
    resetCrossfadePlayback()
    mainPlayer.stop()
    stopAllStems()
    currentURL = nil
    aiStartOffset = 0
    mode = .single
    resetInstrumentalEQ()
  }

  @discardableResult
  func seek(to seconds: TimeInterval) -> Bool {
    guard seconds.isFinite else { return true }
    if mode == .aiStems {
      let stemTarget = seconds - aiStartOffset
      if stemTarget < 0 { return false }
      let dur = stemInstrumental.duration
      guard dur.isFinite, dur > 0 else { return true }
      let upper = dur - 0.5
      guard upper > 0 else { return true }
      let target = max(0, min(stemTarget, upper))
      suppressionToken &+= 1
      let delta = target - stemInstrumental.currentTime
      if abs(delta) > 0.01 {
        stemVocals.seek(time: delta)
        stemInstrumental.seek(time: delta)
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

  func setMasterVolume(_ v: Float) {
    mainMixer.volume = AUValue(max(0, min(1, v)))
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
    DebugLogger.log(
      "Crossfade begin: \(url.lastPathComponent), duration=\(duration), ramp=\(ramp)",
      category: .playback)
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
          instrumental: crossfadeStartInstrumentalVol)
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
    crossfadeStartInstrumentalVol = Float(stemInstrumental.volume)

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
        self.stemInstrumental.volume = AUValue(max(0, self.crossfadeStartInstrumentalVol * outVol))
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
        instrumental: crossfadeStartInstrumentalVol)
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
        resetInstrumentalEQ()
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
  private var crossfadeStartInstrumentalVol: Float = 0
}

final class AVAudioUnitWrapperNode: Node {
  let avAudioNode: AVAudioNode
  let connections: [Node]
  init(input: Node, unit: AVAudioNode) {
    self.avAudioNode = unit
    self.connections = [input]
  }
}
