import Foundation

enum AppLocalization {
  static let supportedIdentifiers = ["zh-Hans", "zh-Hant", "en"]

  static func string(
    _ key: String,
    language: InterfaceLanguage
  ) -> String {
    localizedBundle(for: language).localizedString(
      forKey: key,
      value: key,
      table: nil
    )
  }

  static func format(
    _ key: String,
    language: InterfaceLanguage,
    _ arguments: CVarArg...
  ) -> String {
    String(
      format: string(key, language: language),
      locale: language.locale,
      arguments: arguments
    )
  }

  private static func localizedBundle(
    for language: InterfaceLanguage
  ) -> Bundle {
    let identifier =
      language.localizationIdentifier
      ?? Bundle.preferredLocalizations(
        from: supportedIdentifiers,
        forPreferences: Locale.preferredLanguages
      ).first
      ?? "zh-Hans"

    guard
      let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
      let bundle = Bundle(path: path)
    else {
      return .main
    }
    return bundle
  }
}

extension ApplicationShell {
  func localized(_ key: String) -> String {
    AppLocalization.string(key, language: interfaceLanguage)
  }

  func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    String(
      format: localized(key),
      locale: interfaceLanguage.locale,
      arguments: arguments
    )
  }
}
