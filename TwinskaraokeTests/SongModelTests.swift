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

        #expect(
            song.imageURL?.absoluteString
                == "https://images.neurokaraoke.com/image-id/width=480,quality=85,format=auto"
        )
        #expect(
            song.fullHDImageURL?.absoluteString
                == "https://images.neurokaraoke.com/image-id/width=1920,quality=90,format=auto"
        )
    }

    @Test("downloadCoverImageURL produces a JPEG URL for songs with artwork")
    func downloadCoverImageURLWithArtwork() {
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

        #expect(
            song.downloadCoverImageURL?.absoluteString
                == "https://images.neurokaraoke.com/image-id/width=1920,quality=90,format=jpeg"
        )
    }

    @Test("downloadCoverImageURL is nil for songs without their own artwork")
    func downloadCoverImageURLWithoutArtwork() {
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

        #expect(song.downloadCoverImageURL == nil)
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

    @Test("audioURL falls back to oss when absolutePath is nil")
    func songAudioURLFallsBackToOss() {
        UserDefaults.standard.set("global", forKey: "nk.storageRegion")
        let song = Song(
            id: "song-oss",
            title: "Uploaded Song",
            duration: 200,
            absolutePath: nil,
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: ["Uploader"],
            coverArtists: nil,
            userUploaded: true,
            oss: "audio/Uploaded Song (live).mp3"
        )

        let url = song.audioURL?.absoluteString
        #expect(url != nil)
        #expect(url?.hasPrefix("https://storage.neurokaraoke.com/audio/") == true)
        #expect(url?.contains("Uploaded") == true)
        #expect(url?.contains("%20") == true)
    }

    @Test("audioURL is nil when both absolutePath and oss are nil")
    func songAudioURLNilWithoutAnyPath() {
        let song = Song(
            id: "song-nopath",
            title: "No Path",
            duration: 10,
            absolutePath: nil,
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: nil,
            coverArtists: nil,
            userUploaded: true
        )

        #expect(song.audioURL == nil)
    }

    @Test("Song decodes oss field from JSON")
    func songDecodesOssField() {
        UserDefaults.standard.set("global", forKey: "nk.storageRegion")
        let json = """
        {"id":"s1","title":"T","duration":5,"absolutePath":null,"oss":"audio/test.mp3","userUploaded":true}
        """.data(using: .utf8)!
        let song = try? JSONDecoder().decode(Song.self, from: json)
        #expect(song != nil)
        #expect(song?.oss == "audio/test.mp3")
        #expect(song?.audioURL?.absoluteString == "https://storage.neurokaraoke.com/audio/test.mp3")
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
