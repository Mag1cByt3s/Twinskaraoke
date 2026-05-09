import AVFoundation
import MediaToolbox

enum KaraokeMode {
  case vocalRemoval
  case bassEnhance
  case combined
}

enum VocalRemovalLevel: Int, CaseIterable {
  case off = 0
  case light = 1
  case medium = 2
  case strong = 3
  case maximum = 4
  var centerAttenuation: Float {
    switch self {
    case .off: return 0
    case .light: return 0.6
    case .medium: return 0.8
    case .strong: return 0.95
    case .maximum: return 1.0
    }
  }
  var label: String {
    switch self {
    case .off: return "Off"
    case .light: return "Light"
    case .medium: return "Medium"
    case .strong: return "Strong"
    case .maximum: return "Maximum"
    }
  }
}

enum KaraokeAudioProcessor {
  static var vocalRemovalLevel: VocalRemovalLevel = .off
  static var vocalAttenuation: Float = 0
  static var mode: KaraokeMode = .vocalRemoval
  @MainActor
  static func attachTap(to playerItem: AVPlayerItem) {
    let asset = playerItem.asset
    Task { @MainActor in
      let tracks: [AVAssetTrack]
      if #available(iOS 15.0, *) {
        tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
      } else {
        tracks = asset.tracks(withMediaType: .audio)
      }
      guard let track = tracks.first else { return }
      let processCallback: MTAudioProcessingTapProcessCallback
      switch mode {
      case .vocalRemoval: processCallback = vocalRemovalTapProcess
      case .bassEnhance: processCallback = bassEnhanceTapProcess
      case .combined: processCallback = combinedTapProcess
      }
      var callbacks = MTAudioProcessingTapCallbacks(
        version: kMTAudioProcessingTapCallbacksVersion_0,
        clientInfo: nil,
        init: nil,
        finalize: nil,
        prepare: tapPrepare,
        unprepare: nil,
        process: processCallback
      )
      var unmanagedTap: Unmanaged<MTAudioProcessingTap>?
      let status = withUnsafeMutablePointer(to: &unmanagedTap) { ptr -> OSStatus in
        ptr.withMemoryRebound(to: Optional<MTAudioProcessingTap>.self, capacity: 1) { rebound in
          MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PreEffects,
            rebound
          )
        }
      }
      guard status == noErr, let tap = unmanagedTap?.takeRetainedValue() else { return }
      let mix = AVMutableAudioMix()
      let params = AVMutableAudioMixInputParameters(track: track)
      params.audioTapProcessor = tap
      mix.inputParameters = [params]
      playerItem.audioMix = mix
    }
  }
}

private struct Biquad {
  var b0: Float = 0, b1: Float = 0, b2: Float = 0
  var a1: Float = 0, a2: Float = 0
  var x1: Float = 0, x2: Float = 0
  var y1: Float = 0, y2: Float = 0
  mutating func process(_ x0: Float) -> Float {
    let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
    x2 = x1; x1 = x0
    y2 = y1; y1 = y0
    return y0
  }
  mutating func reset() {
    x1 = 0; x2 = 0; y1 = 0; y2 = 0
  }
  static func highpass(freq: Double, q: Double, sampleRate: Double) -> Biquad {
    let w0 = 2.0 * Double.pi * freq / sampleRate
    let alpha = sin(w0) / (2.0 * q)
    let cosW0 = cos(w0)
    let a0 = Float(1.0 + alpha)
    var bq = Biquad()
    bq.b0 = Float((1.0 + cosW0) / 2.0) / a0
    bq.b1 = Float(-(1.0 + cosW0)) / a0
    bq.b2 = Float((1.0 + cosW0) / 2.0) / a0
    bq.a1 = Float(-2.0 * cosW0) / a0
    bq.a2 = Float(1.0 - alpha) / a0
    return bq
  }
  static func lowpass(freq: Double, q: Double, sampleRate: Double) -> Biquad {
    let w0 = 2.0 * Double.pi * freq / sampleRate
    let alpha = sin(w0) / (2.0 * q)
    let cosW0 = cos(w0)
    let a0 = Float(1.0 + alpha)
    var bq = Biquad()
    bq.b0 = Float((1.0 - cosW0) / 2.0) / a0
    bq.b1 = Float(1.0 - cosW0) / a0
    bq.b2 = Float((1.0 - cosW0) / 2.0) / a0
    bq.a1 = Float(-2.0 * cosW0) / a0
    bq.a2 = Float(1.0 - alpha) / a0
    return bq
  }
}

private struct TapFormat {
  var channels: Int
  var isInterleaved: Bool
  var isFloat: Bool
  var sampleRate: Double
}

private var tapFormat = TapFormat(
  channels: 2, isInterleaved: true, isFloat: true, sampleRate: 44100)

private var vrHPMid1 = Biquad()
private var vrHPMid2 = Biquad()

private var cvrHPMid1 = Biquad()
private var cvrHPMid2 = Biquad()

private func setupVocalFilters(sampleRate: Double) {
  vrHPMid1 = Biquad.highpass(freq: 100, q: 0.7071, sampleRate: sampleRate)
  vrHPMid2 = Biquad.highpass(freq: 100, q: 0.7071, sampleRate: sampleRate)
  cvrHPMid1 = Biquad.highpass(freq: 100, q: 0.7071, sampleRate: sampleRate)
  cvrHPMid2 = Biquad.highpass(freq: 100, q: 0.7071, sampleRate: sampleRate)
}

private let tapPrepare: MTAudioProcessingTapPrepareCallback = {
  _, _, format in
  let asbd = format.pointee
  let channels = Int(asbd.mChannelsPerFrame)
  let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
  let isInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
  let sr = asbd.mSampleRate > 0 ? asbd.mSampleRate : 44100
  tapFormat = TapFormat(
    channels: channels, isInterleaved: isInterleaved, isFloat: isFloat, sampleRate: sr)
  setupVocalFilters(sampleRate: sr)
  bassLowState = 0
  bassHighState = 0
  combinedBassLowState = 0
  combinedBassHighState = 0
}

private let vocalRemovalTapProcess: MTAudioProcessingTapProcessCallback = {
  tap, numFrames, _, bufferList, framesProcessedOut, flagsOut in
  var timeRange = CMTimeRange()
  let status = MTAudioProcessingTapGetSourceAudio(
    tap, numFrames, bufferList, flagsOut, &timeRange, framesProcessedOut)
  guard status == noErr else { return }
  let level = KaraokeAudioProcessor.vocalRemovalLevel
  guard level != .off else { return }
  let abl = UnsafeMutableAudioBufferListPointer(bufferList)
  let frames = Int(framesProcessedOut.pointee)
  guard frames > 0 else { return }
  let fmt = tapFormat
  guard fmt.channels >= 2, fmt.isFloat else { return }
  let att = level.centerAttenuation
  if fmt.isInterleaved {
    guard let buf = abl[0].mData?.assumingMemoryBound(to: Float.self) else { return }
    let stride = fmt.channels
    for i in 0..<frames {
      let li = i * stride
      let ri = li + 1
      let l = buf[li]
      let r = buf[ri]
      let mid = (l + r) * 0.5
      let midHP = vrHPMid2.process(vrHPMid1.process(mid))
      buf[li] = l - midHP * att
      buf[ri] = r - midHP * att
    }
  } else {
    guard abl.count >= 2,
      let lBuf = abl[0].mData?.assumingMemoryBound(to: Float.self),
      let rBuf = abl[1].mData?.assumingMemoryBound(to: Float.self)
    else { return }
    for i in 0..<frames {
      let mid = (lBuf[i] + rBuf[i]) * 0.5
      let midHP = vrHPMid2.process(vrHPMid1.process(mid))
      lBuf[i] = lBuf[i] - midHP * att
      rBuf[i] = rBuf[i] - midHP * att
    }
  }
}

private var bassLowState: Float = 0
private var bassHighState: Float = 0
private let bassCutoffHz: Double = 120
private let trebleCutoffHz: Double = 9000

private let bassEnhanceTapProcess: MTAudioProcessingTapProcessCallback = {
  tap, numFrames, _, bufferList, framesProcessedOut, flagsOut in
  var timeRange = CMTimeRange()
  let status = MTAudioProcessingTapGetSourceAudio(
    tap, numFrames, bufferList, flagsOut, &timeRange, framesProcessedOut)
  guard status == noErr else { return }
  let attenuation = KaraokeAudioProcessor.vocalAttenuation
  guard attenuation > 0.001 else { return }
  let abl = UnsafeMutableAudioBufferListPointer(bufferList)
  let frames = Int(framesProcessedOut.pointee)
  guard frames > 0 else { return }
  let fmt = tapFormat
  guard fmt.channels >= 2, fmt.isFloat else { return }
  let shaped = attenuation * attenuation * (3 - 2 * attenuation)
  let keep = 1.0 - shaped
  let makeupGain: Float = 1.0 + shaped
  let dt = 1.0 / fmt.sampleRate
  let alphaLow = Float(dt / (1.0 / (2.0 * .pi * bassCutoffHz) + dt))
  let alphaHigh = Float(dt / (1.0 / (2.0 * .pi * trebleCutoffHz) + dt))
  var lowState = bassLowState
  var highState = bassHighState
  if fmt.isInterleaved {
    guard let buf = abl[0].mData?.assumingMemoryBound(to: Float.self) else { return }
    let stride = fmt.channels
    for i in 0..<frames {
      let li = i * stride
      let ri = li + 1
      let l = buf[li]
      let r = buf[ri]
      let mid = (l + r) * 0.5
      let side = (l - r) * 0.5
      lowState += alphaLow * (mid - lowState)
      highState += alphaHigh * (mid - highState)
      let bass = lowState
      let air = mid - highState
      let vocalBand = highState - lowState
      let processedMid = bass + air + vocalBand * keep
      let outL = (processedMid + side) * makeupGain
      let outR = (processedMid - side) * makeupGain
      buf[li] = tanhf(outL)
      buf[ri] = tanhf(outR)
    }
  } else {
    guard abl.count >= 2,
      let l = abl[0].mData?.assumingMemoryBound(to: Float.self),
      let r = abl[1].mData?.assumingMemoryBound(to: Float.self)
    else { return }
    for i in 0..<frames {
      let mid = (l[i] + r[i]) * 0.5
      let side = (l[i] - r[i]) * 0.5
      lowState += alphaLow * (mid - lowState)
      highState += alphaHigh * (mid - highState)
      let bass = lowState
      let air = mid - highState
      let vocalBand = highState - lowState
      let processedMid = bass + air + vocalBand * keep
      let outL = (processedMid + side) * makeupGain
      let outR = (processedMid - side) * makeupGain
      l[i] = tanhf(outL)
      r[i] = tanhf(outR)
    }
  }
  bassLowState = lowState
  bassHighState = highState
}

private var combinedBassLowState: Float = 0
private var combinedBassHighState: Float = 0

private let combinedTapProcess: MTAudioProcessingTapProcessCallback = {
  tap, numFrames, _, bufferList, framesProcessedOut, flagsOut in
  var timeRange = CMTimeRange()
  let status = MTAudioProcessingTapGetSourceAudio(
    tap, numFrames, bufferList, flagsOut, &timeRange, framesProcessedOut)
  guard status == noErr else { return }
  let abl = UnsafeMutableAudioBufferListPointer(bufferList)
  let frames = Int(framesProcessedOut.pointee)
  guard frames > 0 else { return }
  let fmt = tapFormat
  guard fmt.channels >= 2, fmt.isFloat else { return }
  let level = KaraokeAudioProcessor.vocalRemovalLevel
  let vocalAtt = level.centerAttenuation
  let bassAtt = KaraokeAudioProcessor.vocalAttenuation
  let bassShaped = bassAtt * bassAtt * (3 - 2 * bassAtt)
  let bassKeep: Float = 1.0 - bassShaped
  let makeupGain: Float = 1.0 + bassShaped
  let dt = 1.0 / fmt.sampleRate
  let alphaBassLow = Float(dt / (1.0 / (2.0 * .pi * bassCutoffHz) + dt))
  let alphaBassHigh = Float(dt / (1.0 / (2.0 * .pi * trebleCutoffHz) + dt))
  var bLowState = combinedBassLowState
  var bHighState = combinedBassHighState
  if fmt.isInterleaved {
    guard let buf = abl[0].mData?.assumingMemoryBound(to: Float.self) else { return }
    let stride = fmt.channels
    for i in 0..<frames {
      let li = i * stride
      let ri = li + 1
      var l = buf[li]
      var r = buf[ri]
      if level != .off {
        let mid = (l + r) * 0.5
        let midHP = cvrHPMid2.process(cvrHPMid1.process(mid))
        l = l - midHP * vocalAtt
        r = r - midHP * vocalAtt
      }
      if bassAtt > 0.001 {
        let mid = (l + r) * 0.5
        let side = (l - r) * 0.5
        bLowState += alphaBassLow * (mid - bLowState)
        bHighState += alphaBassHigh * (mid - bHighState)
        let bass = bLowState
        let air = mid - bHighState
        let vocalBand = bHighState - bLowState
        let processedMid = bass + air + vocalBand * bassKeep
        l = tanhf((processedMid + side) * makeupGain)
        r = tanhf((processedMid - side) * makeupGain)
      }
      buf[li] = l
      buf[ri] = r
    }
  } else {
    guard abl.count >= 2,
      let lBuf = abl[0].mData?.assumingMemoryBound(to: Float.self),
      let rBuf = abl[1].mData?.assumingMemoryBound(to: Float.self)
    else { return }
    for i in 0..<frames {
      var l = lBuf[i]
      var r = rBuf[i]
      if level != .off {
        let mid = (l + r) * 0.5
        let midHP = cvrHPMid2.process(cvrHPMid1.process(mid))
        l = l - midHP * vocalAtt
        r = r - midHP * vocalAtt
      }
      if bassAtt > 0.001 {
        let mid = (l + r) * 0.5
        let side = (l - r) * 0.5
        bLowState += alphaBassLow * (mid - bLowState)
        bHighState += alphaBassHigh * (mid - bHighState)
        let bass = bLowState
        let air = mid - bHighState
        let vocalBand = bHighState - bLowState
        let processedMid = bass + air + vocalBand * bassKeep
        l = tanhf((processedMid + side) * makeupGain)
        r = tanhf((processedMid - side) * makeupGain)
      }
      lBuf[i] = l
      rBuf[i] = r
    }
  }
  combinedBassLowState = bLowState
  combinedBassHighState = bHighState
}
