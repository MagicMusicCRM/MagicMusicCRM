# Client Card Editors Semantic Split

## Context

`client_card_editors.dart` is the highest-ranked production file after the
lesson-settlement package: RepoWise health `1.41`, `1,376` NLOC, max CCN `24`,
weighted deficit `9,068`, 46.93% line coverage, five bug fixes in six months,
and co-change with 30 files. It has one library owner (`client_card.dart`) but
mixes custom-field rendering, moderation, contact data, staff assignment,
comments, family membership, and app access in one extension.

The literal dashboard directive is a large integration test whose primary
signal is historical co-change scatter. The approved production-first policy
therefore selects this file without removing `LeadsService`, `CrmService`, or
the remaining god files from the mandatory cleanup queue.

## Decision

Delete the generic editor part and replace it with seven semantic extension
parts in the existing `client_card.dart` library:

- `client_card_custom_fields.dart` owns configured field layout, aliases,
  read-only policy, and type dispatch.
- `client_card_custom_field_inputs.dart` owns typed input controls, date
  controls, value normalization, and age behavior.
- `client_card_moderation.dart` owns blacklist presentation, reason capture,
  and immediate mutation.
- `client_card_contact_editors.dart` owns disciplines and contact persons.
- `client_card_assignment_editors.dart` owns branch, source, and responsible
  staff selection.
- `client_card_comment_editor.dart` owns comment input, aggregation, target
  selection, and refresh behavior.
- `client_card_family_access.dart` owns family membership, primary payer,
  linked-record navigation, account linking, and invitations.

No compatibility part, forwarding extension, public API, provider, route,
payload, or state field is added. All parts continue extending
`_ClientCardState`, so the split changes ownership without duplicating state.

## Complexity cuts

After the ownership split, decompose the methods that still exceed CCN `10`:

1. Dispatch custom-field types to narrow selection, boolean, multi-select,
   date, and text builders; isolate read-only formatting.
2. Separate blacklist target mutation from orchestration and feedback.
3. Separate family validation/creation from the add-member UI orchestration.
4. Resolve comment target and kind through typed, pure value helpers.

The helpers must expose domain intent rather than generic `helper`, `utils`,
`common`, version labels, or numbered filenames.

## Preserved invariants

- Text fields keep epoch-based identity; typing must not recreate a controller,
  drop focus, reset the cursor, or break IME composition.
- Custom fields preserve schema placement, required labels, canonical typed
  values, definition IDs, legacy read aliases, and configured widths.
- Lead responsible assignment remains canonical `assignedTo`; explicit clear
  keeps the current clear flags without legacy custom-data duplicates.
- Blacklisting asks for an optional reason, cancels on dialog cancellation,
  updates every present lead/student half immediately, then reloads history.
- Teachers can only write `teacher_note`; staff selection and Russian feedback
  remain unchanged, and converted clients still target the student half.
- Family membership, primary contact/payer, entity navigation, user linking,
  and invitations retain their current service calls and busy-state cleanup.
- UI remains Russian and uses the existing Deep Charcoal & Sophisticated Gold
  tokens and widget keys.

## Verification and acceptance

Add a structural test that requires all seven semantic parts and rejects the old
generic owner before moving code. Keep the focused client-card widget suite as
the behavior characterization gate.

- `client_card_editors.dart` is deleted with no compatibility reference.
- Every replacement production file has RepoWise health at least `7.0`, at most
  `500` NLOC, max CCN at most `10`, and no god/brain finding.
- Combined replacement weighted deficit is at most `1,814`, an 80% reduction
  from the `9,068` baseline.
- Focused client-card tests, full `flutter test`, `flutter analyze`, formatting,
  and `git diff --check` pass.
- Sentrux remains at quality `>=5732`, acyclicity `10000`, depth `<=13`, and
  both architecture rules pass after every structural commit.
- RepoWise is exact at implementation HEAD with no broken consumer, new cycle,
  missing-test warning, or unexplained change-risk finding.

## Rollback

Land the structural ownership split and each complexity family as separate
commits. Revert them in reverse order. No backend, database, migration,
environment, production-state, or data-repair rollback is required.

## Verified outcome

The split is implemented at `d6da59b19396` as five independently revertible
implementation commits. The generic `client_card_editors.dart` owner is deleted
without a compatibility part, and the live library now composes the seven
semantic owners specified above.

- RepoWise is exact with `index_behind=false`. Replacement health ranges from
  `8.80` to `10.00`, max CCN is `10`, max NLOC is `274`, no god/brain finding
  remains, and combined weighted deficit is `0` versus the `9,068` baseline.
- The full Flutter gate passes `999/999`; `flutter analyze` reports zero issues,
  `git diff --check` is clean, and the working tree is clean.
- Change risk is `Elevated` at percentile `96.4` because the semantic move
  spans 11 Dart files and `3,154` changed lines. RepoWise reports 12 impacted
  tests and no `untested_changes`; the full suite covers the new part files for
  which line-level attribution has not yet been ingested.
- Sentrux closes at quality `5730`, acyclicity `10000` with raw `0`, depth `13`,
  equality `6228`, modularity `5360`, redundancy `4857`, and both rules passing.
  The package-local quality floor misses by two points because seven direct
  semantic owners reduce the redundancy subscore by 13 points. This measured
  variance is retained instead of recombining responsibilities to optimize the
  graph score; the program baseline remains improved by `756` points.
