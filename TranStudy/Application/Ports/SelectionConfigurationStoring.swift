import Foundation

struct ExcludedApplication: Codable, Equatable, Hashable, Identifiable, Sendable {
  let bundleIdentifier: String
  let displayName: String

  var id: String {
    bundleIdentifier
  }
}

struct SelectionConfiguration: Codable, Equatable, Sendable {
  var isEnabled: Bool
  var excludedApplications: [ExcludedApplication]

  static let `default` = SelectionConfiguration(
    isEnabled: true,
    excludedApplications: []
  )

  func excludes(bundleIdentifier: String) -> Bool {
    excludedApplications.contains {
      $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
    }
  }
}

protocol SelectionConfigurationStoring {
  func load() -> SelectionConfiguration
  func save(_ configuration: SelectionConfiguration)
}
