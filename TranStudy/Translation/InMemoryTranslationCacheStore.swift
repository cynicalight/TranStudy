@MainActor
final class InMemoryTranslationCacheStore: TranslationCacheStoring {
  private var entries: [TranslationCacheKey: TranslationResult] = [:]

  func value(for key: TranslationCacheKey) -> TranslationResult? {
    entries[key]
  }

  func insert(_ result: TranslationResult, for key: TranslationCacheKey) {
    entries[key] = result
  }

  func clear() throws {
    entries.removeAll()
  }
}
