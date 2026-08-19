# Issue 18 Debug Response Logging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore a Debug-only text log for invalid word responses so Issue #18 reproduction captures the failing validation check and model content.

**Architecture:** Keep response validation and public errors unchanged inside `OpenAIChatTranslationClient`. Add a small Debug-only file logger that appends records to `~/Library/Logs/TranStudy/issue-18-debug.log`; inject a temporary destination in tests, and compile the entire path out of Release builds.

**Tech Stack:** Swift 6, Swift Testing, Xcode Debug/Release configurations

## Global Constraints

- Trigger response-file logging only at
  `OpenAIChatTranslationClient.invalidWordResponse`.
- Prefix every diagnostic record with `[DEBUG-issue18]`.
- Never log the API key, Authorization header, or complete `URLRequest`.
- Do not write raw response content into `FileDiagnosticLogStore`.
- Preserve the existing `TranslationError` returned to callers.
- Create the text log with `0600` permissions and cap it at 1 MB.
- Ignore file-system errors so debug logging cannot break translation.

---

### Task 1: Restore invalid-response debug record formatting

**Files:**
- Modify: `TranStudyTests/DeepSeekTranslationProviderTests.swift`
- Modify: `TranStudy/Translation/OpenAIChatTranslationClient.swift:439-446`

**Interfaces:**
- Consumes: Existing `DeepSeekTranslationProvider.translate(_:)` invalid-English response path.
- Produces: Debug-only diagnostic records from `invalidWordResponse`.

- [x] **Step 1: Write the failing test**

Add a Debug-only test that submits a response whose `canonical_form` is Chinese
and asserts that the diagnostic record contains the failure type,
`invalidEnglishFields`, source text, and raw response content. Also assert that
the provider still throws
`TranslationError.invalidResponse(.invalidEnglishContent)`.

- [x] **Step 2: Run the focused test to verify it fails**

Run:

```bash
xcodebuild test -project TranStudy.xcodeproj -scheme TranStudy -destination 'platform=macOS' -only-testing:TranStudyTests/DeepSeekTranslationProviderTests
```

Expected: FAIL because the invalid-response path emits no diagnostic record.

- [x] **Step 3: Implement the minimal Debug-only logging**

Inside `OpenAIChatTranslationClient`, restore named `check`, `content`, and
`request` parameters in `invalidWordResponse`, then format the failure, source
text, optional target sentence, and response content before returning the
unchanged error.

- [x] **Step 4: Run focused and full verification**

Run the focused test command again, then:

```bash
xcodebuild test -project TranStudy.xcodeproj -scheme TranStudy -destination 'platform=macOS'
xcodebuild build -project TranStudy.xcodeproj -scheme TranStudy -configuration Release -destination 'platform=macOS'
git diff --check
```

Expected: focused tests PASS, Release build succeeds without Debug-only logging,
and diff check is clean. Record unrelated pre-existing failures if the full
suite is also run.

- [x] **Step 5: Commit**

```bash
git add TranStudy/Translation/OpenAIChatTranslationClient.swift TranStudyTests/DeepSeekTranslationProviderTests.swift docs/superpowers/plans/2026-08-15-issue-18-debug-response-logging.md
git commit -m "chore(translation): log invalid responses"
```

### Task 2: Persist records in a bounded private text file

**Files:**
- Modify: `TranStudyTests/DeepSeekTranslationProviderTests.swift`
- Modify: `TranStudy/Translation/OpenAIChatTranslationClient.swift`

**Interfaces:**
- Consumes: The existing `invalidWordResponse` diagnostic fields.
- Produces: Debug-only `Issue18DebugFileLogger` and
  `~/Library/Logs/TranStudy/issue-18-debug.log`.

- [x] **Step 1: Write and run a failing persistence test**

Replace the captured console closure in the existing test with a logger pointed
at a unique temporary file. Assert the file contains a timestamp, failure,
check, source text, and raw response. Run the focused provider tests and confirm
the test fails because the file logger does not exist.

- [x] **Step 2: Implement append-only file output**

Add `Issue18DebugFileLogger` behind `#if DEBUG`, create its parent directory,
append UTF-8 records, and ignore write errors. Format the response as one record
whose lines use the `[DEBUG-issue18]` prefix.

- [x] **Step 3: Add and satisfy the size-bound test**

Seed the temporary log to its configured limit, trigger another invalid
response, and assert the old bytes are replaced by the new record and the file
does not exceed the limit. Implement replacement before an overflowing append.

- [x] **Step 4: Add and satisfy the permissions test**

Assert the resulting file's POSIX permissions are `0600`, then explicitly set
those permissions after every create or append operation.

- [x] **Step 5: Verify Debug tests and the Release artifact**

Run focused provider/log-store tests, build Release, confirm the Release binary
does not contain `DEBUG-issue18` or `issue-18-debug.log`, and run
`git diff --check`.

- [x] **Step 6: Commit**

```bash
git add TranStudy/Translation/OpenAIChatTranslationClient.swift \
  TranStudyTests/DeepSeekTranslationProviderTests.swift \
  docs/superpowers/specs/2026-08-15-issue-18-debug-response-logging-design.md \
  docs/superpowers/plans/2026-08-15-issue-18-debug-response-logging.md
git commit -m "chore(translation): write debug response log"
```
