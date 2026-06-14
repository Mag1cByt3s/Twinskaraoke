import AVFoundation
import Combine
import Foundation
import MediaPlayer
import SwiftUI

enum PlaybackMode {
  case listLoop
  case singleLoop
  var iconName: String {
    switch self {
    case .listLoop: return "repeat"
    case .singleLoop: return "repeat.1"
    }
  }
}

@MainActor
class AudioManager: ObservableObject {
  static let shared = AudioManager()
  @Published var currentSong: Song?
  @Published var isPlaying = false
  @Published var isLoading = false
  @Published var currentTime: Double = 0
  @Published var duration: Double = 0
  @Published var queue: [Song] = []
  @Published var currentIndex: Int = 0
  @Published var playbackMode: PlaybackMode = .listLoop
  @Published var isShuffleOn = false
  @Published var volume: Double = AudioManager.storedVolume()
  private var player: AVPlayer?
  private var timeObserver: Any?
  private var endTimeObserver: NSObjectProtocol?
  private var cancellables = Set<AnyCancellable>()
  private var downloadTask: URLSessionDownloadTask?
  private var recoveringFromBrokenCache: Set<String> = []
  private var playbackRequested = false
  private var shouldResumeAfterInterruption = false
  private static let audioCacheDir: URL = {
    let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
      .appendingPathComponent("AudioCache")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }()
  private static let maxCachedFiles = 10
  private static let volumeDefaultsKey = "nk.watchVolume"
  init() {
    setupRemoteCommands()
    setupInterruptionHandler()
  }
  var progress: Double {
    guard duration > 0 else { return 0 }
    return currentTime / duration
  }

  var upNextSongs: [Song] {
    guard let index = resolvedCurrentQueueIndex else { return [] }
    let nextIndex = index + 1
    guard nextIndex < queue.endIndex else { return [] }
    return Array(queue[nextIndex...])
  }

  func play(song: Song, context: [Song] = []) {
    var playbackQueue = context.isEmpty ? [song] : context
    if let index = playbackQueue.firstIndex(of: song) {
      currentIndex = index
    } else {
      playbackQueue.insert(song, at: 0)
      currentIndex = 0
    }
    queue = playbackQueue
    currentSong = song
    prepareAndPlay()
  }
  private func prepareAndPlay() {
    cleanupPlayer()
    currentTime = 0
    duration = 0
    isPlaying = false
    playbackRequested = true
    cancellables.removeAll()
    setupInterruptionHandler()
    downloadTask?.cancel()
    guard let song = currentSong else {
      playbackRequested = false
      isLoading = false
      return
    }
    let localURL = localCacheURL(for: song.id)
    if FileManager.default.fileExists(atPath: localURL.path) {
      isLoading = true
      validateCacheAndPlay(song: song, cacheURL: localURL)
      return
    }
    guard let remoteURL = song.audioURL else {
      playbackRequested = false
      isLoading = false
      return
    }
    isLoading = true
    downloadTask = URLSession.shared.downloadTask(with: remoteURL) {
      [weak self] tempURL, _, error in
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.isLoading = false
        guard let tempURL = tempURL, error == nil else {
          self.playbackRequested = false
          return
        }
        try? FileManager.default.moveItem(at: tempURL, to: localURL)
        guard self.currentSong?.id == song.id else { return }
        self.evictOldCacheFiles()
        self.setupPlayer(with: localURL)
      }
    }
    downloadTask?.resume()
  }
  private func setupPlayer(with localURL: URL) {
    do {
      try AVAudioSession.sharedInstance().setCategory(
        .playback, mode: .default, policy: .longFormAudio)
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {}
    let playerItem = AVPlayerItem(url: localURL)
    let player = AVPlayer(playerItem: playerItem)
    player.volume = Float(volume)
    self.player = player
    player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
    playerItem.publisher(for: \.duration)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] dur in
        let seconds = CMTimeGetSeconds(dur)
        if !seconds.isNaN && seconds > 0 {
          self?.duration = seconds
        }
      }
      .store(in: &cancellables)
    playerItem.publisher(for: \.status)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] status in
        guard let self = self else { return }
        if status == .readyToPlay {
          if self.playbackRequested {
            player.play()
          }
          self.refreshPlaybackState()
          self.updateNowPlayingInfo()
        } else if status == .failed {
          self.isLoading = false
          self.isPlaying = false
          if !self.recoverFromBrokenCache(playbackURL: localURL) {
            self.playbackRequested = false
            self.playNext()
          }
        }
      }
      .store(in: &cancellables)
    player.publisher(for: \.timeControlStatus, options: [.initial, .new])
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.refreshPlaybackState()
      }
      .store(in: &cancellables)
    let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
    timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
      [weak self] time in
      Task { @MainActor [weak self] in
        guard let self = self else { return }
        let seconds = CMTimeGetSeconds(time)
        if seconds.isFinite && !seconds.isNaN {
          self.currentTime = max(0, seconds)
        }
      }
    }
    if let oldObserver = endTimeObserver {
      NotificationCenter.default.removeObserver(oldObserver)
    }
    endTimeObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.playEnded()
      }
    }
  }
  private func refreshPlaybackState() {
    guard playbackRequested else {
      isPlaying = false
      isLoading = false
      return
    }
    guard let player else {
      isPlaying = false
      return
    }
    if player.timeControlStatus == .playing {
      isPlaying = true
      isLoading = false
    } else {
      isPlaying = false
      isLoading = true
    }
  }
  @discardableResult
  private func pausePlayback(cancelDownload: Bool = true) -> Bool {
    let hasPendingDownload = player == nil && (playbackRequested || isLoading)
    if hasPendingDownload && cancelDownload {
      downloadTask?.cancel()
    }
    guard player != nil || playbackRequested || isLoading else { return false }
    playbackRequested = false
    player?.pause()
    isPlaying = false
    if cancelDownload || player != nil {
      isLoading = false
    }
    updateNowPlayingInfo()
    return true
  }
  @discardableResult
  private func resumePlayback() -> Bool {
    guard let player else {
      if isLoading {
        playbackRequested = true
        updateNowPlayingInfo()
        return true
      }
      isPlaying = false
      if !isLoading { playbackRequested = false }
      updateNowPlayingInfo()
      return false
    }
    do {
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {}
    playbackRequested = true
    player.play()
    refreshPlaybackState()
    updateNowPlayingInfo()
    return true
  }
  @discardableResult
  func togglePlayPause() -> Bool {
    if playbackRequested || isPlaying {
      return pausePlayback()
    }
    return resumePlayback()
  }
  func playNext() {
    guard !queue.isEmpty else { return }
    currentIndex = resolvedCurrentQueueIndex ?? queue.startIndex
    if isShuffleOn && queue.count > 1 {
      var nextIndex = currentIndex
      while nextIndex == currentIndex {
        nextIndex = Int.random(in: 0..<queue.count)
      }
      currentIndex = nextIndex
    } else {
      currentIndex = (currentIndex + 1) % queue.count
    }
    currentSong = queue[currentIndex]
    prepareAndPlay()
  }
  func playPrevious() {
    if currentTime > 3.0 {
      player?.seek(to: .zero)
      return
    }
    guard !queue.isEmpty else {
      player?.seek(to: .zero)
      return
    }
    if let index = resolvedCurrentQueueIndex {
      currentIndex = index
    }
    if currentIndex > 0 {
      currentIndex -= 1
      currentSong = queue[currentIndex]
      prepareAndPlay()
    } else {
      player?.seek(to: .zero)
    }
  }
  func playEnded() {
    if playbackMode == .singleLoop {
      player?.seek(to: .zero)
      player?.play()
    } else {
      playNext()
    }
  }
  func toggleMode() {
    switch playbackMode {
    case .listLoop: playbackMode = .singleLoop
    case .singleLoop: playbackMode = .listLoop
    }
  }
  func toggleShuffle() {
    isShuffleOn.toggle()
  }
  func seek(to time: Double) {
    player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
    updateNowPlayingInfo()
  }
  func setVolume(_ value: Double) {
    let clamped = min(max(value, 0), 1)
    volume = clamped
    UserDefaults.standard.set(clamped, forKey: AudioManager.volumeDefaultsKey)
    player?.volume = Float(clamped)
  }
  private static func storedVolume() -> Double {
    guard UserDefaults.standard.object(forKey: volumeDefaultsKey) != nil else { return 1 }
    return min(max(UserDefaults.standard.double(forKey: volumeDefaultsKey), 0), 1)
  }
  private var resolvedCurrentQueueIndex: Int? {
    guard !queue.isEmpty, let currentSong else { return nil }
    if queue.indices.contains(currentIndex), queue[currentIndex] == currentSong {
      return currentIndex
    }
    return queue.firstIndex(of: currentSong)
  }
  private func cleanupPlayer() {
    if let observer = timeObserver {
      player?.removeTimeObserver(observer)
      timeObserver = nil
    }
    if let observer = endTimeObserver {
      NotificationCenter.default.removeObserver(observer)
      endTimeObserver = nil
    }
    player?.pause()
    player = nil
  }
  private func localCacheURL(for songID: String) -> URL {
    AudioManager.audioCacheDir.appendingPathComponent("\(songID).mp3")
  }
  func clearCache() {
    downloadTask?.cancel()
    downloadTask = nil
    let fm = FileManager.default
    if let entries = try? fm.contentsOfDirectory(
      at: AudioManager.audioCacheDir, includingPropertiesForKeys: nil)
    {
      for url in entries {
        try? fm.removeItem(at: url)
      }
    }
  }
  private func validateCachedFile(
    at url: URL, expectedDuration: Int, completion: @escaping (Bool) -> Void
  ) {
    Task {
      let asset = AVURLAsset(url: url)
      let expected = Double(expectedDuration)
      do {
        let loadedDuration = try await asset.load(.duration)
        let isPlayable = try await asset.load(.isPlayable)
        let actual = loadedDuration.seconds
        let durationOK: Bool
        if expected > 5 {
          durationOK = actual.isFinite && actual >= expected * 0.9
        } else {
          durationOK = actual.isFinite && actual > 0
        }
        await MainActor.run {
          completion(isPlayable && durationOK)
        }
      } catch {
        await MainActor.run {
          completion(false)
        }
      }
    }
  }
  private func validateCacheAndPlay(song: Song, cacheURL: URL) {
    let songID = song.id
    validateCachedFile(at: cacheURL, expectedDuration: song.duration) { [weak self] valid in
      guard let self, self.currentSong?.id == songID else { return }
      if valid {
        self.setupPlayer(with: cacheURL)
        return
      }
      try? FileManager.default.removeItem(at: cacheURL)
      guard let remoteURL = song.audioURL else {
        self.isLoading = false
        self.playbackRequested = false
        return
      }
      self.downloadTask = URLSession.shared.downloadTask(with: remoteURL) {
        [weak self] tempURL, _, error in
        DispatchQueue.main.async {
          guard let self = self else { return }
          self.isLoading = false
          guard let tempURL = tempURL, error == nil else {
            self.playbackRequested = false
            return
          }
          try? FileManager.default.moveItem(at: tempURL, to: cacheURL)
          guard self.currentSong?.id == songID else { return }
          self.evictOldCacheFiles()
          self.setupPlayer(with: cacheURL)
        }
      }
      self.downloadTask?.resume()
    }
  }
  @discardableResult
  private func recoverFromBrokenCache(playbackURL: URL) -> Bool {
    guard playbackURL.path.hasPrefix(AudioManager.audioCacheDir.path),
      let song = currentSong,
      !recoveringFromBrokenCache.contains(song.id),
      let remoteURL = song.audioURL
    else { return false }
    let songID = song.id
    recoveringFromBrokenCache.insert(songID)
    try? FileManager.default.removeItem(at: playbackURL)
    cleanupPlayer()
    isLoading = true
    downloadTask?.cancel()
    downloadTask = URLSession.shared.downloadTask(with: remoteURL) {
      [weak self] tempURL, _, error in
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.isLoading = false
        guard let tempURL = tempURL, error == nil else {
          self.playbackRequested = false
          return
        }
        try? FileManager.default.moveItem(at: tempURL, to: playbackURL)
        guard self.currentSong?.id == songID else { return }
        self.evictOldCacheFiles()
        self.setupPlayer(with: playbackURL)
      }
    }
    downloadTask?.resume()
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
      self?.recoveringFromBrokenCache.remove(songID)
    }
    return true
  }
  private func evictOldCacheFiles() {
    let fm = FileManager.default
    let dir = AudioManager.audioCacheDir
    guard
      let files = try? fm.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
    else { return }
    guard files.count > AudioManager.maxCachedFiles else { return }
    let sorted = files.sorted {
      let d1 =
        (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        ?? .distantPast
      let d2 =
        (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        ?? .distantPast
      return d1 < d2
    }
    let toRemove = sorted.prefix(files.count - AudioManager.maxCachedFiles)
    for file in toRemove {
      try? fm.removeItem(at: file)
    }
  }
  private func setupRemoteCommands() {
    let cc = MPRemoteCommandCenter.shared()
    cc.playCommand.addTarget { [weak self] _ in
      guard let self = self, !self.playbackRequested else { return .commandFailed }
      return self.resumePlayback() ? .success : .commandFailed
    }
    cc.pauseCommand.addTarget { [weak self] _ in
      guard let self = self, self.playbackRequested else { return .commandFailed }
      return self.pausePlayback() ? .success : .commandFailed
    }
    cc.togglePlayPauseCommand.addTarget { [weak self] _ in
      guard let self else { return .commandFailed }
      return self.togglePlayPause() ? .success : .commandFailed
    }
    cc.nextTrackCommand.addTarget { [weak self] _ in
      self?.playNext()
      return .success
    }
    cc.previousTrackCommand.addTarget { [weak self] _ in
      self?.playPrevious()
      return .success
    }
  }
  private func setupInterruptionHandler() {
    NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
      .sink { [weak self] note in self?.handleInterruption(note) }
      .store(in: &cancellables)
  }
  private func handleInterruption(_ note: Notification) {
    guard let info = note.userInfo,
      let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: typeValue)
    else { return }
    switch type {
    case .began:
      shouldResumeAfterInterruption = playbackRequested
      if playbackRequested {
        pausePlayback(cancelDownload: false)
      }
    case .ended:
      guard let optsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
      let opts = AVAudioSession.InterruptionOptions(rawValue: optsValue)
      if opts.contains(.shouldResume), shouldResumeAfterInterruption {
        resumePlayback()
      }
      shouldResumeAfterInterruption = false
    @unknown default: break
    }
  }
  private func updateNowPlayingInfo() {
    guard let song = currentSong else {
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
      return
    }
    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    info[MPMediaItemPropertyTitle] = song.title
    info[MPMediaItemPropertyArtist] = song.artistName
    info[MPMediaItemPropertyPlaybackDuration] = duration
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
    info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }
  deinit {
    downloadTask?.cancel()
    if let observer = timeObserver {
      player?.removeTimeObserver(observer)
    }
    if let observer = endTimeObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    player?.pause()
  }
}
