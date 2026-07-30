import Foundation

enum InterfaceLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
  case system
  case simplifiedChinese
  case traditionalChinese
  case english

  var id: Self {
    self
  }

  var localizationIdentifier: String? {
    switch self {
    case .system:
      nil
    case .simplifiedChinese:
      "zh-Hans"
    case .traditionalChinese:
      "zh-Hant"
    case .english:
      "en"
    }
  }

  var locale: Locale {
    localizationIdentifier.map(Locale.init(identifier:)) ?? .autoupdatingCurrent
  }
}

enum ChineseWritingSystem: String, CaseIterable, Codable, Identifiable, Sendable {
  case simplified
  case traditional

  var id: Self {
    self
  }

  var promptInstruction: String {
    switch self {
    case .simplified:
      "Use Simplified Chinese characters for every Chinese output field."
    case .traditional:
      "Use Traditional Chinese characters for every Chinese output field."
    }
  }
}

struct LanguageAndSpeechPreferences: Codable, Equatable, Sendable {
  var interfaceLanguage: InterfaceLanguage
  var chineseWritingSystem: ChineseWritingSystem
  var speechVoiceIdentifier: String?
  var speechRate: Float
  var automaticallySpeaksTranslations: Bool

  static let `default` = LanguageAndSpeechPreferences(
    interfaceLanguage: .system,
    chineseWritingSystem: .simplified,
    speechVoiceIdentifier: nil,
    speechRate: 0.5,
    automaticallySpeaksTranslations: false
  )
}
