# Issue 18 Debug Response Logging Design

## Goal

Restore the repository's former Debug-only logging at the word-response
validation boundary so an intermittent Issue #18 failure records the exact
validation check and model content needed for root-cause analysis.

## Scope

- Trigger response-file logging only from
  `OpenAIChatTranslationClient.invalidWordResponse`.
- Retain the existing `[DEBUG-issue18]`-style unique prefix on every line.
- Log the validation failure, internal validation check, requested source text,
  optional target sentence, and `choices[0].message.content`.
- Compile all logging behind `#if DEBUG`.
- Keep Release behavior and the persistent diagnostic archive unchanged.
- Never log the API key, Authorization header, or complete `URLRequest`.

## Data Flow

When a decoded word response fails validation, each existing guard calls
`invalidWordResponse`. A Debug build appends the bounded debugging record to
`~/Library/Logs/TranStudy/issue-18-debug.log` and then returns the same
`TranslationError` as before. The file is created with `0600` permissions and
is replaced with the newest record before an append would grow it beyond 1 MB.
File-system failures are ignored so diagnostics cannot change translation
behavior. A Release build compiles out the logging and only returns the error.

## Verification

- A focused test exercises an invalid English response and confirms the same
  public error classification remains intact.
- A focused test confirms the Debug log contains a timestamp, the failing
  validation check, request context, and raw model response.
- Tests confirm the file is private (`0600`) and bounded to 1 MB.
- The Release build compiles without relying on Debug-only values.
- Existing provider tests continue to pass.

## Cleanup

After Issue #18 has been reproduced and the root cause is captured, remove all
lines tagged `[DEBUG-issue18]` and remove
`~/Library/Logs/TranStudy/issue-18-debug.log` so selected text and model content
do not remain on the development machine.
