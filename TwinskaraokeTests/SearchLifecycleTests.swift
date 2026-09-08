import Foundation
import Testing
@testable import Twinskaraoke

@MainActor
@Suite("Search lifecycle")
struct SearchLifecycleTests {
    @Test("Editing a query clears results and errors before the debounce")
    func editingInvalidatesPresentationImmediately() {
        let model = SearchViewModel()
        model.results = [UITestFixtures.song(id: "old", title: "Old", artist: "Artist")]
        model.searchErrorMessage = "Old error"
        model.isSearching = true
        model.searchText = "new query"
        #expect(model.results.isEmpty)
        #expect(model.searchErrorMessage == nil)
        #expect(model.isSearching)
        model.searchText = ""
    }

    @Test("An old response is rejected during the next query's debounce")
    func lateResponseDuringDebounce() async {
        var response: CheckedContinuation<[Song], Never>?
        let model = SearchViewModel(loadSongs: { _ in
            await withCheckedContinuation { response = $0 }
        })
        model.search("old")
        while response == nil { await Task.yield() }
        model.searchText = "new"
        response?.resume(returning: [UITestFixtures.song(id: "old", title: "Old", artist: "Artist")])
        for _ in 0..<10 { await Task.yield() }
        #expect(model.results.isEmpty)
        #expect(model.searchErrorMessage == nil)
        model.searchText = ""
    }

    @Test("Clearing a pending query cancels the search without waiting")
    func clearingPendingQuery() async throws {
        let model = SearchViewModel()
        model.searchText = "pending"
        model.searchText = "  \n"
        #expect(!model.hasActiveQuery)
        #expect(model.results.isEmpty)
        #expect(!model.isSearching)
        try await Task.sleep(for: .milliseconds(600))
        #expect(model.results.isEmpty)
        #expect(!model.isSearching)
        #expect(model.searchErrorMessage == nil)
    }

    @Test("Submitting immediately cancels the delayed duplicate request")
    func submittingPendingQuery() async throws {
        var queries: [String] = []
        let model = SearchViewModel(loadSongs: { query in
            queries.append(query)
            return []
        })
        model.searchText = "Neuro"
        #expect(model.isSearching)
        model.search(model.searchText)
        for _ in 0..<10 { await Task.yield() }
        #expect(queries == ["Neuro"])
        #expect(!model.isSearching)
        try await Task.sleep(for: .milliseconds(600))
        #expect(queries == ["Neuro"])
        model.searchText = "Neuro "
        #expect(!model.isSearching)
    }

    @Test("Typing coalesces into the latest query and then leaves loading")
    func typingDispatchesLatestQuery() async throws {
        var queries: [String] = []
        let model = SearchViewModel(loadSongs: { query in
            queries.append(query)
            return [UITestFixtures.song(id: "result", title: "Result", artist: "Artist")]
        })
        model.searchText = "Neu"
        model.searchText = "Neuro"
        #expect(model.isSearching)
        try await Task.sleep(for: .milliseconds(700))
        #expect(queries == ["Neuro"])
        #expect(model.results.count == 1)
        #expect(!model.isSearching)
    }
}
