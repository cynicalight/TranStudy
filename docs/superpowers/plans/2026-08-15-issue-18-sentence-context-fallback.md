# Issue 18 Sentence Context Fallback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fall back to captured sentence context when Accessibility cannot expand a selection into a surrounding word window, so correct contextual translations are accepted.

**Architecture:** Make an optional `SelectionWordContext` mean that a usable surrounding window really exists. Sanitize captures at the Accessibility adapter seam, activate the existing sentence prompt fallback, and validate responses against the sentence hint when strict word-window validation is unavailable.

**Tech Stack:** Swift 6, macOS Accessibility text markers, Swift Testing, Xcode Debug and Release configurations

## Global Constraints

- Do not change word-or-phrase versus long-text classification.
- A usable word context has non-whitespace content on at least one surrounding side.
- Keep one empty side valid for document-start and document-end selections.
- Publish selection-only word-context captures as `nil`.
- Keep strict existing validation when a usable word window exists.
- Validate fallback with selected-text containment and bidirectional target-hint containment.
- Preserve the existing Debug-only Issue 18 log and exclude it from Release artifacts.

---

### Task 0: Preserve the completed reproduction instrumentation

**Files:**
- Modify: `TranStudy/Translation/OpenAIChatTranslationClient.swift`
- Test: `TranStudyTests/DeepSeekTranslationProviderTests.swift`

**Interfaces:**
- Consumes: Existing `Issue18DebugFileLogger` invalid-response path.
- Produces: A committed baseline that records raw and normalized mismatch details.

- [ ] **Step 1: Verify the focused Debug tests**

```bash
xcodebuild test -project TranStudy.xcodeproj -scheme TranStudy \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/TranStudyIssue18Run \
  -disableAutomaticPackageResolution \
  -only-testing:TranStudyTests/DeepSeekTranslationProviderTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: 8 tests pass, including the selection-context comparison log test.

- [ ] **Step 2: Confirm and commit only the instrumentation**

```bash
git diff --check
git add TranStudy/Translation/OpenAIChatTranslationClient.swift \
  TranStudyTests/DeepSeekTranslationProviderTests.swift
git commit -m "chore(translation): log context mismatch details"
```

Expected: the commit contains only Debug diagnostic fields and their test.

### Task 1: Define usable surrounding word context

**Files:**
- Modify: `TranStudy/Application/SelectionSentenceContext.swift:3-22`
- Test: `TranStudyTests/SelectionSentenceContextTests.swift`

**Interfaces:**
- Consumes: `SelectionWordContext.precedingText` and `.followingText`.
- Produces: `SelectionWordContext.hasSurroundingContent: Bool`.

- [ ] **Step 1: Write failing usability tests**

```swift
@Test("selection-only word context is not a surrounding word window")
func selectionOnlyWordContextIsNotUsable() {
  let context = SelectionWordContext(
    precedingText: " \n",
    selectedText: "where",
    followingText: "\t"
  )
  #expect(!context.hasSurroundingContent)
}

@Test("one populated side keeps a boundary word context usable")
func onePopulatedSideKeepsWordContextUsable() {
  let documentStart = SelectionWordContext(
    precedingText: "",
    selectedText: "First",
    followingText: " word after"
  )
  let documentEnd = SelectionWordContext(
    precedingText: "word before ",
    selectedText: "last",
    followingText: ""
  )
  #expect(documentStart.hasSurroundingContent)
  #expect(documentEnd.hasSurroundingContent)
}
```

- [ ] **Step 2: Run the tests to verify RED**

```bash
xcodebuild test -project TranStudy.xcodeproj -scheme TranStudy \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/TranStudyIssue18Run \
  -disableAutomaticPackageResolution \
  -only-testing:TranStudyTests/SelectionSentenceContextTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: compilation fails because `hasSurroundingContent` does not exist.

- [ ] **Step 3: Implement the minimal invariant**

```swift
var hasSurroundingContent: Bool {
  !precedingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    || !followingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}
```

- [ ] **Step 4: Run the focused tests to verify GREEN and commit**

Run the Task 1 command again. Expected: all tests pass.

```bash
git add TranStudy/Application/SelectionSentenceContext.swift \
  TranStudyTests/SelectionSentenceContextTests.swift
git commit -m "fix(selection): detect missing word context"
```

### Task 2: Publish sentence fallback from the Accessibility adapter

**Files:**
- Modify: `TranStudy/System/AccessibilitySelectionProvider.swift:24-30,101-122,376-573`
- Test: `TranStudyTests/SelectionSentenceContextTests.swift`
- Test: `TranStudyTests/ApplicationShellTests.swift:167-235`

**Interfaces:**
- Consumes: `SelectionWordContext.hasSurroundingContent`.
- Produces: `SelectionContextCapture.wordContext: SelectionWordContext?` and a snapshot whose word context is `nil` for selection-only captures.

- [ ] **Step 1: Write the failing adapter-capture test**

Add to `SelectionSentenceContextTests`:

```swift
@Test("selection-only word capture preserves the sentence fallback")
@MainActor
func selectionOnlyWordCapturePreservesSentenceFallback() throws {
  let sentenceContext = SelectionSentenceContext(
    targetSentence: "You can use it where you work.",
    previousSentence: nil,
    nextSentence: nil
  )
  let capture = try #require(
    AccessibilitySelectionProvider.SelectionContextCapture(
      sentenceContext: sentenceContext,
      wordContext: SelectionWordContext(
        precedingText: "",
        selectedText: "where",
        followingText: ""
      )
    ))

  #expect(capture.sentenceContext == sentenceContext)
  #expect(capture.wordContext == nil)
  #expect(capture.sourceWordWindowText == sentenceContext.targetSentence)
}

@Test("selection-only word capture without a sentence is unavailable")
@MainActor
func selectionOnlyWordCaptureWithoutSentenceIsUnavailable() {
  let capture = AccessibilitySelectionProvider.SelectionContextCapture(
    sentenceContext: nil,
    wordContext: SelectionWordContext(
      precedingText: "",
      selectedText: "where",
      followingText: ""
    )
  )

  #expect(capture == nil)
}
```

- [ ] **Step 2: Add a downstream fallback characterization test**

```swift
@Test("missing word window sends sentence context without strict word validation input")
func missingWordWindowUsesSentenceContext() async throws {
  let translator = TestTranslationProvider(
    result: TranslationResult(
      sourceText: "where",
      canonicalForm: "where",
      pronunciation: "/wɛr/",
      partOfSpeech: "adverb",
      contextualMeaning: "在那里",
      exampleSentence: "You can use it where you work.",
      sentenceTranslation: "你可以在工作的地方使用它。"
    ))
  let shell = ApplicationShell(environment: .test(translation: translator))
  let snapshot = SelectionSnapshot(
    selectedText: "where",
    targetSentence: "You can use it where you work.",
    previousSentence: "The service is portable.",
    nextSentence: "It also supports messages.",
    wordContext: nil,
    screenPosition: CGPoint(x: 640, y: 420),
    sourceApplicationName: "Zen Browser"
  )

  await shell.translateSelection(snapshot)

  #expect(
    translator.lastRequest
      == TranslationRequest(
        sourceText: "where",
        context: [
          "Previous sentence:\nThe service is portable.",
          "Target sentence:\nYou can use it where you work.",
          "Next sentence:\nIt also supports messages.",
        ].joined(separator: "\n\n"),
        kind: .contextualSelection,
        targetSentence: "You can use it where you work.",
        selectionWordContext: nil
      ))
}
```

- [ ] **Step 3: Run the tests to verify RED**

```bash
xcodebuild test -project TranStudy.xcodeproj -scheme TranStudy \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/TranStudyIssue18Run \
  -disableAutomaticPackageResolution \
  -only-testing:TranStudyTests/SelectionSentenceContextTests \
  -only-testing:TranStudyTests/ApplicationShellTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: compilation fails because the current nested `SelectionContextCapture`
is private, has a non-optional word context, and does not provide the failable
invariant-enforcing initializer. The downstream characterization documents the
already-working caller behavior that the adapter must activate.

- [ ] **Step 4: Make capture enforce the optional word-context invariant**

```swift
struct SelectionContextCapture {
  let sentenceContext: SelectionSentenceContext?
  let wordContext: SelectionWordContext?

  init?(
    sentenceContext: SelectionSentenceContext?,
    wordContext candidate: SelectionWordContext?
  ) {
    let wordContext = candidate?.hasSurroundingContent == true ? candidate : nil
    guard sentenceContext != nil || wordContext != nil else {
      return nil
    }
    self.sentenceContext = sentenceContext
    self.wordContext = wordContext
  }

  var sourceWordWindowText: String {
    wordContext?.combinedText ?? sentenceContext?.targetSentence ?? ""
  }
}
```

Update the length diagnostic to use:

```swift
contextCapture.wordContext?.precedingText.count ?? 0
contextCapture.wordContext?.followingText.count ?? 0
```

- [ ] **Step 5: Route both extraction paths through the failable initializer**

For the AX range/document path, replace the required word-context guard with
independent extraction:

```swift
let wordContext = SelectionWordContext.extract(
  from: documentText,
  selectedRange: selectedRange
)
let sentenceContext = SelectionSentenceContext.extract(
  from: documentText,
  selectedRange: selectedRange
)
```

Then route the result through the failable initializer:

```swift
return SelectionContextCapture(
  sentenceContext: sentenceContext,
  wordContext: wordContext
)
```

For the web path, replace the required word-context guard with:

```swift
let wordContext = webWordContext(selectedRange: selectedRange, in: element)
```

Return every paragraph/sentence branch through the failable initializer. If sentence-marker extraction fails, return:

```swift
return SelectionContextCapture(
  sentenceContext: nil,
  wordContext: wordContext
)
```

- [ ] **Step 6: Run focused tests and commit**

```bash
xcodebuild test -project TranStudy.xcodeproj -scheme TranStudy \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/TranStudyIssue18Run \
  -disableAutomaticPackageResolution \
  -only-testing:TranStudyTests/SelectionSentenceContextTests \
  -only-testing:TranStudyTests/ApplicationShellTests \
  CODE_SIGNING_ALLOWED=NO
git add TranStudy/System/AccessibilitySelectionProvider.swift \
  TranStudyTests/SelectionSentenceContextTests.swift \
  TranStudyTests/ApplicationShellTests.swift
git commit -m "fix(selection): fall back to sentence context"
```

Expected: focused tests pass and the optional capture compiles.

### Task 3: Validate responses against the sentence fallback

**Files:**
- Modify: `TranStudy/Translation/OpenAIChatTranslationClient.swift:181-214`
- Test: `TranStudyTests/OpenAICompatibleTranslationProviderTests.swift:145-185`

**Interfaces:**
- Consumes: `TranslationRequest.targetSentence`, `.sourceText`, and optional `.selectionWordContext`.
- Produces: Strict word-window validation or sentence-hint fallback validation.

- [ ] **Step 1: Add fallback response cases to the existing provider test**

The existing fixture returns `She ran home.`. Add:

```swift
let sentenceFallbackResult = try await provider.translate(
  TranslationRequest(
    sourceText: "ran",
    context: "Target sentence:\nShe ran home.",
    kind: .contextualSelection,
    targetSentence: "She ran home."
  ))
#expect(sentenceFallbackResult.exampleSentence == "She ran home.")

let completedHintResult = try await provider.translate(
  TranslationRequest(
    sourceText: "ran",
    context: "Target sentence:\nran",
    kind: .contextualSelection,
    targetSentence: "ran"
  ))
#expect(completedHintResult.exampleSentence == "She ran home.")

await #expect(throws: TranslationError.invalidResponse(.invalidEnglishContent)) {
  try await provider.translate(
    TranslationRequest(
      sourceText: "ran",
      context: "Target sentence:\nThey ran away.",
      kind: .contextualSelection,
      targetSentence: "They ran away."
    ))
}
```

Add a second response fixture whose example matches the target hint but omits
the selected source text:

```swift
let missingSelectionContent = try JSONSerialization.data(
  withJSONObject: [
    "input_kind": "word_or_phrase",
    "source_text": "ran",
    "canonical_form": "run",
    "pronunciation": "/ræn/",
    "part_of_speech": "verb",
    "contextual_meaning": "奔跑",
    "example_sentence": "She hurried home.",
    "sentence_translation": "她匆忙回家了。",
  ]
)
let missingSelectionBody = try JSONSerialization.data(
  withJSONObject: [
    "choices": [
      [
        "message": [
          "content": try #require(
            String(data: missingSelectionContent, encoding: .utf8)
          )
        ]
      ]
    ]
  ]
)
let missingSelectionProvider = OpenAICompatibleTranslationProvider(
  configuration: configuration,
  apiKeyStore: CustomProviderTestAPIKeyStore(apiKey: "custom-api-key"),
  httpClient: CustomProviderTestHTTPClient(
    data: missingSelectionBody,
    statusCode: 200
  )
)

await #expect(throws: TranslationError.invalidResponse(.invalidEnglishContent)) {
  try await missingSelectionProvider.translate(
    TranslationRequest(
      sourceText: "ran",
      context: "Target sentence:\nShe hurried home.",
      kind: .contextualSelection,
      targetSentence: "She hurried home."
    ))
}
```

- [ ] **Step 2: Run the test to verify RED**

```bash
xcodebuild test -project TranStudy.xcodeproj -scheme TranStudy \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/TranStudyIssue18Run \
  -disableAutomaticPackageResolution \
  -only-testing:TranStudyTests/OpenAICompatibleTranslationProviderTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: both rejection expectations fail because validation is currently
skipped without a word context.

- [ ] **Step 3: Implement sentence-fallback validation**

Append after the existing strict word-context branch:

```swift
else if request.kind == .contextualSelection,
  let targetSentence = request.targetSentence
{
  let normalizedTargetSentence = Self.normalizedEnglishIdentity(targetSentence)
  let normalizedSelectedText = Self.normalizedEnglishIdentity(request.sourceText)
  let normalizedExampleSentence = Self.normalizedEnglishIdentity(exampleSentence)
  let exampleContainsSelection = normalizedExampleSentence.contains(normalizedSelectedText)
  let exampleMatchesTargetHint =
    normalizedExampleSentence.contains(normalizedTargetSentence)
    || normalizedTargetSentence.contains(normalizedExampleSentence)
  guard exampleContainsSelection, exampleMatchesTargetHint else {
    throw Self.invalidWordResponse(
      .invalidEnglishContent,
      check: "exampleSentenceDoesNotMatchSentenceFallback",
      content: content,
      request: request
    )
  }
}
```

- [ ] **Step 4: Run provider tests and commit**

```bash
xcodebuild test -project TranStudy.xcodeproj -scheme TranStudy \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/TranStudyIssue18Run \
  -disableAutomaticPackageResolution \
  -only-testing:TranStudyTests/OpenAICompatibleTranslationProviderTests \
  -only-testing:TranStudyTests/DeepSeekTranslationProviderTests \
  CODE_SIGNING_ALLOWED=NO
git add TranStudy/Translation/OpenAIChatTranslationClient.swift \
  TranStudyTests/OpenAICompatibleTranslationProviderTests.swift
git commit -m "fix(translation): validate sentence fallback"
```

Expected: both provider suites pass.

### Task 4: Verify artifacts and reproduce Issue 18

**Files:**
- Verify: `TranStudy.xcodeproj`
- Verify: `/tmp/TranStudyIssue18Run/Build/Products/Debug/TranStudy.app`
- Verify: `/Users/jfs/Library/Logs/TranStudy/issue-18-debug.log`

**Interfaces:**
- Consumes: Tasks 1-3 and the stable `TranStudy Debug` signing identity.
- Produces: Tested Debug and Release artifacts plus a signed Debug app for manual reproduction.

- [ ] **Step 1: Run all focused suites**

```bash
xcodebuild test -project TranStudy.xcodeproj -scheme TranStudy \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/TranStudyIssue18Run \
  -disableAutomaticPackageResolution \
  -only-testing:TranStudyTests/SelectionSentenceContextTests \
  -only-testing:TranStudyTests/ApplicationShellTests \
  -only-testing:TranStudyTests/OpenAICompatibleTranslationProviderTests \
  -only-testing:TranStudyTests/DeepSeekTranslationProviderTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: all selected suites pass.

- [ ] **Step 2: Build Debug and Release**

```bash
xcodebuild clean build -project TranStudy.xcodeproj -scheme TranStudy \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/TranStudyIssue18Run \
  -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO
xcodebuild build -project TranStudy.xcodeproj -scheme TranStudy \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath /tmp/TranStudyIssue18Run \
  -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO
```

Expected: both builds print `BUILD SUCCEEDED`.

- [ ] **Step 3: Verify Release excludes Debug diagnostics**

```bash
strings /tmp/TranStudyIssue18Run/Build/Products/Release/TranStudy.app/Contents/MacOS/TranStudy \
  | rg 'DEBUG-issue18|issue-18-debug\.log|validation\.normalized_context'
```

Expected: no matches.

- [ ] **Step 4: Sign, launch, and reproduce**

Sign the Debug app with the existing stable `TranStudy Debug` identity and its current designated requirement, then run:

```bash
open -n /tmp/TranStudyIssue18Run/Build/Products/Debug/TranStudy.app
```

Select `where` and `where you` in the original Zen Browser sentence. Both should translate, and this command should show no new context-mismatch record:

```bash
tail -n 120 /Users/jfs/Library/Logs/TranStudy/issue-18-debug.log
```

- [ ] **Step 5: Final repository checks**

```bash
git diff --check
git status --short --branch
git log -6 --oneline
```

Expected: no whitespace errors and only intentional changes remain.
