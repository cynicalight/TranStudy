@MainActor
protocol TranslationCacheStoring {
  func value(for key: TranslationCacheKey) -> TranslationResult?
  func insert(_ result: TranslationResult, for key: TranslationCacheKey)
  func clear() throws
}
