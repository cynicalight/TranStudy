import AppKit
import ApplicationServices
import Foundation

@MainActor
final class AccessibilitySelectionProvider: SelectionProviding {
  private static let supportedBundleIdentifiers: Set<String> = [
    "com.apple.Safari",
    "com.apple.TextEdit",
  ]

  private var candidatePosition: CGPoint?
  private var gestureStartFingerprint: SelectionFingerprint?
  private var candidateFingerprint: SelectionFingerprint?

  private struct ActiveSelection {
    let application: NSRunningApplication
    let element: AXUIElement
    let selectedText: String
    let fingerprint: SelectionFingerprint
  }

  private struct SelectionFingerprint: Equatable {
    let processIdentifier: pid_t
    let selectedText: String
    let rangeIdentity: String
  }

  init(requestAccess: Bool = true) {
    guard requestAccess else {
      return
    }

    AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
  }

  func beginMouseSelectionGesture() {
    gestureStartFingerprint = activeSelection()?.fingerprint
    candidateFingerprint = nil
    candidatePosition = nil
  }

  func selectionCandidate(at screenPosition: CGPoint) async -> SelectionCandidate? {
    guard
      let activeSelection = activeSelection(),
      activeSelection.fingerprint != gestureStartFingerprint
    else {
      gestureStartFingerprint = nil
      candidateFingerprint = nil
      candidatePosition = nil
      return nil
    }

    gestureStartFingerprint = nil
    candidateFingerprint = activeSelection.fingerprint
    candidatePosition = screenPosition
    return SelectionCandidate(
      screenPosition: screenPosition,
      sourceApplicationName: sourceApplicationName(for: activeSelection.application)
    )
  }

  func currentSelection() async -> SelectionSnapshot? {
    guard
      let activeSelection = activeSelection(),
      let candidatePosition,
      activeSelection.fingerprint == candidateFingerprint
    else {
      return nil
    }

    guard
      let context = selectionContext(in: activeSelection.element)
    else {
      return nil
    }
    return SelectionSnapshot(
      selectedText: activeSelection.selectedText,
      targetSentence: context.targetSentence,
      previousSentence: context.previousSentence,
      nextSentence: context.nextSentence,
      screenPosition: candidatePosition,
      sourceApplicationName: sourceApplicationName(for: activeSelection.application)
    )
  }

  func isSelectionCandidateCurrent() async -> Bool {
    guard
      let candidateFingerprint,
      let activeSelection = activeSelection()
    else {
      return false
    }
    return activeSelection.fingerprint == candidateFingerprint
  }

  private func activeSelection() -> ActiveSelection? {
    guard
      AXIsProcessTrusted(),
      let application = supportedFrontmostApplication(),
      let element = selectedElement(),
      let selectedText = selectedText(in: element)
    else {
      return nil
    }
    let fingerprint = selectionFingerprint(
      application: application,
      element: element,
      selectedText: selectedText
    )
    return ActiveSelection(
      application: application,
      element: element,
      selectedText: selectedText,
      fingerprint: fingerprint
    )
  }

  private func selectionFingerprint(
    application: NSRunningApplication,
    element: AXUIElement,
    selectedText: String
  ) -> SelectionFingerprint {
    let rangeIdentity: String
    if let range = selectedRange(in: element) {
      rangeIdentity = "range:\(range.location):\(range.length)"
    } else if let range = textMarkerRangeAttribute(
      kAXSelectedTextMarkerRangeAttribute as CFString,
      from: element
    ) {
      rangeIdentity = "marker:\(CFHash(range))"
    } else {
      rangeIdentity = "text-only"
    }
    return SelectionFingerprint(
      processIdentifier: application.processIdentifier,
      selectedText: selectedText,
      rangeIdentity: rangeIdentity
    )
  }

  private func sourceApplicationName(for application: NSRunningApplication) -> String {
    application.localizedName ?? "未知应用"
  }

  private func supportedFrontmostApplication() -> NSRunningApplication? {
    guard
      let application = NSWorkspace.shared.frontmostApplication,
      let bundleIdentifier = application.bundleIdentifier,
      Self.supportedBundleIdentifiers.contains(bundleIdentifier)
    else {
      return nil
    }
    return application
  }

  private func selectedElement() -> AXUIElement? {
    let systemWideElement = AXUIElementCreateSystemWide()
    guard
      let focusedElement = copyUIElementAttribute(
        kAXFocusedUIElementAttribute as CFString,
        from: systemWideElement
      )
    else {
      return nil
    }

    var currentElement: AXUIElement? = focusedElement
    for _ in 0..<8 {
      guard let element = currentElement else {
        break
      }
      if selectedText(in: element) != nil {
        return element
      }
      currentElement = copyUIElementAttribute(kAXParentAttribute as CFString, from: element)
    }
    return nil
  }

  private func selectedText(in element: AXUIElement) -> String? {
    guard
      let text = copyAttribute(kAXSelectedTextAttribute as CFString, from: element)
        as? String,
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return nil
    }
    return text
  }

  private func selectionContext(in element: AXUIElement) -> SelectionSentenceContext? {
    if let context = webSelectionContext(in: element) {
      return context
    }

    guard
      let selectedRange = selectedRange(in: element),
      let documentText = documentText(in: element, selectedRange: selectedRange)
    else {
      return nil
    }

    return SelectionSentenceContext.extract(
      from: documentText,
      selectedRange: selectedRange
    )
  }

  private func webSelectionContext(in element: AXUIElement) -> SelectionSentenceContext? {
    guard
      let selectedRange = textMarkerRangeAttribute(
        kAXSelectedTextMarkerRangeAttribute as CFString,
        from: element
      )
    else {
      return nil
    }

    let selectionStart = AXTextMarkerRangeCopyStartMarker(selectedRange)
    guard
      let targetRange = textMarkerRangeParameterizedAttribute(
        kAXSentenceTextMarkerRangeForTextMarkerParameterizedAttribute as CFString,
        parameter: selectionStart,
        from: element
      ),
      let targetSentence = string(for: targetRange, in: element)
    else {
      return nil
    }

    let targetStart = AXTextMarkerRangeCopyStartMarker(targetRange)
    let targetEnd = AXTextMarkerRangeCopyEndMarker(targetRange)
    let previousSentence =
      textMarkerParameterizedAttribute(
        kAXPreviousSentenceStartTextMarkerForTextMarkerParameterizedAttribute as CFString,
        parameter: targetStart,
        from: element
      ).flatMap { previousStart in
        string(
          for: AXTextMarkerRangeCreate(nil, previousStart, targetStart),
          in: element
        )
      }
    let nextSentence =
      textMarkerParameterizedAttribute(
        kAXNextSentenceEndTextMarkerForTextMarkerParameterizedAttribute as CFString,
        parameter: targetEnd,
        from: element
      ).flatMap { nextEnd in
        string(
          for: AXTextMarkerRangeCreate(nil, targetEnd, nextEnd),
          in: element
        )
      }

    return SelectionSentenceContext(
      targetSentence: targetSentence,
      previousSentence: previousSentence,
      nextSentence: nextSentence
    )
  }

  private func selectedRange(in element: AXUIElement) -> CFRange? {
    guard
      let rawValue = copyAttribute(
        kAXSelectedTextRangeAttribute as CFString,
        from: element
      ),
      CFGetTypeID(rawValue) == AXValueGetTypeID()
    else {
      return nil
    }
    let value = unsafeDowncast(rawValue, to: AXValue.self)
    guard AXValueGetType(value) == .cfRange else {
      return nil
    }

    var range = CFRange()
    guard AXValueGetValue(value, .cfRange, &range) else {
      return nil
    }
    return range
  }

  private func documentText(in element: AXUIElement, selectedRange: CFRange) -> String? {
    if let text = copyAttribute(kAXValueAttribute as CFString, from: element) as? String,
      selectedRange.location >= 0,
      selectedRange.location + selectedRange.length <= (text as NSString).length
    {
      return text
    }

    guard
      let characterCount =
        copyAttribute(kAXNumberOfCharactersAttribute as CFString, from: element)
        as? NSNumber,
      characterCount.intValue > 0
    else {
      return nil
    }

    var fullRange = CFRange(location: 0, length: characterCount.intValue)
    guard
      let rangeValue = AXValueCreate(.cfRange, &fullRange),
      let text = copyParameterizedAttribute(
        kAXStringForRangeParameterizedAttribute as CFString,
        parameter: rangeValue,
        from: element
      ) as? String
    else {
      return nil
    }
    return text
  }

  private func copyAttribute(
    _ attribute: CFString,
    from element: AXUIElement
  ) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
      return nil
    }
    return value
  }

  private func copyUIElementAttribute(
    _ attribute: CFString,
    from element: AXUIElement
  ) -> AXUIElement? {
    guard
      let value = copyAttribute(attribute, from: element),
      CFGetTypeID(value) == AXUIElementGetTypeID()
    else {
      return nil
    }
    return unsafeDowncast(value, to: AXUIElement.self)
  }

  private func textMarkerRangeAttribute(
    _ attribute: CFString,
    from element: AXUIElement
  ) -> AXTextMarkerRange? {
    guard
      let value = copyAttribute(attribute, from: element),
      CFGetTypeID(value) == AXTextMarkerRangeGetTypeID()
    else {
      return nil
    }
    return unsafeDowncast(value, to: AXTextMarkerRange.self)
  }

  private func textMarkerRangeParameterizedAttribute(
    _ attribute: CFString,
    parameter: AXTextMarker,
    from element: AXUIElement
  ) -> AXTextMarkerRange? {
    guard
      let value = copyParameterizedAttribute(
        attribute,
        parameter: parameter,
        from: element
      ),
      CFGetTypeID(value) == AXTextMarkerRangeGetTypeID()
    else {
      return nil
    }
    return unsafeDowncast(value, to: AXTextMarkerRange.self)
  }

  private func textMarkerParameterizedAttribute(
    _ attribute: CFString,
    parameter: AXTextMarker,
    from element: AXUIElement
  ) -> AXTextMarker? {
    guard
      let value = copyParameterizedAttribute(
        attribute,
        parameter: parameter,
        from: element
      ),
      CFGetTypeID(value) == AXTextMarkerGetTypeID()
    else {
      return nil
    }
    return unsafeDowncast(value, to: AXTextMarker.self)
  }

  private func string(
    for range: AXTextMarkerRange,
    in element: AXUIElement
  ) -> String? {
    guard
      let value = copyParameterizedAttribute(
        kAXStringForTextMarkerRangeParameterizedAttribute as CFString,
        parameter: range,
        from: element
      ) as? String
    else {
      return nil
    }
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
  }

  private func copyParameterizedAttribute(
    _ attribute: CFString,
    parameter: CFTypeRef,
    from element: AXUIElement
  ) -> CFTypeRef? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyParameterizedAttributeValue(
        element,
        attribute,
        parameter,
        &value
      ) == .success
    else {
      return nil
    }
    return value
  }
}
