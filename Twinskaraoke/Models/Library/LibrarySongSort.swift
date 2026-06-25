import Foundation

enum LibrarySongSort: String, CaseIterable, Identifiable {
    case recentlyAdded
    case title
    case artist
    case duration

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .recentlyAdded: "Recently Added"
        case .title: "Title"
        case .artist: "Artist"
        case .duration: "Duration"
        }
    }

    var symbol: String {
        switch self {
        case .recentlyAdded: "clock"
        case .title: "textformat"
        case .artist: "person"
        case .duration: "timer"
        }
    }
}
