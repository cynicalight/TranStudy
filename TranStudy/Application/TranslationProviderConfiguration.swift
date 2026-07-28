enum TranslationProviderKind: String, CaseIterable, Codable, Identifiable, Sendable {
  case deepSeek
  case openAICompatible

  var id: Self {
    self
  }

  var title: String {
    switch self {
    case .deepSeek:
      "DeepSeek"
    case .openAICompatible:
      "OpenAI 兼容接口"
    }
  }
}

struct TranslationProviderConfiguration: Codable, Equatable, Sendable {
  var provider: TranslationProviderKind
  var deepSeekModel: DeepSeekModel
  var customBaseURL: String
  var customModel: String

  static let `default` = TranslationProviderConfiguration(
    provider: .deepSeek,
    deepSeekModel: .flash,
    customBaseURL: "",
    customModel: ""
  )
}
