import Foundation
import Testing
@testable import Twinskaraoke_Watch_App

@MainActor
@Suite("Watch song model")
struct WatchSongModelTests {
  @Test("Watch song URLs normalize storage paths")
  func songAudioURLNormalizesAbsolutePath() {
    UserDefaults.standard.set("global", forKey: "nk.storageRegion")
    let song = Song(
      id: "watch-song-1",
      title: "Watch Song",
      duration: 125,
      absolutePath: "/watch/audio.mp3",
      coverArt: SongMedia(absolutePath: "/covers/watch.jpg"),
      coverArtists: ["Cover Artist"],
      originalArtists: ["Original Artist"],
      cloudflareId: nil,
      userUploaded: false
    )

    #expect(song.audioURL?.absoluteString == "https://storage.neurokaraoke.com/watch/audio.mp3")
    #expect(song.imageURL?.absoluteString == "https://images.neurokaraoke.com/covers/watch.jpg/quality=95")
    #expect(song.artistName == "Original Artist")
    #expect(song.durationText == "2:05")
  }

  @Test("Watch song equality is based on id")
  func equalityUsesSongId() {
    let first = Song(
      id: "same-id",
      title: "First",
      duration: 1,
      absolutePath: "first.mp3",
      coverArt: nil,
      coverArtists: nil,
      originalArtists: nil,
      cloudflareId: nil,
      userUploaded: false
    )
    let second = Song(
      id: "same-id",
      title: "Second",
      duration: 2,
      absolutePath: "second.mp3",
      coverArt: nil,
      coverArtists: nil,
      originalArtists: nil,
      cloudflareId: nil,
      userUploaded: false
    )

    #expect(first == second)
  }
}
