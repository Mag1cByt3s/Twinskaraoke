import Combine
import Foundation

@MainActor
final class RecentlyAddedTracker: ObservableObject {
  static let shared = RecentlyAddedTracker()
  private static let storageKey = "nk.recentlyAddedDates.v1"
  @Published private(set) var dates: [String: Date] = [:]
  private init() { load() }
  func date(for id: String) -> Date {
    dates[id] ?? .distantPast
  }
  func registerIfNew(_ ids: [String]) {
    var changed = false
    let now = Date()
    for id in ids where dates[id] == nil {
      dates[id] = now
      changed = true
    }
    if changed { save() }
  }
  func bump(_ id: String) {
    dates[id] = Date()
    save()
  }
  private func load() {
    guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }
    if let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
      dates = decoded
    }
  }
  private func save() {
    if let data = try? JSONEncoder().encode(dates) {
      UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
  }
}
