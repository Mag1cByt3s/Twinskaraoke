import Foundation

nonisolated enum GuestIdentity {
  private static let storageKey = "nk.guestId"
  private static let tokenKey = "nk.token"

  static let current: String = {
    let defaults = UserDefaults.standard
    if let existing = defaults.string(forKey: storageKey), !existing.isEmpty {
      return existing
    }
    let generated = UUID().uuidString.lowercased()
    defaults.set(generated, forKey: storageKey)
    return generated
  }()

  static var isAuthenticated: Bool {
    let token = UserDefaults.standard.string(forKey: tokenKey)
    return !(token?.isEmpty ?? true)
  }

  static func applyIfNeeded(to request: inout URLRequest) {
    guard !isAuthenticated else { return }
    request.setValue(current, forHTTPHeaderField: "x-guest-id")
  }
}
