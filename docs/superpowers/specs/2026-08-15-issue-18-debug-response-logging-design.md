# Issue 18 Debug Response Logging Design

## Goal

Restore the repository's former Debug-only logging at the word-response
validation boundary so an intermittent Issue #18 failure records the exact
validation check and model content needed for root-cause analysis.

## Scope

- Change only `OpenAIChatTranslationClient.invalidWordResponse`.
- Retain the existing `[DEBUG-issue18]`-style unique prefix on every line.
- Log the validation failure, internal validation check, requested source text,
  optional target sentence, and `choices[0].message.content`.
- Compile all logging behind `#if DEBUG`.
- Keep Release behavior and the persistent diagnostic archive unchanged.
- Never log the API key, Authorization header, or complete `URLRequest`.

## Data Flow

When a decoded word response fails validation, each existing guard calls
`invalidWordResponse`. A Debug build writes the bounded debugging record to the
process console and then returns the same `TranslationError` as before. A
Release build compiles out the logging and only returns the error.

## Verification

- A focused test exercises an invalid English response and confirms the same
  public error classification remains intact.
- The Debug build compiles with the restored parameter bindings and logging.
- The Release build compiles without relying on Debug-only values.
- Existing provider tests continue to pass.

## Cleanup

After Issue #18 has been reproduced and the root cause is captured, remove all
lines tagged `[DEBUG-issue18]` so selected text and model content do not remain
in routine development logs.
