import ApplicationServices
import Foundation

struct SelectionControlAttributes: Equatable, Sendable {
  let role: String?
  let subrole: String?
  let containsProtectedContent: Bool?
}

enum SelectionControlRejectionReason: String, Equatable, Sendable {
  case secureTextField = "secure-text-field"
  case protectedContent = "protected-content"
  case unconfirmedTextField = "unconfirmed-text-field-subrole"
}

enum SelectionControlPrivacyPolicy {
  static func rejectionReason(
    for attributes: SelectionControlAttributes
  ) -> SelectionControlRejectionReason? {
    if attributes.subrole == kAXSecureTextFieldSubrole as String {
      return .secureTextField
    }
    if attributes.containsProtectedContent == true {
      return .protectedContent
    }
    if attributes.role == kAXTextFieldRole as String,
      attributes.subrole == nil || attributes.subrole == kAXUnknownSubrole as String
    {
      return .unconfirmedTextField
    }
    return nil
  }
}
