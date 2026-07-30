import Foundation

@MainActor
final class FileTranslationCacheStore: TranslationCacheStoring {
  private let fileURL: URL
  private var entries: [TranslationCacheKey: TranslationResult]

  init(fileURL: URL = FileTranslationCacheStore.defaultFileURL) {
    self.fileURL = fileURL
    entries = Self.load(from: fileURL)
  }

  func value(for key: TranslationCacheKey) -> TranslationResult? {
    entries[key]
  }

  func insert(_ result: TranslationResult, for key: TranslationCacheKey) {
    entries[key] = result
    persist()
  }

  func clear() throws {
    entries.removeAll()
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return
    }
    try FileManager.default.removeItem(at: fileURL)
  }

  private func persist() {
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let data = try JSONEncoder().encode(entries)
      try data.write(to: fileURL, options: .atomic)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: fileURL.path
      )
    } catch {
      // Cache failures must never prevent a translation from succeeding.
    }
  }

  private static func load(
    from fileURL: URL
  ) -> [TranslationCacheKey: TranslationResult] {
    guard
      let data = try? Data(contentsOf: fileURL),
      let entries = try? JSONDecoder().decode(
        [TranslationCacheKey: TranslationResult].self,
        from: data
      )
    else {
      return [:]
    }

    return entries
  }

  private static var defaultFileURL: URL {
    let applicationSupport =
      FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first ?? FileManager.default.temporaryDirectory

    return
      applicationSupport
      .appending(path: "com.cynicalight.TranStudy", directoryHint: .isDirectory)
      .appending(path: "translation-cache.json")
  }
}
