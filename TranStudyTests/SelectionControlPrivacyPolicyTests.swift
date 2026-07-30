import ApplicationServices
import Testing

@testable import TranStudy

struct SelectionControlPrivacyPolicyTests {
  @Test("secure and protected controls are always rejected")
  func secureAndProtectedControlsAreRejected() {
    #expect(
      SelectionControlPrivacyPolicy.rejectionReason(
        for: SelectionControlAttributes(
          role: kAXTextFieldRole as String,
          subrole: kAXSecureTextFieldSubrole as String,
          containsProtectedContent: false
        ))
        == .secureTextField
    )
    #expect(
      SelectionControlPrivacyPolicy.rejectionReason(
        for: SelectionControlAttributes(
          role: kAXStaticTextRole as String,
          subrole: nil,
          containsProtectedContent: true
        ))
        == .protectedContent
    )
  }

  @Test("text fields with unknown security attributes are rejected")
  func unconfirmedTextFieldsAreRejected() {
    for subrole in [nil, kAXUnknownSubrole as String?] {
      #expect(
        SelectionControlPrivacyPolicy.rejectionReason(
          for: SelectionControlAttributes(
            role: kAXTextFieldRole as String,
            subrole: subrole,
            containsProtectedContent: nil
          ))
          == .unconfirmedTextField
      )
    }
  }

  @Test("a confirmed non-sensitive text field is eligible")
  func confirmedNonSensitiveTextFieldIsEligible() {
    #expect(
      SelectionControlPrivacyPolicy.rejectionReason(
        for: SelectionControlAttributes(
          role: kAXTextFieldRole as String,
          subrole: kAXSearchFieldSubrole as String,
          containsProtectedContent: false
        ))
        == nil
    )
  }

  @Test("ordinary accessible text is eligible")
  func ordinaryAccessibleTextIsEligible() {
    #expect(
      SelectionControlPrivacyPolicy.rejectionReason(
        for: SelectionControlAttributes(
          role: kAXStaticTextRole as String,
          subrole: nil,
          containsProtectedContent: false
        ))
        == nil
    )
  }
}
