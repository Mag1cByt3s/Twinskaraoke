import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
  case system
  case english = "en"
  case simplifiedChinese = "zh-Hans"
  case traditionalChinese = "zh-Hant"
  case japanese = "ja"
  case french = "fr"
  case german = "de"
  case finnish = "fi"
  case ukrainian = "uk"

  static let storageKey = "nk.language"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .system: return "System"
    case .english: return "English"
    case .simplifiedChinese: return "简体中文"
    case .traditionalChinese: return "繁體中文"
    case .japanese: return "日本語"
    case .french: return "Français"
    case .german: return "Deutsch"
    case .finnish: return "Suomi"
    case .ukrainian: return "Українська"
    }
  }

  var localeIdentifier: String {
    switch self {
    case .system:
      return Locale.current.identifier
    case .english:
      return "en"
    case .simplifiedChinese:
      return "zh-Hans"
    case .traditionalChinese:
      return "zh-Hant"
    case .japanese:
      return "ja"
    case .french:
      return "fr"
    case .german:
      return "de"
    case .finnish:
      return "fi"
    case .ukrainian:
      return "uk"
    }
  }
}
