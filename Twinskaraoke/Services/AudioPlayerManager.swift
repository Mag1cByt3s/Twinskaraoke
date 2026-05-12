import AVFoundation
import Combine
import Foundation
import MediaPlayer
import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

enum RepeatMode {
  case off, all, one
  var symbol: String {
    switch self {
    case .off, .all: return "repeat"
    case .one: return "repeat.1"
    }
  }
  var isActive: Bool { self != .off }
  func next() -> RepeatMode {
    switch self {
    case .off: return .all
    case .all: return .one
    case .one: return .off
    }
  }
}

private final class AudioDownloadSession: NSObject, URLSessionDataDelegate {
  private let songID: String
  private let partialURL: URL
  private let finalURL: URL
  private var fileHandle: FileHandle?
  private var task: URLSessionDataTask?
  private var session: URLSession?
  var onCompletion: ((URL?) -> Void)?
  init(songID: String) {
    self.songID = songID
    self.finalURL = AudioPlayerManager.audioCacheDir.appendingPathComponent("\(songID).mp3")
    self.partialURL = AudioPlayerManager.audioCacheDir.appendingPathComponent(
      "\(songID).mp3.partial")
    super.init()
  }
  func start(from remoteURL: URL) {
    try? FileManager.default.removeItem(at: partialURL)
    FileManager.default.createFile(atPath: partialURL.path, contents: nil)
    self.fileHandle = try? FileHandle(forWritingTo: partialURL)
    session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    task = session?.dataTask(with: remoteURL)
    task?.resume()
  }
  func cancel() {
    task?.cancel()
    session?.invalidateAndCancel()
    fileHandle?.closeFile()
    try? FileManager.default.removeItem(at: partialURL)
  }
  func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    completionHandler(.allow)
  }
  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    fileHandle?.write(data)
  }
  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    fileHandle?.closeFile()
    fileHandle = nil
    session.invalidateAndCancel()
    if error != nil {
      try? FileManager.default.removeItem(at: partialURL)
      DispatchQueue.main.async { [weak self] in self?.onCompletion?(nil) }
      return
    }
    if let http = task.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
      try? FileManager.default.removeItem(at: partialURL)
      DispatchQueue.main.async { [weak self] in self?.onCompletion?(nil) }
      return
    }
    try? FileManager.default.removeItem(at: finalURL)
    do {
      try FileManager.default.moveItem(at: partialURL, to: finalURL)
      let final = finalURL
      DispatchQueue.main.async { [weak self] in self?.onCompletion?(final) }
    } catch {
      try? FileManager.default.removeItem(at: partialURL)
      DispatchQueue.main.async { [weak self] in self?.onCompletion?(nil) }
    }
  }
}

private enum AudioEffect {
  case karaoke, bassEnhance, vocalEnhance, backgroundEnhance
}

class AudioPlayerManager: ObservableObject {
  static let shared = AudioPlayerManager()
  @Published var currentSong: Song?
  @Published var isPlaying = false
  @Published var isBuffering = false
  @Published var progress: Double = 0.0
  @Published var queue: [Song] = []
  @Published var showFullScreen = false
  @Published var isEditingProgress = false
  @Published var volume: Double = 1.0
  @Published var isUserScrubbingVolume: Bool = false
  @Published var routeIcon: String = "airplayaudio"
  @Published var routeName: String = ""
  @Published var repeatMode: RepeatMode = .off
  @Published var isShuffled: Bool = false
  @Published var autoplayEnabled: Bool = true
  @Published var isRadioMode: Bool = false
  @Published var radioArtworkURL: URL?

  @Published var karaokeMode: Bool = false {
    didSet {
      guard !_suppressModeSwitch else { return }
      if karaokeMode {
        disableOtherModes(except: .karaoke)
      }
      applyMLSeparationIfNeeded()
    }
  }
  @Published var aiVocalStrength: Float = AudioPlayerManager.loadAIVocalStrength() {
    didSet {
      let clamped = min(1, max(0, aiVocalStrength))
      if clamped != aiVocalStrength {
        aiVocalStrength = clamped
        return
      }
      UserDefaults.standard.set(Double(aiVocalStrength), forKey: "nk.aiVocalStrength")
      applyAIMixVolumes()
    }
  }
  private static func loadAIVocalStrength() -> Float {
    let raw = UserDefaults.standard.object(forKey: "nk.aiVocalStrength") as? Double ?? 1.0
    return Float(min(1, max(0, raw)))
  }

  @Published var bassEnhanceMode: Bool = false {
    didSet {
      guard !_suppressModeSwitch else { return }
      if bassEnhanceMode {
        disableOtherModes(except: .bassEnhance)
      }
      applyMLSeparationIfNeeded()
    }
  }
  @Published var bassEnhanceStrength: Float = AudioPlayerManager.loadFloat(
    "nk.bassEnhanceStrength", default: 0.5)
  {
    didSet {
      UserDefaults.standard.set(bassEnhanceStrength, forKey: "nk.bassEnhanceStrength")
      applyAIMixVolumes()
    }
  }

  @Published var vocalEnhanceMode: Bool = false {
    didSet {
      guard !_suppressModeSwitch else { return }
      if vocalEnhanceMode {
        disableOtherModes(except: .vocalEnhance)
      }
      applyMLSeparationIfNeeded()
    }
  }
  @Published var vocalEnhanceStrength: Float = AudioPlayerManager.loadFloat(
    "nk.vocalEnhanceStrength", default: 0.5)
  {
    didSet {
      UserDefaults.standard.set(vocalEnhanceStrength, forKey: "nk.vocalEnhanceStrength")
      applyAIMixVolumes()
    }
  }

  @Published var backgroundEnhanceMode: Bool = false {
    didSet {
      guard !_suppressModeSwitch else { return }
      if backgroundEnhanceMode {
        disableOtherModes(except: .backgroundEnhance)
      }
      applyMLSeparationIfNeeded()
    }
  }
  @Published var backgroundEnhanceStrength: Float = AudioPlayerManager.loadFloat(
    "nk.backgroundEnhanceStrength", default: 0.5)
  {
    didSet {
      UserDefaults.standard.set(backgroundEnhanceStrength, forKey: "nk.backgroundEnhanceStrength")
      applyAIMixVolumes()
    }
  }

  @Published var eqEnabled: Bool = UserDefaults.standard.bool(forKey: "nk.eqEnabled") {
    didSet {
      UserDefaults.standard.set(eqEnabled, forKey: "nk.eqEnabled")
      audioKit.setEQEnabled(eqEnabled)
    }
  }
  private var eqPresetIsApplying = false
  @Published var eqPreset: EQPreset = {
    let raw = UserDefaults.standard.string(forKey: "nk.eqPreset") ?? ""
    return EQPreset(rawValue: raw) ?? .flat
  }()
  {
    didSet {
      UserDefaults.standard.set(eqPreset.rawValue, forKey: "nk.eqPreset")
      guard eqPreset != .custom else { return }
      eqPresetIsApplying = true
      eqGainsDB = eqPreset.gains
      eqPresetIsApplying = false
    }
  }
  @Published var eqGainsDB: [Float] = {
    (UserDefaults.standard.array(forKey: "nk.eqGainsDB") as? [Float])
      ?? Array(repeating: 0, count: 10)
  }()
  {
    didSet {
      UserDefaults.standard.set(eqGainsDB, forKey: "nk.eqGainsDB")
      audioKit.setEQGains(eqGainsDB)
      if !eqPresetIsApplying && eqPreset != .custom && eqGainsDB != eqPreset.gains {
        eqPreset = .custom
      }
    }
  }

  @Published var autoMixEnabled: Bool =
    (UserDefaults.standard.object(forKey: "nk.autoMixEnabled") as? Bool ?? true)
  {
    didSet {
      UserDefaults.standard.set(autoMixEnabled, forKey: "nk.autoMixEnabled")
      if autoMixEnabled && crossfadeEnabled { crossfadeEnabled = false }
    }
  }
  @Published var crossfadeEnabled: Bool =
    (UserDefaults.standard.object(forKey: "nk.crossfadeEnabled") as? Bool ?? false)
  {
    didSet {
      UserDefaults.standard.set(crossfadeEnabled, forKey: "nk.crossfadeEnabled")
      if crossfadeEnabled && autoMixEnabled { autoMixEnabled = false }
    }
  }
  @Published var crossfadeSeconds: Double = AudioPlayerManager.loadCrossfadeSeconds() {
    didSet {
      let clamped = min(15, max(1, crossfadeSeconds))
      if clamped != crossfadeSeconds {
        crossfadeSeconds = clamped
        return
      }
      UserDefaults.standard.set(crossfadeSeconds, forKey: "nk.crossfadeSeconds")
    }
  }
  @Published var upcomingSong: Song?
  #if canImport(UIKit)
    @Published var nowPlayingArtwork: UIImage?
  #endif
  private static func loadCrossfadeSeconds() -> Double {
    let raw = UserDefaults.standard.object(forKey: "nk.crossfadeSeconds") as? Double ?? 6.0
    return min(15, max(1, raw))
  }
  private static func loadFloat(_ key: String, default defaultValue: Float) -> Float {
    if UserDefaults.standard.object(forKey: key) != nil {
      return UserDefaults.standard.float(forKey: key)
    }
    return defaultValue
  }

  private let audioKit = AudioKitPlayback()
  private let transitionCoordinator = TransitionCoordinator()
  private var radioPlayer: AVPlayer?
  private var radioTimeObserver: (player: AVPlayer, token: Any)?
  private var pollTimer: Timer?

  private var _suppressModeSwitch = false
  private var originalQueue: [Song] = []
  private var cancellables = Set<AnyCancellable>()
  private var artworkURL: URL?
  private var artworkTask: URLSessionDataTask?
  private var downloadSession: AudioDownloadSession?
  private var currentPlaybackURL: URL?
  private var instrumentalTask: Task<Void, Never>?
  private var separationGeneration: UInt64 = 0

  #if canImport(UIKit)
    private var bgTaskID: UIBackgroundTaskIdentifier = .invalid
    private var trackTransitionTaskID: UIBackgroundTaskIdentifier = .invalid
  #endif

  static let audioCacheDir: URL = {
    let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
      .appendingPathComponent("AudioCache")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }()

  #if canImport(UIKit)
    private static let artworkCache: NSCache<NSURL, UIImage> = {
      let cache = NSCache<NSURL, UIImage>()
      cache.countLimit = 32
      cache.totalCostLimit = 32 * 1024 * 1024
      return cache
    }()
    private static let artworkMaxPixel: CGFloat = 600
  #endif

  var anyAIEffectActive: Bool {
    karaokeMode || bassEnhanceMode || vocalEnhanceMode || backgroundEnhanceMode
  }

  init() {
    configureAudioSessionCategory()
    activateAudioSession()
    AudioPlayerManager.cleanupOrphanPartialCacheFiles()
    #if os(iOS)
      UIApplication.shared.beginReceivingRemoteControlEvents()
    #endif
    setupRemoteCommands()

    audioKit.onPlaybackEnded = { [weak self] in
      guard let self, !self.isRadioMode else { return }
      guard self.isPlaying else { return }
      guard !self.audioKit.isCrossfading else { return }
      self.playNextOrRandom()
    }
    audioKit.onCrossfadeCompleted = { [weak self] in
      guard let self else { return }
      self.transitionCoordinatorDidFinish()
    }
    audioKit.setEQEnabled(eqEnabled)
    audioKit.setEQGains(eqGainsDB)
    startPollTimer()

    transitionCoordinator.audioKit = audioKit
    transitionCoordinator.onBeginTransition = { [weak self] plan in
      self?.handleTransitionBegin(plan: plan)
    }
    transitionCoordinator.onUpcomingSongDetermined = { [weak self] song in
      self?.upcomingSong = song
    }

    NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
      .sink { [weak self] note in self?.handleInterruption(note) }
      .store(in: &cancellables)
    NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
      .sink { [weak self] note in self?.handleRouteChange(note) }
      .store(in: &cancellables)
    updateRouteIcon()
    AVAudioSession.sharedInstance().publisher(for: \.outputVolume)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] sysVol in
        guard let self = self else { return }
        guard !self.isUserScrubbingVolume else { return }
        let v = Double(sysVol)
        if abs(self.volume - v) > 0.01 { self.volume = v }
      }
      .store(in: &cancellables)
    #if canImport(UIKit)
      NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
        .sink { [weak self] _ in self?.handleBackgroundTransition() }
        .store(in: &cancellables)
      NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
        .sink { [weak self] _ in
          AudioPlayerManager.artworkCache.removeAllObjects()
          self?.instrumentalTask?.cancel()
          self?.instrumentalTask = nil
        }
        .store(in: &cancellables)
    #endif
  }

  deinit {
    pollTimer?.invalidate()
    instrumentalTask?.cancel()
    if let existing = radioTimeObserver {
      existing.player.removeTimeObserver(existing.token)
    }
    artworkTask?.cancel()
    downloadSession?.cancel()
    radioPlayer?.pause()
  }

  private func disableOtherModes(except keep: AudioEffect) {
    _suppressModeSwitch = true
    if keep != .karaoke { karaokeMode = false }
    if keep != .bassEnhance { bassEnhanceMode = false }
    if keep != .vocalEnhance { vocalEnhanceMode = false }
    if keep != .backgroundEnhance { backgroundEnhanceMode = false }
    _suppressModeSwitch = false
  }

  private var currentActiveEffect: AudioEffect? {
    if karaokeMode { return .karaoke }
    if bassEnhanceMode { return .bassEnhance }
    if vocalEnhanceMode { return .vocalEnhance }
    if backgroundEnhanceMode { return .backgroundEnhance }
    return nil
  }

  private func applyAIMixVolumes() {
    guard audioKit.mode == .aiStems else { return }
    audioKit.resetBassEQ()
    if karaokeMode {
      audioKit.setStemVolumes(vocals: max(0, 1.0 - aiVocalStrength), drums: 1, bass: 1, other: 1)
    } else if bassEnhanceMode {
      audioKit.setStemVolumes(vocals: 1, drums: 1, bass: 1 + 0.5 * bassEnhanceStrength, other: 1)
    } else if vocalEnhanceMode {
      audioKit.setStemVolumes(vocals: 1 + 0.5 * vocalEnhanceStrength, drums: 1, bass: 1, other: 1)
    } else if backgroundEnhanceMode {
      audioKit.setStemVolumes(vocals: 1, drums: 1 + 0.5 * backgroundEnhanceStrength, bass: 1 + 0.5 * backgroundEnhanceStrength, other: 1 + 0.5 * backgroundEnhanceStrength)
    } else {
      audioKit.setStemVolumes(vocals: 1, drums: 1, bass: 1, other: 1)
    }
  }

  private func startPollTimer() {
    pollTimer?.invalidate()
    pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {
      @MainActor [weak self] _ in
      guard let self else { return }
      guard !self.isRadioMode else { return }
      guard !self.isEditingProgress else { return }
      let totalDur: Double
      if let song = self.currentSong, song.duration > 0 {
        totalDur = Double(song.duration)
      } else {
        totalDur = self.audioKit.duration
      }
      guard totalDur.isFinite, totalDur > 0 else { return }
      let t = self.audioKit.currentTime
      self.progress = min(1.0, max(0.0, t / totalDur))
      self.updateNowPlayingElapsed(t)

      if self.repeatMode != .one {
        self.transitionCoordinator.poll(
          currentTime: t,
          totalDuration: totalDur,
          currentSong: self.currentSong,
          queue: self.queue,
          autoMixEnabled: self.autoMixEnabled,
          crossfadeEnabled: self.crossfadeEnabled,
          crossfadeSeconds: self.crossfadeSeconds,
          aiEffectActive: self.anyAIEffectActive,
          autoplayEnabled: self.autoplayEnabled
        )
      }
    }
  }

  func play(song: Song, context: [Song] = []) {
    if isRadioMode { RadioController.shared.stop() }
    stopRadioPlayer()
    isRadioMode = false
    radioArtworkURL = nil
    transitionCoordinator.reset()
    audioKit.cancelCrossfade()
    reportPlayCount(for: song.id)
    enrichSongMetadataIfNeeded(for: song)
    if currentSong?.id != song.id {
      progress = 0
      withAnimation(.easeInOut(duration: 0.32)) {
        currentSong = song
      }
    } else {
      currentSong = song
    }
    if !context.isEmpty {
      queue = context
      if isShuffled {
        originalQueue = context
        var rest = queue.filter { $0.id != song.id }
        rest.shuffle()
        queue = [song] + rest
      } else {
        originalQueue = []
      }
    }
    downloadSession?.cancel()
    downloadSession = nil
    let cacheURL = AudioPlayerManager.audioCacheDir.appendingPathComponent("\(song.id).mp3")
    let downloadedURL = DownloadManager.shared.localURL(for: song.id)
    if FileManager.default.fileExists(atPath: downloadedURL.path) {
      startPlayingFile(downloadedURL)
      applyMLSeparationIfNeeded()
      return
    }
    if FileManager.default.fileExists(atPath: cacheURL.path) {
      startPlayingFile(cacheURL)
      applyMLSeparationIfNeeded()
      return
    }
    guard let remoteURL = song.audioURL else { return }
    audioKit.stop()
    isPlaying = false
    isBuffering = true
    let songID = song.id
    let session = AudioDownloadSession(songID: songID)
    downloadSession = session
    session.onCompletion = { [weak self] url in
      guard let self else { return }
      guard self.currentSong?.id == songID else { return }
      self.isBuffering = false
      if let url {
        self.startPlayingFile(url)
        self.applyMLSeparationIfNeeded()
      }
    }
    session.start(from: remoteURL)
  }

  private func startPlayingFile(_ url: URL) {
    instrumentalTask?.cancel()
    instrumentalTask = nil
    separationGeneration &+= 1
    VocalSeparator.shared.cancel()
    currentPlaybackURL = url
    configureAudioSessionCategory()
    activateAudioSession()
    NotificationCenter.default.post(name: MediaPlaybackCoordinator.audioWillPlay, object: nil)
    audioKit.play(url: url)
    isPlaying = true
    isBuffering = false
    updateNowPlayingInfo(reloadArtwork: true)
    #if canImport(UIKit)
      endTrackTransitionBackgroundTask()
    #endif
  }

  func togglePlayPause() {
    if isRadioMode {
      if isPlaying {
        radioPlayer?.pause()
      } else {
        NotificationCenter.default.post(name: MediaPlaybackCoordinator.audioWillPlay, object: nil)
        radioPlayer?.play()
      }
      isPlaying.toggle()
      updateNowPlayingInfo(reloadArtwork: false)
      return
    }
    if isPlaying {
      audioKit.pause()
      isPlaying = false
    } else {
      NotificationCenter.default.post(name: MediaPlaybackCoordinator.audioWillPlay, object: nil)
      audioKit.resume()
      isPlaying = true
    }
    updateNowPlayingInfo(reloadArtwork: false)
  }

  func pauseIfPlaying() {
    guard isPlaying else { return }
    if isRadioMode {
      radioPlayer?.pause()
    } else {
      audioKit.pause()
    }
    isPlaying = false
    updateNowPlayingInfo(reloadArtwork: false)
  }

  func seek(to fraction: Double) {
    guard fraction.isFinite, (0.0...1.0).contains(fraction) else { return }
    if isRadioMode { return }
    let audioDur = audioKit.duration
    let totalDur: Double
    if audioDur.isFinite, audioDur > 0 {
      totalDur = audioDur
    } else if let song = currentSong, song.duration > 0 {
      totalDur = Double(song.duration)
    } else {
      return
    }
    let target = min(totalDur * fraction, totalDur - 1.5)
    guard target >= 0 else { return }
    audioKit.seek(to: target)
    updateNowPlayingInfo(reloadArtwork: false)
  }

  func playNextOrRandom() {
    if isRadioMode { return }
    if transitionCoordinator.state.isCrossfading { return }
    transitionCoordinator.reset()
    #if canImport(UIKit)
      beginTrackTransitionBackgroundTask()
    #endif
    configureAudioSessionCategory()
    activateAudioSession()
    if repeatMode == .one, let current = currentSong {
      play(song: current)
      return
    }
    if let current = currentSong, !queue.isEmpty,
      let idx = queue.firstIndex(where: { $0.id == current.id }),
      idx + 1 < queue.count
    {
      play(song: queue[idx + 1])
    } else if repeatMode == .all, let first = queue.first {
      play(song: first)
    } else if autoplayEnabled {
      fetchRandomTrending()
    } else {
      isPlaying = false
      audioKit.pause()
      updateNowPlayingInfo(reloadArtwork: false)
      #if canImport(UIKit)
        endTrackTransitionBackgroundTask()
      #endif
    }
  }

  func playPrevious() {
    if isRadioMode { return }
    if let current = currentSong, !queue.isEmpty,
      let idx = queue.firstIndex(where: { $0.id == current.id }),
      idx - 1 >= 0
    {
      play(song: queue[idx - 1])
    } else {
      seek(to: 0)
    }
  }

  func toggleRepeat() { repeatMode = repeatMode.next() }
  func toggleShuffle() {
    isShuffled.toggle()
    if isShuffled {
      originalQueue = queue
      guard let current = currentSong else { return }
      var rest = queue.filter { $0.id != current.id }
      rest.shuffle()
      queue = [current] + rest
    } else if !originalQueue.isEmpty {
      queue = originalQueue
      originalQueue = []
    }
  }
  func playInOrder(song: Song, context: [Song]) {
    isShuffled = false
    originalQueue = []
    play(song: song, context: context)
  }
  func playShuffled(from songs: [Song]) {
    guard let pick = songs.randomElement() else { return }
    let shuffled = songs.shuffled()
    isShuffled = true
    originalQueue = songs
    play(song: pick, context: shuffled)
  }
  func toggleAutoplay() { autoplayEnabled.toggle() }
  func moveInUpNext(from source: IndexSet, to destination: Int) {
    guard let current = currentSong,
      let baseIdx = queue.firstIndex(where: { $0.id == current.id })
    else { return }
    let upNextStart = baseIdx + 1
    guard upNextStart < queue.count else { return }
    var upNext = Array(queue[upNextStart...])
    upNext.move(fromOffsets: source, toOffset: destination)
    queue = Array(queue[..<upNextStart]) + upNext
  }
  func removeFromUpNext(at offsets: IndexSet) {
    guard let current = currentSong,
      let baseIdx = queue.firstIndex(where: { $0.id == current.id })
    else { return }
    let upNextStart = baseIdx + 1
    guard upNextStart < queue.count else { return }
    var upNext = Array(queue[upNextStart...])
    upNext.remove(atOffsets: offsets)
    queue = Array(queue[..<upNextStart]) + upNext
  }

  func playRadio(streamURL: URL, song: Song, artworkURL: URL?) {
    let alreadyOnSameStation = isRadioMode && currentSong?.id == song.id
    if alreadyOnSameStation {
      currentSong = song
      radioArtworkURL = artworkURL
      updateNowPlayingInfo(reloadArtwork: true)
      return
    }
    audioKit.stop()
    instrumentalTask?.cancel()
    instrumentalTask = nil
    downloadSession?.cancel()
    downloadSession = nil
    isRadioMode = true
    radioArtworkURL = artworkURL
    progress = 0
    queue = []
    originalQueue = []
    withAnimation(.easeInOut(duration: 0.32)) { currentSong = song }
    isBuffering = true
    startRadio(url: streamURL)
  }

  private func startRadio(url: URL) {
    stopRadioPlayer()
    currentPlaybackURL = url
    let item = AVPlayerItem(url: url)
    let player = AVPlayer(playerItem: item)
    if #available(iOS 15.0, *) {
      player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
    }
    player.automaticallyWaitsToMinimizeStalling = true
    player.allowsExternalPlayback = true
    player.volume = 1.0
    radioPlayer = player
    NotificationCenter.default.post(name: MediaPlaybackCoordinator.audioWillPlay, object: nil)
    player.play()
    isPlaying = true
    isBuffering = false
    updateNowPlayingInfo(reloadArtwork: true)
  }

  private func stopRadioPlayer() {
    if let existing = radioTimeObserver {
      existing.player.removeTimeObserver(existing.token)
      radioTimeObserver = nil
    }
    radioPlayer?.pause()
    radioPlayer = nil
  }

  func updateRadioMetadata(song: Song, artworkURL: URL?) {
    guard isRadioMode else { return }
    currentSong = song
    radioArtworkURL = artworkURL
    updateNowPlayingInfo(reloadArtwork: true)
  }

  func displayImageURL(for song: Song) -> URL? {
    if isRadioMode, currentSong?.id == song.id, let art = radioArtworkURL {
      return art
    }
    return song.imageURL
  }

  func clearCache() {
    downloadSession?.cancel()
    downloadSession = nil
    instrumentalTask?.cancel()
    instrumentalTask = nil
    let fm = FileManager.default
    if let entries = try? fm.contentsOfDirectory(
      at: AudioPlayerManager.audioCacheDir, includingPropertiesForKeys: nil)
    {
      for url in entries {
        try? fm.removeItem(at: url)
      }
    }
    #if canImport(UIKit)
      AudioPlayerManager.artworkCache.removeAllObjects()
      nowPlayingArtwork = nil
    #endif
  }

  private static func cleanupOrphanPartialCacheFiles() {
    let fm = FileManager.default
    guard
      let entries = try? fm.contentsOfDirectory(at: audioCacheDir, includingPropertiesForKeys: nil)
    else { return }
    for url in entries where url.pathExtension == "partial" {
      try? fm.removeItem(at: url)
    }
  }

  private func applyMLSeparationIfNeeded() {
    instrumentalTask?.cancel()
    instrumentalTask = nil
    separationGeneration &+= 1
    let gen = separationGeneration
    guard anyAIEffectActive, !isRadioMode, let song = currentSong else {
      VocalSeparator.shared.cancel()
      if audioKit.mode == .aiStems { audioKit.revertToMain() }
      return
    }
    guard VocalSeparator.shared.isAvailable else {
      if audioKit.mode == .aiStems { audioKit.revertToMain() }
      return
    }
    if audioKit.mode == .aiStems {
      applyAIMixVolumes()
      return
    }
    if let stems = VocalSeparator.shared.cachedStems(forSongID: song.id) {
      audioKit.switchToStems(
        vocalsURL: stems.vocals, drumsURL: stems.drums,
        bassURL: stems.bass, otherURL: stems.other,
        startOffset: stems.startOffset)
      applyAIMixVolumes()
      isPlaying = true
      return
    }
    VocalSeparator.shared.cancel()
    let songID = song.id
    let trimStart = audioKit.currentTime
    instrumentalTask = Task { @MainActor [weak self] in
      var sourceURL: URL?
      let deadline = Date().addingTimeInterval(30)
      while sourceURL == nil, Date() < deadline {
        if Task.isCancelled { return }
        guard let self, self.separationGeneration == gen,
          self.currentSong?.id == songID, self.anyAIEffectActive else { return }
        let downloaded = DownloadManager.shared.localURL(for: songID)
        let cached = AudioPlayerManager.audioCacheDir.appendingPathComponent("\(songID).mp3")
        if FileManager.default.fileExists(atPath: downloaded.path) {
          sourceURL = downloaded
        } else if FileManager.default.fileExists(atPath: cached.path) {
          sourceURL = cached
        } else {
          try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5s poll
        }
      }
      guard let sourceURL else { return }
      if Task.isCancelled { return }
      guard let self, self.separationGeneration == gen,
        self.currentSong?.id == songID, self.anyAIEffectActive else { return }

      do {
        let stems = try await VocalSeparator.shared.separate(
          forSongID: songID, sourceURL: sourceURL, startTime: trimStart
        )
        if Task.isCancelled { return }
        guard self.separationGeneration == gen,
          self.currentSong?.id == songID, self.anyAIEffectActive else { return }
        self.audioKit.switchToStems(
          vocalsURL: stems.vocals, drumsURL: stems.drums,
          bassURL: stems.bass, otherURL: stems.other,
          startOffset: stems.startOffset)
        self.applyAIMixVolumes()
        self.isPlaying = true
      } catch is CancellationError {
        return
      } catch VocalSeparatorError.cancelled {
        return
      } catch VocalSeparatorError.unavailable {
        return
      } catch {
        print("[Karaoke] AI separation failed for \(songID): \(error)")
        return
      }
    }
  }

  private func configureAudioSessionCategory() {
    do {
      if #available(iOS 13.0, *) {
        try AVAudioSession.sharedInstance().setCategory(
          .playback, mode: .default, policy: .longFormAudio, options: [])
      } else {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
      }
    } catch {}
  }
  private func activateAudioSession() {
    try? AVAudioSession.sharedInstance().setActive(true, options: [])
  }
  private func handleInterruption(_ note: Notification) {
    guard let info = note.userInfo,
      let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: typeValue)
    else { return }
    switch type {
    case .began:
      if isPlaying {
        if isRadioMode { radioPlayer?.pause() } else { audioKit.pause() }
        isPlaying = false
        updateNowPlayingInfo(reloadArtwork: false)
      }
    case .ended:
      guard let optsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
      let opts = AVAudioSession.InterruptionOptions(rawValue: optsValue)
      if opts.contains(.shouldResume) {
        activateAudioSession()
        NotificationCenter.default.post(name: MediaPlaybackCoordinator.audioWillPlay, object: nil)
        if isRadioMode { radioPlayer?.play() } else { audioKit.resume() }
        isPlaying = true
        updateNowPlayingInfo(reloadArtwork: false)
      }
    @unknown default: break
    }
  }
  private func handleRouteChange(_ note: Notification) {
    updateRouteIcon()
    guard let info = note.userInfo,
      let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
      let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
    else { return }
    if reason == .oldDeviceUnavailable, isPlaying {
      if isRadioMode { radioPlayer?.pause() } else { audioKit.pause() }
      isPlaying = false
      updateNowPlayingInfo(reloadArtwork: false)
    }
  }
  func updateRouteIcon() {
    let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
    guard let primary = outputs.first else {
      routeIcon = "airplayaudio"
      routeName = ""
      return
    }
    routeName = primary.portName
    let nameLower = primary.portName.lowercased()
    switch primary.portType {
    case .builtInSpeaker, .builtInReceiver:
      routeIcon = "airplayaudio"
    case .headphones:
      routeIcon = "headphones"
    case .HDMI:
      routeIcon = "tv.fill"
    case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
      if nameLower.contains("airpods max") {
        routeIcon = "airpodsmax"
      } else if nameLower.contains("airpods pro") {
        routeIcon = "airpodspro"
      } else if nameLower.contains("airpods") {
        routeIcon = "airpods"
      } else if nameLower.contains("beats") {
        routeIcon = "beats.headphones"
      } else {
        routeIcon = "hifispeaker.fill"
      }
    case .airPlay:
      if nameLower.contains("homepod mini") {
        routeIcon = "homepodmini"
      } else if nameLower.contains("homepod") {
        routeIcon = "homepod"
      } else if nameLower.contains("apple tv") {
        routeIcon = "appletv"
      } else {
        routeIcon = "airplayaudio"
      }
    default:
      routeIcon = "airplayaudio"
    }
  }

  private func setupRemoteCommands() {
    let cc = MPRemoteCommandCenter.shared()
    cc.playCommand.addTarget { [weak self] _ in
      guard let self = self, !self.isPlaying else { return .commandFailed }
      self.togglePlayPause()
      return .success
    }
    cc.pauseCommand.addTarget { [weak self] _ in
      guard let self = self, self.isPlaying else { return .commandFailed }
      self.togglePlayPause()
      return .success
    }
    cc.togglePlayPauseCommand.addTarget { [weak self] _ in
      self?.togglePlayPause()
      return .success
    }
    cc.nextTrackCommand.addTarget { [weak self] _ in
      self?.playNextOrRandom()
      return .success
    }
    cc.previousTrackCommand.addTarget { [weak self] _ in
      self?.playPrevious()
      return .success
    }
    cc.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let self = self,
        let positionEvent = event as? MPChangePlaybackPositionCommandEvent
      else { return .commandFailed }
      let dur = self.audioKit.duration
      guard dur.isFinite, dur > 0 else { return .commandFailed }
      self.seek(to: positionEvent.positionTime / dur)
      return .success
    }
  }

  private func updateNowPlayingInfo(reloadArtwork: Bool) {
    guard let song = currentSong else {
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
      return
    }
    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    info[MPMediaItemPropertyTitle] = song.title
    info[MPMediaItemPropertyArtist] = song.originalArtists?.joined(separator: ", ") ?? ""
    if isRadioMode {
      info[MPNowPlayingInfoPropertyIsLiveStream] = true
      info[MPMediaItemPropertyPlaybackDuration] = nil
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = nil
    } else {
      let dur = audioKit.duration
      let actualDuration = (dur.isFinite && dur > 0) ? dur : Double(song.duration)
      info[MPNowPlayingInfoPropertyIsLiveStream] = false
      info[MPMediaItemPropertyPlaybackDuration] = actualDuration
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = audioKit.currentTime
    }
    info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    let targetArt = isRadioMode ? radioArtworkURL : song.imageURL
    if reloadArtwork || artworkURL != targetArt {
      info[MPMediaItemPropertyArtwork] = nil
      artworkURL = targetArt
      #if canImport(UIKit)
        if reloadArtwork { nowPlayingArtwork = nil }
      #endif
      if let targetArt {
        loadArtworkAsync(from: targetArt)
      }
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }
  private func updateNowPlayingElapsed(_ elapsed: Double) {
    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
    info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }
  private func loadArtworkAsync(from url: URL) {
    let songID = currentSong?.id
    artworkTask?.cancel()
    artworkTask = nil
    #if canImport(UIKit)
      if let cached = AudioPlayerManager.artworkCache.object(forKey: url as NSURL) {
        applyArtwork(cached, for: songID)
        return
      }
    #endif
    let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
      guard let self = self, let data = data,
        self.currentSong?.id == songID
      else { return }
      #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return }
        let squareImage = image.croppedToSquare().downscaled(
          maxPixel: AudioPlayerManager.artworkMaxPixel)
        let cost = Int(
          squareImage.size.width * squareImage.size.height * squareImage.scale
            * squareImage.scale * 4)
        AudioPlayerManager.artworkCache.setObject(squareImage, forKey: url as NSURL, cost: cost)
        self.applyArtwork(squareImage, for: songID)
      #endif
    }
    artworkTask = task
    task.resume()
  }
  #if canImport(UIKit)
    private func applyArtwork(_ image: UIImage, for songID: String?) {
      let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
      DispatchQueue.main.async { [weak self] in
        guard let self = self, self.currentSong?.id == songID else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyArtwork] = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        self.nowPlayingArtwork = image
      }
    }
  #endif

  #if canImport(UIKit)
    private func handleBackgroundTransition() {
      if bgTaskID != .invalid {
        UIApplication.shared.endBackgroundTask(bgTaskID)
      }
      bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "AudioCache") { [weak self] in
        guard let self = self else { return }
        if self.bgTaskID != .invalid {
          UIApplication.shared.endBackgroundTask(self.bgTaskID)
          self.bgTaskID = .invalid
        }
      }
    }
    private func beginTrackTransitionBackgroundTask() {
      endTrackTransitionBackgroundTask()
      trackTransitionTaskID = UIApplication.shared.beginBackgroundTask(
        withName: "TrackTransition"
      ) { [weak self] in
        guard let self else { return }
        if self.trackTransitionTaskID != .invalid {
          UIApplication.shared.endBackgroundTask(self.trackTransitionTaskID)
          self.trackTransitionTaskID = .invalid
        }
      }
    }
    private func endTrackTransitionBackgroundTask() {
      guard trackTransitionTaskID != .invalid else { return }
      UIApplication.shared.endBackgroundTask(trackTransitionTaskID)
      trackTransitionTaskID = .invalid
    }
  #endif

  private func fetchRandomTrending() {
    guard let url = URL(string: "\(StorageHost.api)/api/explore/trendings?days=7&take=50")
    else { return }
    var request = URLRequest(url: url)
    request.timeoutInterval = 15
    GuestIdentity.applyIfNeeded(to: &request)
    URLSession.shared.dataTask(with: request) { data, _, _ in
      if let data = data, let songs = try? JSONDecoder().decode([Song].self, from: data),
        let random = songs.randomElement()
      {
        DispatchQueue.main.async { self.play(song: random, context: songs) }
      } else {
        DispatchQueue.main.async {
          #if canImport(UIKit)
            self.endTrackTransitionBackgroundTask()
          #endif
        }
      }
    }.resume()
  }
  private func reportPlayCount(for songID: String) {
    guard let url = URL(string: "\(StorageHost.api)/api/songs/playCount/\(songID)") else { return }
    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    if let token = UserDefaults.standard.string(forKey: "nk.token"), !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    GuestIdentity.applyIfNeeded(to: &request)
    URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
  }

  private func enrichSongMetadataIfNeeded(for song: Song) {
    guard !song.hasArtistMetadata else { return }
    let songID = song.id
    guard let url = URL(string: "\(StorageHost.api)/api/explore/trendings?days=all") else { return }
    var searchURL = URLComponents(string: "\(StorageHost.api)/api/songs")
    var request: URLRequest
    if let searchURL, let u = searchURL.url {
      request = URLRequest(url: u)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      GuestIdentity.applyIfNeeded(to: &request)
      request.httpBody = try? JSONSerialization.data(withJSONObject: [
        "page": 1, "pageSize": 1, "search": song.title,
      ])
    } else {
      request = URLRequest(url: url)
      GuestIdentity.applyIfNeeded(to: &request)
    }
    URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
      guard let data else { return }
      if let response = try? JSONDecoder().decode(SearchResponse.self, from: data),
        let match = response.items.first(where: { $0.id == songID })
      {
        DispatchQueue.main.async {
          guard let self, self.currentSong?.id == songID else { return }
          self.currentSong = match
          self.updateNowPlayingInfo(reloadArtwork: false)
        }
        return
      }
      if let songs = try? JSONDecoder().decode([Song].self, from: data),
        let match = songs.first(where: { $0.id == songID })
      {
        DispatchQueue.main.async {
          guard let self, self.currentSong?.id == songID else { return }
          self.currentSong = match
          self.updateNowPlayingInfo(reloadArtwork: false)
        }
      }
    }.resume()
  }

  private func handleTransitionBegin(plan: TransitionCoordinator.TransitionPlan) {
    #if canImport(UIKit)
      beginTrackTransitionBackgroundTask()
    #endif
    configureAudioSessionCategory()
    activateAudioSession()

    if anyAIEffectActive {
      quickCutToNext(plan: plan)
    } else {
      audioKit.beginCrossfade(
        url: plan.nextFileURL,
        duration: plan.fadeDuration,
        ramp: plan.rampStyle
      )
    }
  }

  private func quickCutToNext(plan: TransitionCoordinator.TransitionPlan) {
    let fadeDuration = plan.fadeDuration
    let song = plan.nextSong
    let steps = Int(fadeDuration * 60)
    let interval: TimeInterval = 1.0 / 60.0
    var step = 0
    Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
      @MainActor [weak self] timer in
      guard let self else {
        timer.invalidate()
        return
      }
      step += 1
      let t = Float(step) / Float(max(1, steps))
      self.audioKit.setMasterVolume(1.0 - t)
      if t >= 1.0 {
        timer.invalidate()
        self.audioKit.setMasterVolume(1.0)
        self.transitionCoordinator.reset()
        self.play(song: song)
      }
    }
  }

  private func transitionCoordinatorDidFinish() {
    guard case .crossfading(let plan) = transitionCoordinator.state else {
      transitionCoordinator.reset()
      return
    }
    let song = plan.nextSong
    reportPlayCount(for: song.id)
    enrichSongMetadataIfNeeded(for: song)
    if currentSong?.id != song.id {
      progress = 0
      withAnimation(.easeInOut(duration: 0.32)) {
        currentSong = song
      }
    }
    isPlaying = true
    isBuffering = false
    updateNowPlayingInfo(reloadArtwork: true)
    transitionCoordinator.reset()
    if anyAIEffectActive {
      applyMLSeparationIfNeeded()
    }
    #if canImport(UIKit)
      endTrackTransitionBackgroundTask()
    #endif
  }
}

#if canImport(UIKit)
  extension UIImage {
    func croppedToSquare() -> UIImage {
      let originalWidth = size.width
      let originalHeight = size.height
      let sideLength = min(originalWidth, originalHeight)
      let xOffset = (originalWidth - sideLength) / 2.0
      let yOffset = (originalHeight - sideLength) / 2.0
      let cropRect = CGRect(x: xOffset, y: yOffset, width: sideLength, height: sideLength)
      guard let cgImage = cgImage?.cropping(to: cropRect) else { return self }
      return UIImage(cgImage: cgImage, scale: scale, orientation: imageOrientation)
    }
    func downscaled(maxPixel: CGFloat) -> UIImage {
      let pixelW = size.width * scale
      let pixelH = size.height * scale
      let longest = max(pixelW, pixelH)
      guard longest > maxPixel else { return self }
      let ratio = maxPixel / longest
      let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      format.opaque = true
      let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
      return renderer.image { _ in
        draw(in: CGRect(origin: .zero, size: newSize))
      }
    }
  }
#endif
