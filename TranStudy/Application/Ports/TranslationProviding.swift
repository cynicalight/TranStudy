enum TranslationRequestKind: Codable, Equatable, Hashable, Sendable {
  case wordOrPhrase
  case contextualSelection
  case longText
}

struct TranslationRequest: Codable, Equatable, Hashable, Sendable {
  let sourceText: String
  let context: String?
  let kind: TranslationRequestKind
  let targetSentence: String?
  let chineseWritingSystem: ChineseWritingSystem

  init(
    sourceText: String,
    context: String? = nil,
    kind: TranslationRequestKind = .wordOrPhrase,
    targetSentence: String? = nil,
    chineseWritingSystem: ChineseWritingSystem = .simplified
  ) {
    self.sourceText = sourceText
    self.context = context
    self.kind = kind
    self.targetSentence = targetSentence
    self.chineseWritingSystem = chineseWritingSystem
  }

  var promptContent: String {
    guard let context, !context.isEmpty else {
      return sourceText
    }

    var content = """
      Target text:
      \(sourceText)

      Context:
      \(context)
      """
    if kind == .contextualSelection, let targetSentence {
      content += """


        Return this exact target sentence unchanged as example_sentence:
        \(targetSentence)
        Translate that exact sentence as sentence_translation. Use adjacent sentences only to
        disambiguate the target text; do not return either adjacent sentence as learning content.
        """
    }
    return content
  }
}

struct TranslationResult: Codable, Equatable, Sendable {
  let sourceText: String
  let canonicalForm: String
  let pronunciation: String
  let partOfSpeech: String
  let contextualMeaning: String
  let exampleSentence: String
  let sentenceTranslation: String
}

struct LongTextTranslationResult: Equatable, Sendable {
  let sourceText: String
  let translatedText: String
}

enum TranslationError: Error, Equatable, Sendable {
  case notConfigured
  case inputTooLong
  case timedOut
  case networkUnavailable
  case invalidResponse(
    TranslationResponseValidationFailure = .malformedPayload
  )
  case invalidRequest
  case authenticationFailed
  case quotaExceeded
  case rateLimited
  case serviceUnavailable

  var userFacingMessageKey: String {
    switch self {
    case .notConfigured:
      "尚未配置此翻译服务的 API Key。请到“设置 > 翻译服务”完成配置。"
    case .inputTooLong:
      "内容超过约 12000 字符或 token 预算，请缩短后重试。"
    case .timedOut:
      "翻译请求超时。请检查网络后重试。"
    case .networkUnavailable:
      "无法连接到翻译服务。请检查网络、代理或服务地址。"
    case .invalidResponse(let failure):
      failure.userFacingMessageKey
    case .invalidRequest:
      "翻译服务拒绝了请求。请检查服务地址、模型名称和输入内容。"
    case .authenticationFailed:
      "API Key 无效、已失效，或没有使用当前模型的权限。请在设置中更新 Key 或模型。"
    case .quotaExceeded:
      "API Key 的余额或可用额度不足。请在服务商后台充值，或更换 API Key。"
    case .rateLimited:
      "翻译请求过于频繁，服务暂时限流。请稍候再试。"
    case .serviceUnavailable:
      "翻译服务暂时不可用。请稍后重试。"
    }
  }
}

enum TranslationResponseValidationFailure: Equatable, Sendable {
  case malformedPayload
  case unexpectedInputKind
  case missingRequiredContent
  case invalidEnglishContent
  case invalidChineseContent

  var userFacingMessageKey: String {
    switch self {
    case .malformedPayload:
      "翻译服务返回的数据无法解析。请重试。"
    case .unexpectedInputKind:
      "翻译服务返回了错误的内容类型。请重试。"
    case .missingRequiredContent:
      "翻译服务返回的学习内容不完整。请重试。"
    case .invalidEnglishContent:
      "翻译服务返回的英文词条或例句无效。请重试。"
    case .invalidChineseContent:
      "翻译服务返回的中文释义或译文无效。请重试。"
    }
  }
}

@MainActor
protocol TranslationProviding {
  func translate(_ request: TranslationRequest) async throws -> TranslationResult
  func translateLongText(_ sourceText: String) async throws -> LongTextTranslationResult
  func translateLongText(
    _ sourceText: String,
    chineseWritingSystem: ChineseWritingSystem
  ) async throws -> LongTextTranslationResult
}

extension TranslationProviding {
  func translateLongText(_ sourceText: String) async throws -> LongTextTranslationResult {
    try await translateLongText(sourceText, chineseWritingSystem: .simplified)
  }

  func translateLongText(
    _ sourceText: String,
    chineseWritingSystem: ChineseWritingSystem
  ) async throws -> LongTextTranslationResult {
    throw TranslationError.invalidResponse(.malformedPayload)
  }
}
