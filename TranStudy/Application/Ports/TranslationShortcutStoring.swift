import Foundation

enum TranslationShortcutKey: String, CaseIterable, Codable, Identifiable, Sendable {
  case f1
  case f2
  case f3
  case f4
  case f5
  case f6
  case f7
  case f8
  case f9
  case f10
  case f11
  case f12

  static let `default`: TranslationShortcutKey = .f5

  var id: String {
    rawValue
  }

  var title: String {
    rawValue.uppercased()
  }
}

protocol TranslationShortcutStoring {
  func load() -> TranslationShortcutKey
  func save(_ shortcut: TranslationShortcutKey)
}
