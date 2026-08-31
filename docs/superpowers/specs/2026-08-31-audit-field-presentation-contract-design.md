# Audit Field Presentation Contract

## Context

The client-card history and Analytics journal already share
`AuditPresentationService`, but field presentation still has several competing
sources of truth. Default CRM fields have Russian labels in
`SettingsService`, the legacy timeline has a second partial label map in
`crm-mappers.ts`, and the shared presenter has a third smaller map. Unknown
keys fall back to English humanization, while structured values may reach the
UI as JSON. Some references, such as `assigned_to`, `closedBy`, and
`transitionFingerprint`, can expose UUIDs or hashes.

The current keyspace is deliberately open. Leads, students, and teachers can
retain HolliHop compatibility keys, and configured CRM fields may introduce
new Latin identifiers. Therefore an exhaustive hard-coded translation map
cannot be the contract.

Values such as `DRUMS`, `GUITAR`, `PIANO`, `VOCAL`, and any future value entered
by a director are business data, not enum codes owned by the application.
Their spelling and case must remain unchanged in audit history.

## Decision

Keep one audit pipeline and improve its existing write and presentation
boundaries. Do not add another event store, journal endpoint, Flutter
formatter, compatibility presenter, or parallel CRM field model.

1. Extract the existing default CRM field definitions from
   `SettingsService` into a pure catalog consumed by both settings and audit
   presentation. The settings API remains unchanged.
2. Add one audit-field presentation policy beside
   `AuditPresentationService`. It owns canonical aliases, technical-field
   suppression, structural value formatting, and the safe unknown-field
   fallback. The duplicate audit label map in `crm-mappers.ts` is removed.
3. Extend audit change metadata with optional immutable presentation hints:
   Russian label, semantic value type, and display mode. Producers use the
   authoritative field definition available during the mutation. Old events
   without hints continue through the catalog and safe fallback.
4. Typed client custom-field mutations calculate their before/after changes
   inside the existing transaction and return safe presentation snapshots to
   the existing lead/student audit producer. Labels remain historically stable
   if a director later renames or archives the field.

No database migration is required because audit metadata is JSONB and the new
properties are optional.

## Presentation rules

The formatter applies rules to structure, never to director-owned business
text.

- Scalar text and configured select values are preserved byte-for-byte after
  the existing redaction boundary. No dictionary translates `DRUMS`,
  `GUITAR`, `PIANO`, `VOCAL`, `kids`, or any other configured value.
- Known date values are displayed as `ДД.ММ.ГГГГ`; known date-time values as
  `ДД.ММ.ГГГГ ЧЧ:ММ`. Invalid or ambiguous text is preserved rather than
  guessed.
- Booleans are `Да` / `Нет`. Primitive lists are joined with `, ` while
  preserving every item. Empty lists become `Не указано` through the existing
  card contract.
- Structured contact values are summarized without raw JSON or contact PII,
  for example `Контактных лиц: 1 → 2`.
- Business references use a stored display name when the producer has one.
  Otherwise the event states that the field changed without showing an ID.
- A changed-only fact keeps `before` and `after` empty in the compatible
  response contract; the shared Flutter card renders one `Изменено` line
  instead of two misleading `Не указано` lines.
- UUIDs, hashes, fingerprints, version counters, session identifiers, and
  other technical-only fields never enter `AuditPresentationChange`.
- A configured field uses its stored label snapshot. A known legacy field uses
  the shared catalog or alias map. Any remaining custom key is displayed as
  `Дополнительное поле`; its Latin identifier and raw JSON are not shown.

The same output continues to feed both the client-card history and Analytics
journal. Flutter performs no secondary key/value localization; it only applies
the shared compact layout for changed-only facts.

## Data flow

For new events:

1. The existing command validates and performs the mutation.
2. The mutation layer produces semantic field changes from the same
   before/after state used by the transaction.
3. Each change carries a safe value plus optional `label`, `valueType`, and
   `displayMode` snapshot. Raw structured contact data and technical IDs are
   not copied into presentation metadata.
4. `AuditService` keeps its existing redaction and append-only insert.
5. `AuditPresentationService` applies the shared policy and returns the same
   `AuditPresentationEvent` contract to both consumers.

For historical events, step 3 is absent. The presenter resolves known aliases,
formats safe structures, and fails closed for unknown objects or technical
identifiers. Existing audit rows are not rewritten or deleted.

## Compatibility and failure handling

- Existing action keys, entity keys, routes, pagination, filters, and Flutter
  card JSON remain compatible.
- New metadata hints are optional and ignored by older code paths.
- A malformed list or object is never returned as raw JSON; the change becomes
  a neutral changed-only fact.
- A malformed presentation hint is ignored in favor of the trusted catalog or
  safe fallback.
- User-entered labels and values pass through the existing sensitive-data
  redaction before persistence and through display sanitization before output.
- Audit/outbox transactionality, expected versions, idempotency, append-only
  history, and RBAC are unchanged.

## Verification and acceptance

Use red-green TDD against the real shared presenter and real producer helpers.

- Table-driven tests cover every standard CRM key, every confirmed legacy
  alias, all core snake-case audit fields, and representative unknown keys.
- Contract tests prove arbitrary director values are preserved exactly,
  including `DRUMS`, `GUITAR`, `PIANO`, `VOCAL`, mixed case, Cyrillic, and a
  previously unseen value.
- Security regressions prove UUIDs, hashes, fingerprints, sessions, and raw
  `contactPersons` JSON cannot appear in either consumer payload.
- Type-format tests cover dates, date-times, booleans, primitive lists, empty
  lists, malformed JSON, object arrays, and redaction markers.
- Producer tests cover lead/student core updates and typed custom-field
  changes with stable label snapshots.
- The production audit inventory continues to require explicit Russian titles
  and entity labels for all statically known business producers.
- Focused audit, dashboard, client-context, CRM mapper, settings, validator,
  and mutation tests pass, followed by server typecheck, build, security gate,
  and the full backend suite.

## Rollout and rollback

Land the catalog extraction, safe presentation policy, producer snapshots, and
consumer regression coverage as independently reviewable commits where
practical. Release through the existing backend/application process; no data
backfill is required.

Rollback reverts the code commits in reverse order. Because metadata additions
are optional JSON properties and historical rows are untouched, rollback does
not require a database restore or audit-history rewrite.
