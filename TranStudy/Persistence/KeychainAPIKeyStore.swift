import Foundation
import Security

enum KeychainError: Error {
  case unexpectedStatus(OSStatus)
}

@MainActor
final class KeychainAPIKeyStore: APIKeyStoring {
  private let account = "api-key"

  func loadAPIKey(for provider: TranslationProviderKind) throws -> String? {
    var query = baseQuery(for: provider)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    if status == errSecItemNotFound {
      return nil
    }

    guard status == errSecSuccess else {
      throw KeychainError.unexpectedStatus(status)
    }

    guard
      let data = result as? Data,
      let apiKey = String(data: data, encoding: .utf8)
    else {
      throw KeychainError.unexpectedStatus(errSecDecode)
    }

    return apiKey
  }

  func saveAPIKey(_ apiKey: String, for provider: TranslationProviderKind) throws {
    let data = Data(apiKey.utf8)
    let updateStatus = SecItemUpdate(
      baseQuery(for: provider) as CFDictionary,
      [kSecValueData as String: data] as CFDictionary
    )

    if updateStatus == errSecSuccess {
      return
    }

    guard updateStatus == errSecItemNotFound else {
      throw KeychainError.unexpectedStatus(updateStatus)
    }

    var addition = baseQuery(for: provider)
    addition[kSecValueData as String] = data
    addition[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let addStatus = SecItemAdd(addition as CFDictionary, nil)

    guard addStatus == errSecSuccess else {
      throw KeychainError.unexpectedStatus(addStatus)
    }
  }

  private func baseQuery(for provider: TranslationProviderKind) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service(for: provider),
      kSecAttrAccount as String: account,
    ]
  }

  private func service(for provider: TranslationProviderKind) -> String {
    switch provider {
    case .deepSeek:
      "com.cynicalight.TranStudy.deepseek"
    case .openAICompatible:
      "com.cynicalight.TranStudy.openai-compatible"
    }
  }
}
