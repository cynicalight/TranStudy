import Foundation

struct TranslationCacheKey: Codable, Hashable, Sendable {
  let provider: TranslationProviderKind
  let endpoint: String
  let model: String
  let request: TranslationRequest

  init(
    configuration: TranslationProviderConfiguration,
    request: TranslationRequest
  ) {
    provider = configuration.provider
    self.request = request

    switch configuration.provider {
    case .deepSeek:
      endpoint = "https://api.deepseek.com"
      model = "\(configuration.deepSeekModel.rawValue)#response-v2"
    case .openAICompatible:
      endpoint = configuration.customBaseURL.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      model =
        configuration.customModel.trimmingCharacters(
          in: .whitespacesAndNewlines
        ) + "#response-v2"
    }
  }
}
