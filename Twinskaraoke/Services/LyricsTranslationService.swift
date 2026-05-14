import Foundation

enum LyricsTranslationError: Error {
  case unavailable
  case invalidResponse
}

final class LyricsTranslationService {
  static let shared = LyricsTranslationService()

  private let defaults = UserDefaults.standard
  private let endpointKey = "nk.lyricsTranslationEndpoint"

  private init() {}

  var isConfigured: Bool {
    endpointURL != nil
  }

  func translate(songID: String, lyrics: [LyricLine]) async throws -> [LyricLine] {
    guard let endpointURL else { throw LyricsTranslationError.unavailable }

    var request = URLRequest(url: endpointURL)
    request.httpMethod = "POST"
    request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token = UserDefaults.standard.string(forKey: "nk.token"), !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    GuestIdentity.applyIfNeeded(to: &request)
    request.httpBody = try JSONEncoder().encode(TranslationRequest(songID: songID, lyrics: lyrics))

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw LyricsTranslationError.invalidResponse
    }

    let translatedLines = try decodeTranslations(from: data)
    guard translatedLines.count == lyrics.count else {
      throw LyricsTranslationError.invalidResponse
    }

    return zip(lyrics, translatedLines).map { line, translatedText in
      line.withTranslation(translatedText)
    }
  }

  private var endpointURL: URL? {
    guard let raw = defaults.string(forKey: endpointKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
      !raw.isEmpty
    else {
      return nil
    }
    return URL(string: raw)
  }

  private func decodeTranslations(from data: Data) throws -> [String] {
    if let direct = try? JSONDecoder().decode([String].self, from: data) {
      return direct
    }
    if let wrapped = try? JSONDecoder().decode(TranslationResponse.self, from: data) {
      if !wrapped.lines.isEmpty {
        return wrapped.lines.map(\.text)
      }
      if !wrapped.translations.isEmpty {
        return wrapped.translations
      }
      if !wrapped.items.isEmpty {
        return wrapped.items.map(\.text)
      }
    }
    throw LyricsTranslationError.invalidResponse
  }
}

private struct TranslationRequest: Encodable {
  let songID: String
  let lyrics: [TranslationRequestLine]

  init(songID: String, lyrics: [LyricLine]) {
    self.songID = songID
    self.lyrics = lyrics.map { TranslationRequestLine(time: $0.time, text: $0.text) }
  }
}

private struct TranslationRequestLine: Encodable {
  let time: TimeInterval
  let text: String
}

private struct TranslationResponse: Decodable {
  let lines: [TranslationResponseLine]
  let translations: [String]
  let items: [TranslationResponseLine]

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    lines = (try? container.decode([TranslationResponseLine].self, forKey: .lines)) ?? []
    translations = (try? container.decode([String].self, forKey: .translations)) ?? []
    items = (try? container.decode([TranslationResponseLine].self, forKey: .items)) ?? []
  }

  private enum CodingKeys: String, CodingKey {
    case lines
    case translations
    case items
  }
}

private struct TranslationResponseLine: Decodable {
  let text: String
}
