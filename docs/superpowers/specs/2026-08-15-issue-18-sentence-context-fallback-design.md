# Issue 18 Sentence Context Fallback Design

## Goal

Make contextual word and phrase translation fall back to the captured sentence
context when an application's Accessibility adapter can read the selection but
cannot expand it to the surrounding word window.

The fix must make one- and two-word selections in Zen Browser translate without
weakening the normal validation path used when a complete word window is
available.

## Root Cause

`AccessibilitySelectionProvider.webWordContext` starts its context boundaries
at the selected range. Zen Browser returns no advancing marker for the previous
word start and next word end parameterized attributes. The loops stop, but the
adapter still returns a `SelectionWordContext` whose preceding and following
text are both empty.

That structurally non-optional but semantically incomplete value prevents both
existing fallbacks:

1. `selectionContext(in:)` treats the web text-marker capture as successful and
   does not try the AX range/document-text adapter.
2. `SelectionSnapshot.translationContext` prefers any non-`nil` word context
   over the independently captured sentence context.

The model receives the full sentence as a hint and returns it correctly. The
response validator then rejects that sentence because it cannot be contained
inside the incomplete word context, which contains only the selected text.

## Scope

This change fixes only the missing-context fallback and its response
validation. It does not change the word-or-phrase versus long-text classifier.
In particular, the separate classification of `where you got` as long text is
out of scope.

The existing Debug-only Issue 18 text log remains available for manual
verification.

## Design

### Represent unavailable word context explicitly

`SelectionContextCapture.wordContext` becomes optional. A
`SelectionWordContext` is usable as a surrounding word window only when at
least one of `precedingText` or `followingText` contains a non-whitespace
character.

An empty side remains valid at the start or end of a document. Both sides empty
means the adapter captured only the selection and therefore did not provide a
surrounding word window.

### Capture the two context forms independently

`webSelectionContext` captures the word-window candidate and sentence context
independently instead of requiring the word window before attempting sentence
capture.

- A usable word window and sentence context are both retained.
- A selection-only word-window candidate is represented as `nil`, while a
  successfully captured sentence context is retained.
- A usable word window may still support translation if sentence capture is
  unavailable.
- If neither context form is available, selection-context capture fails.

The AX range/document-text adapter applies the same usability rule before
publishing its extracted word context. All adapters therefore maintain the
invariant that a non-`nil` word context contains actual surrounding content.

### Keep prompt and validation inputs consistent

`SelectionSnapshot` publishes the sanitized optional word context. Existing
callers then behave consistently:

- `translationContext` uses `wordContext.promptText` when the word window is
  usable.
- Otherwise it constructs context from the previous, target, and next sentence.
- `ApplicationShell` passes the same optional value as
  `TranslationRequest.selectionWordContext`.

The prompt can therefore never use sentence fallback while response validation
still receives a selection-only word context.

### Validate the sentence fallback

The current strict word-window validation remains unchanged when
`selectionWordContext` is present:

1. The normalized word window must contain the normalized model example.
2. The normalized model example must contain the normalized selected text.

When the word window is absent and `targetSentence` is available, the fallback
validation requires:

1. The normalized model example contains the normalized requested source text.
2. The normalized model example contains the normalized target-sentence hint,
   or the normalized target-sentence hint contains the normalized model
   example.

The bidirectional containment rule permits a locally detected sentence hint to
be incomplete at inline formatting boundaries while still rejecting an
unrelated model-generated sentence.

If neither a usable word window nor sentence context exists, the selection
snapshot remains incomplete and translation does not start.

## Error Handling

Accessibility capability gaps remain normal adapter outcomes, not user-visible
errors. Returning `nil` for an unavailable word window triggers the sentence
fallback. File logging remains best-effort and must not change translation
behavior.

An unrelated example in sentence-fallback mode continues to produce
`TranslationError.invalidResponse(.invalidEnglishContent)`.

## Testing

Implementation follows a red-green-refactor cycle with focused tests for:

1. A word context with both surrounding sides empty is unusable.
2. A document-start or document-end word context with one populated side stays
   usable.
3. A selection snapshot with no usable word window constructs its prompt from
   sentence context and passes `selectionWordContext == nil`.
4. Sentence-fallback validation accepts a correct complete example sentence.
5. Sentence-fallback validation accepts an example that completes an
   incomplete target-sentence hint.
6. Sentence-fallback validation rejects an example that omits the selected
   source text or is unrelated to the target-sentence hint.
7. Existing strict word-window validation remains unchanged.
8. Existing word-window extraction limits and formatting-boundary behavior
   remain unchanged.

Manual verification uses the signed Debug app in Zen Browser and confirms that
one- and two-word selections no longer append
`exampleSentenceDoesNotMatchSelectionContext` records to the Issue 18 log.

## Success Criteria

- Zen Browser selections whose word markers cannot expand use sentence context.
- Correct model responses for those selections are accepted.
- Unrelated example sentences remain rejected.
- Applications that provide a complete word window retain the strict existing
  behavior.
- Long-text classification behavior is unchanged.
- Debug and Release configurations compile, focused tests pass, and Release
  artifacts contain no Issue 18 Debug log strings.
