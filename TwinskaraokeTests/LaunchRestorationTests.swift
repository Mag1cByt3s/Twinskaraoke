import Foundation
import Security
import Testing
@testable import Twinskaraoke

@Suite("Launch restoration")
struct LaunchRestorationTests {
    @Test func keychainUnavailableIsNotMissing() {
        for status in [errSecInteractionNotAllowed, errSecNotAvailable, errSecAuthFailed] {
            #expect(CredentialStore.classifyRead(status: status, data: nil) == .unavailable(status))
        }
        #expect(CredentialStore.classifyRead(status: errSecItemNotFound, data: nil) == .missing)
        #expect(CredentialStore.classifyRead(status: errSecSuccess, data: Data("secret".utf8)) == .available("secret"))
        #expect(CredentialStore.classifyRead(status: errSecSuccess, data: Data()) == .unavailable(errSecDecode))
    }

    @Test func unavailableCredentialDoesNotCreateAnonymousRequest() {
        #expect(throws: CredentialStore.StoreError.self) {
            try KaraokeAPIClient.request(path: "/api/playlists", readToken: {
                throw CredentialStore.StoreError.keychain(errSecInteractionNotAllowed)
            })
        }
    }

    @Test func malformedPlaylistPayloadIsNotAnEmptyLibrary() throws {
        #expect(throws: (any Error).self) {
            try KaraokeAPIClient.decodePlaylists(from: Data("{\"error\":\"unavailable\"}".utf8))
        }
        #expect(throws: (any Error).self) {
            try KaraokeAPIClient.decodePlaylists(from: Data("[{\"unexpected\":true}]".utf8))
        }
        #expect(try KaraokeAPIClient.decodePlaylists(from: Data("[]".utf8)).isEmpty)
    }

    @MainActor @Test func failedPublicPlaylistLoadCanRetry() async {
        let loader = FailingPageLoader()
        let model = PublicPlaylistsViewModel { _, _ in try await loader.load() }
        model.loadIfNeeded()
        while model.isLoadingMore { await Task.yield() }
        #expect(model.errorMessage != nil)
        model.loadIfNeeded()
        while model.isLoadingMore { await Task.yield() }
        #expect(model.errorMessage == nil)
        #expect(await loader.calls == 2)
        model.loadIfNeeded()
        #expect(await loader.calls == 2)
    }

    @MainActor @Test func startupDoesNotProbeOrDeleteAudio() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let song = UITestFixtures.song(id: "restored", title: "Saved", artist: "Artist")
        let directory = root.appendingPathComponent(song.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(song).write(to: directory.appendingPathComponent("metadata.json"))
        let audio = directory.appendingPathComponent("main.mp3")
        let bytes = Data("a temporarily undecodable file".utf8)
        try bytes.write(to: audio)
        let result = DownloadManager.scanExistingDownloads(in: root)
        #expect(result.validIDs == [song.id])
        #expect(!result.hadFailures)
        #expect(try Data(contentsOf: audio) == bytes)
        try Data("invalid metadata".utf8).write(to: directory.appendingPathComponent("metadata.json"))
        #expect(DownloadManager.scanExistingDownloads(in: root).hadFailures)
        #expect(try Data(contentsOf: audio) == bytes)
    }

    @Test func reconciliationPreservesLiveChangesAndUnavailableFiles() {
        #expect(DownloadManager.restorationMissingIDs(
            starting: ["gone", "completed", "active", "saved"], discovered: ["saved"],
            changed: ["completed"], inProgress: ["active"], hadFailures: false) == ["gone"])
        #expect(DownloadManager.restorationMissingIDs(
            starting: ["unreadable"], discovered: [], changed: [], inProgress: [], hadFailures: true).isEmpty)
    }

    @Test func signedURLRotationPreservesContentIdentity() {
        #expect(DownloadManager.sameAudioResource("https://example.com/song?token=old", "https://example.com/song?token=new"))
        #expect(!DownloadManager.sameAudioResource("https://example.com/song?version=1", "https://example.com/song?version=2"))
    }
}

private actor FailingPageLoader {
    var calls = 0
    func load() throws -> [Playlist] {
        calls += 1
        if calls == 1 { throw URLError(.notConnectedToInternet) }
        return []
    }
}
