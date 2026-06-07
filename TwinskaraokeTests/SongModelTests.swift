import Foundation
import Testing
@testable import Twinskaraoke

@Suite("Song model")
struct SongModelTests {
  @Test("Cloudflare artwork URLs use the image CDN")
  func songImageURLWithCloudflareId() {
    UserDefaults.standard.set("global", forKey: "nk.storageRegion")
    let song = Song(
      id: "song-1",
      title: "Test Song",
      duration: 185,
      absolutePath: "/audio/test.mp3",
      cloudflareID: "image-id",
      coverArt: Media(absolutePath: "/covers/test.jpg"),
      originalArtists: ["Original Artist"],
      coverArtists: ["Cover Artist"],
      userUploaded: false
    )

    #expect(song.imageURL?.absoluteString == "https://images.neurokaraoke.com/image-id/public")
    #expect(song.fullHDImageURL?.absoluteString == "https://images.neurokaraoke.com/image-id/quality=95")
  }

  @Test("Audio URLs trim leading slashes")
  func songAudioURLNormalizesAbsolutePath() {
    UserDefaults.standard.set("global", forKey: "nk.storageRegion")
    let song = Song(
      id: "song-2",
      title: "Test Song",
      duration: 61,
      absolutePath: "/songs/test.mp3",
      cloudflareID: nil,
      coverArt: nil,
      originalArtists: nil,
      coverArtists: nil,
      userUploaded: false
    )

    #expect(song.audioURL?.absoluteString == "https://storage.neurokaraoke.com/songs/test.mp3")
    #expect(song.durationText == "1:01")
  }

  @Test("Display artist combines original and cover artists")
  func displayArtistUsesOriginalAndCoverMetadata() {
    let song = Song(
      id: "song-3",
      title: "Test Song",
      duration: 180,
      absolutePath: nil,
      cloudflareID: nil,
      coverArt: nil,
      originalArtists: ["Original"],
      coverArtists: ["Neuro"],
      userUploaded: false
    )

    #expect(song.displayTitle == "Test Song - Original")
    #expect(song.displayArtist == "Original · Cover by Neuro")
    #expect(song.hasArtistMetadata)
  }
}
