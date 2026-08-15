# Issue 18 Debug Response Logging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore Debug-only console output for invalid word responses so Issue #18 reproduction captures the failing validation check and model content.

**Architecture:** Keep response validation and public errors unchanged inside `OpenAIChatTranslationClient`. Add an internal Debug-only output closure for deterministic testing, and call it only from `invalidWordResponse`; Release builds compile the output path away.

**Tech Stack:** Swift 6, Swift Testing, Xcode Debug/Release configurations

## Global Constraints

- Change response logging only at `OpenAIChatTranslationClient.invalidWordResponse`.
- Prefix every diagnostic record with `[DEBUG-issue18]`.
- Never log the API key, Authorization header, or complete `URLRequest`.
- Do not write raw response content into `FileDiagnosticLogStore`.
- Preserve the existing `TranslationError` returned to callers.

---

### Task 1: Restore invalid-response debug output

**Files:**
- Modify: `TranStudyTests/DeepSeekTranslationProviderTests.swift`
- Modify: `TranStudy/Translation/OpenAIChatTranslationClient.swift:439-446`

**Interfaces:**
- Consumes: Existing `DeepSeekTranslationProvider.translate(_:)` invalid-English response path.
- Produces: Debug-only `OpenAIChatTranslationClient.issue18DebugOutput` closure and console records from `invalidWordResponse`.

- [x] **Step 1: Write the failing test**

Add a Debug-only test that installs a capturing closure, submits a response whose
`canonical_form` is Chinese, and asserts that output contains the failure type,
`invalidEnglishFields`, source text, and raw response content. Also assert that
the provider still throws `TranslationError.invalidResponse(.invalidEnglishContent)`.

- [x] **Step 2: Run the focused test to verify it fails**

Run:

```bash
xcodebuild test -project TranStudy.xcodeproj -scheme TranStudy -destination 'platform=macOS' -only-testing:TranStudyTests/DeepSeekTranslationProviderTests
```

Expected: FAIL because `issue18DebugOutput` does not exist and the invalid
response path emits no output.

- [x] **Step 3: Implement the minimal Debug-only logging**

Inside `OpenAIChatTranslationClient`, add a Debug-only output closure defaulting
to `print`. Restore named `check`, `content`, and `request` parameters in
`invalidWordResponse`, then emit the failure, source text, optional target
sentence, and response content before returning the unchanged error.

- [x] **Step 4: Run focused and full verification**

Run the focused test command again, then:

```bash
xcodebuild test -project TranStudy.xcodeproj -scheme TranStudy -destination 'platform=macOS'
xcodebuild build -project TranStudy.xcodeproj -scheme TranStudy -configuration Release -destination 'platform=macOS'
git diff --check
```

Expected: focused and full tests PASS, Release build succeeds, and diff check is
clean.

- [ ] **Step 5: Commit**

```bash
git add TranStudy/Translation/OpenAIChatTranslationClient.swift TranStudyTests/DeepSeekTranslationProviderTests.swift docs/superpowers/plans/2026-08-15-issue-18-debug-response-logging.md
git commit -m "debug(translation): log invalid responses"
```
