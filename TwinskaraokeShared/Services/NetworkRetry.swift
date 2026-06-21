import Foundation

/// Provides exponential backoff retry logic for network operations.
nonisolated enum NetworkRetry {
  /// Maximum number of retry attempts (initial attempt + 5 retries = 6 total)
  static let maxRetries = 5

  /// Base delay in seconds for exponential backoff (doubles each retry)
  static let baseDelay: TimeInterval = 1.0

  /// Executes an async operation with exponential backoff retry logic.
  ///
  /// - Parameter operation: The async throwing closure to retry
  /// - Returns: The result of the operation if successful
  /// - Throws: The last error encountered after all retries are exhausted
  static func execute<T>(_ operation: @Sendable () async throws -> T) async throws -> T {
    var lastError: Error?

    for attempt in 0...maxRetries {
      do {
        return try await operation()
      } catch {
        lastError = error

        // Don't retry on the last attempt
        guard attempt < maxRetries else {
          break
        }

        // Calculate exponential backoff: 1s, 2s, 4s, 8s, 16s
        let delay = baseDelay * pow(2.0, Double(attempt))
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      }
    }

    throw lastError ?? URLError(.unknown)
  }

  /// Executes an async operation with exponential backoff retry logic,
  /// retrying only for specific error conditions.
  ///
  /// - Parameters:
  ///   - shouldRetry: Closure that determines if a given error is retryable
  ///   - operation: The async throwing closure to retry
  /// - Returns: The result of the operation if successful
  /// - Throws: The last error encountered after all retries are exhausted or first non-retryable error
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

        // Don't retry if error is not retryable
        guard shouldRetry(error) else {
          throw error
        }

        // Don't retry on the last attempt
        guard attempt < maxRetries else {
          break
        }

        // Calculate exponential backoff: 1s, 2s, 4s, 8s, 16s
        let delay = baseDelay * pow(2.0, Double(attempt))
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      }
    }

    throw lastError ?? URLError(.unknown)
  }

  /// Determines if an error is retryable based on common network failure patterns.
  ///
  /// - Parameter error: The error to evaluate
  /// - Returns: `true` if the error should trigger a retry
  static func isRetryable(_ error: Error) -> Bool {
    // Retry on common network errors
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

    // Retry on 5xx server errors
    if let apiError = error as? KaraokeAPIClient.APIError,
       case .httpStatus(let code) = apiError,
       (500..<600).contains(code) {
      return true
    }

    return false
  }
}
