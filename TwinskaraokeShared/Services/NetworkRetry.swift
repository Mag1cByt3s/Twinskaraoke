import Foundation

nonisolated enum NetworkRetry {

  static let maxRetries = 5

  static let baseDelay: TimeInterval = 1.0

  static func execute<T>(_ operation: @Sendable () async throws -> T) async throws -> T {
    var lastError: Error?

    for attempt in 0...maxRetries {
      do {
        return try await operation()
      } catch {
        lastError = error

        guard attempt < maxRetries else {
          break
        }

        let delay = baseDelay * pow(2.0, Double(attempt))
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      }
    }

    throw lastError ?? URLError(.unknown)
  }

  static func execute<T>(
    shouldRetry: @Sendable (Error) -> Bool,
    _ operation: @Sendable () async throws -> T
  ) async throws -> T {
    var lastError: Error?

    for attempt in 0...maxRetries {
      do {
        return try await operation()
      } catch {
        lastError = error

        guard shouldRetry(error) else {
          throw error
        }

        guard attempt < maxRetries else {
          break
        }

        let delay = baseDelay * pow(2.0, Double(attempt))
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      }
    }

    throw lastError ?? URLError(.unknown)
  }

  static func isRetryable(_ error: Error) -> Bool {

    if let urlError = error as? URLError {
      switch urlError.code {
      case .timedOut,
           .cannotFindHost,
           .cannotConnectToHost,
           .networkConnectionLost,
           .dnsLookupFailed,
           .notConnectedToInternet,
           .badServerResponse:
        return true
      default:
        return false
      }
    }

    if let apiError = error as? KaraokeAPIClient.APIError,
       case .httpStatus(let code) = apiError,
       (500..<600).contains(code) {
      return true
    }

    return false
  }
}
