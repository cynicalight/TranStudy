import Foundation

enum LearningStoreLocationError: Error {
  case applicationSupportDirectoryUnavailable
}

enum LearningStoreLocation {
  static func preparePersistentStoreURL(
    applicationSupportDirectory: URL? =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
    fileManager: FileManager = .default
  ) throws -> URL {
    guard let applicationSupportDirectory else {
      throw LearningStoreLocationError.applicationSupportDirectoryUnavailable
    }
    let directory =
      applicationSupportDirectory
      .appending(path: "TranStudy", directoryHint: .isDirectory)
    try fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let storeURL = directory.appending(path: "learning.store")
    guard !fileManager.fileExists(atPath: storeURL.path) else {
      return storeURL
    }

    let legacyStoreURL = applicationSupportDirectory.appending(path: "default.store")
    guard fileManager.fileExists(atPath: legacyStoreURL.path) else {
      return storeURL
    }

    let storeWALURL = URL(fileURLWithPath: storeURL.path + "-wal")
    let migrationPrefix = ".learning-store-migration-\(UUID().uuidString)"
    let temporaryStoreURL = directory.appending(path: migrationPrefix)
    let temporaryWALURL = URL(fileURLWithPath: temporaryStoreURL.path + "-wal")
    var installedURLs: [URL] = []
    do {
      try copyStoreFile(
        from: legacyStoreURL,
        to: temporaryStoreURL,
        fileManager: fileManager
      )

      let legacyWALURL = URL(fileURLWithPath: legacyStoreURL.path + "-wal")
      if fileManager.fileExists(atPath: legacyWALURL.path) {
        try copyStoreFile(
          from: legacyWALURL,
          to: temporaryWALURL,
          fileManager: fileManager
        )
      }

      if fileManager.fileExists(atPath: storeWALURL.path) {
        try fileManager.removeItem(at: storeWALURL)
      }
      if fileManager.fileExists(atPath: temporaryWALURL.path) {
        try fileManager.moveItem(at: temporaryWALURL, to: storeWALURL)
        installedURLs.append(storeWALURL)
      }
      try fileManager.moveItem(at: temporaryStoreURL, to: storeURL)
    } catch {
      for installedURL in installedURLs.reversed() {
        try? fileManager.removeItem(at: installedURL)
      }
      try? fileManager.removeItem(at: temporaryWALURL)
      try? fileManager.removeItem(at: temporaryStoreURL)
      throw error
    }
    return storeURL
  }

  private static func copyStoreFile(
    from sourceURL: URL,
    to destinationURL: URL,
    fileManager: FileManager
  ) throws {
    try fileManager.copyItem(at: sourceURL, to: destinationURL)
    try fileManager.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: destinationURL.path
    )
  }
}
