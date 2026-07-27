import Foundation
import Security

enum KeychainError: Error {
  case unexpectedStatus(OSStatus)
}

@MainActor
final class KeychainAPIKeyStore: APIKeyStoring {
  private let service = "com.cynicalight.TranStudy.deepseek"
  private let account = "api-key"

  func loadAPIKey() throws -> String? {
    var query = baseQuery
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

  func saveAPIKey(_ apiKey: String) throws {
    let data = Data(apiKey.utf8)
    let updateStatus = SecItemUpdate(
      baseQuery as CFDictionary,
      [kSecValueData as String: data] as CFDictionary
    )

    if updateStatus == errSecSuccess {
      return
    }

    guard updateStatus == errSecItemNotFound else {
      throw KeychainError.unexpectedStatus(updateStatus)
    }

    var addition = baseQuery
    addition[kSecValueData as String] = data
    addition[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let addStatus = SecItemAdd(addition as CFDictionary, nil)

    guard addStatus == errSecSuccess else {
      throw KeychainError.unexpectedStatus(addStatus)
    }
  }

  private var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}
