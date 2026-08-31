# Audit Field Presentation Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every user-visible audit field readable and safe in Russian while preserving director-created reference values exactly as entered.

**Architecture:** Keep the existing append-only audit pipeline and shared `AuditPresentationService`. Extract the existing CRM field catalog, add one pure audit-field presentation policy, and attach optional immutable label/type/display snapshots to new audit changes; historical rows use the same catalog and fail-closed fallback.

**Tech Stack:** NestJS, TypeScript, PostgreSQL JSONB audit metadata, Jest, Flutter shared `AuditEventCard` consumers.

**Spec:** `docs/superpowers/specs/2026-08-31-audit-field-presentation-contract-design.md`

## Global Constraints

- Preserve `DRUMS`, `GUITAR`, `PIANO`, `VOCAL`, every Cyrillic value, mixed case, and every future director-created value exactly; do not translate or canonicalize business values.
- Keep one audit store, one shared backend presenter, and the current Flutter card contract.
- Do not rewrite or delete historical audit rows.
- Hide UUIDs, hashes, fingerprints, version counters, session identifiers, and raw structured contact data.
- Dates use `ДД.ММ.ГГГГ`; date-times use `ДД.ММ.ГГГГ ЧЧ:ММ`; booleans use `Да` / `Нет`; primitive lists join with `, `.
- Unknown custom keys use `Дополнительное поле`; never show a Latin key or raw JSON.
- Preserve audit/outbox transactionality, expected versions, idempotency, append-only facts, and backend RBAC.
- No production deploy is part of this implementation plan; release requires a separate direct owner command.

---

## File structure

- Create `server/src/settings/crm-custom-field-catalog.ts`: pure owner of the existing default CRM field definitions and lookup by entity/key.
- Create `server/src/settings/crm-custom-field-catalog.spec.ts`: catalog completeness, uniqueness, and Russian-label contract.
- Create `server/src/audit/audit-field-presentation.policy.ts`: field aliases, technical suppression, safe producer snapshots, and final formatting.
- Create `server/src/audit/audit-field-presentation.policy.spec.ts`: value-preservation, Russian formatting, structured-data, and technical-ID tests.
- Modify `server/src/settings/settings.service.ts`: consume the extracted catalog without changing the settings API.
- Modify `server/src/audit/audit-presentation.types.ts`: define optional presentation hint types while preserving response JSON.
- Modify `server/src/audit/audit-presentation.service.ts`: delegate every change to the shared policy and delete duplicate field/value formatting.
- Modify `server/src/audit/audit-presentation.service.spec.ts`: shared presenter and historical-event regression cases.
- Modify `server/src/crm/crm-mappers.ts`: produce safe semantic changes and remove its duplicate field-label map.
- Modify `server/src/crm/crm-mappers.spec.ts`: core/custom/structured/technical producer tests.
- Modify typed custom-field validation and persistence files so label/type snapshots and before/after values travel through the existing transaction.
- Modify lead/student command tests to prove typed and legacy changes share one audit metadata array.
- Modify the small set of platform producers with asymmetric or technical refs, plus their focused tests.

---

### Task 1: Extract the authoritative CRM field catalog

**Files:**
- Create: `server/src/settings/crm-custom-field-catalog.ts`
- Create: `server/src/settings/crm-custom-field-catalog.spec.ts`
- Modify: `server/src/settings/settings.service.ts:32-582`
- Test: `server/src/settings/settings.service.spec.ts`

**Interfaces:**
- Produces: `CrmCustomFieldDefinition`, `DEFAULT_CRM_CUSTOM_FIELDS`, and `findDefaultCrmField(key: string, entity?: "students" | "leads" | "teachers"): CrmCustomFieldDefinition | null`.
- Consumes: `CRM_CUSTOM_FIELD_ENTITIES`, `CRM_CUSTOM_FIELD_TYPES`, and `CrmCustomFieldDefinitionDto` from the existing DTO module.

- [ ] **Step 1: Write the failing catalog contract test**

```ts
import {
  DEFAULT_CRM_CUSTOM_FIELDS,
  findDefaultCrmField,
} from './crm-custom-field-catalog';

describe('CRM custom field catalog', () => {
  it('owns unique Russian labels for the current standard fields', () => {
    const identities = DEFAULT_CRM_CUSTOM_FIELDS.map(
      (field) => `${field.entity}:${field.key}`,
    );
    expect(new Set(identities).size).toBe(identities.length);
    expect(findDefaultCrmField('birthday', 'students')?.label)
      .toBe('Дата рождения');
    expect(findDefaultCrmField('discipline', 'leads')?.label)
      .toBe('Интересующее направление');
    expect(findDefaultCrmField('additionalParams', 'teachers')?.label)
      .toBe('Дополнительные параметры');
  });
});
```

- [ ] **Step 2: Run the test and verify RED**

Run: `npm --prefix server test -- --runInBand src/settings/crm-custom-field-catalog.spec.ts`

Expected: FAIL because `crm-custom-field-catalog.ts` does not exist.

- [ ] **Step 3: Move, do not copy, the existing catalog**

Move `CrmCustomFieldDefinition`, the HolliHop option constants,
`LEGACY_DEFAULT_CRM_CUSTOM_FIELDS`, `REJECTED_CRM_CUSTOM_FIELD_KEYS`, and
`DEFAULT_CRM_CUSTOM_FIELDS` from `settings.service.ts` into the new pure file.
Export only the public type, final catalog, and lookup function. Keep the
current filtering of `workplace`, `position`, `individualPrice`, and legacy
`source` fields exactly unchanged.

```ts
export function findDefaultCrmField(
  key: string,
  entity?: CrmCustomFieldDefinition['entity'],
): CrmCustomFieldDefinition | null {
  return DEFAULT_CRM_CUSTOM_FIELDS.find(
    (field) => field.key === key && (!entity || field.entity === entity),
  ) ?? null;
}
```

- [ ] **Step 4: Make `SettingsService` consume the catalog**

Import `CrmCustomFieldDefinition` and `DEFAULT_CRM_CUSTOM_FIELDS`; remove the
moved declarations. Do not change response shapes, normalization, snapshot
storage, or audit actions.

- [ ] **Step 5: Run catalog and settings tests**

Run: `npm --prefix server test -- --runInBand src/settings/crm-custom-field-catalog.spec.ts src/settings/settings.service.spec.ts`

Expected: both suites PASS with unchanged settings snapshots.

- [ ] **Step 6: Commit**

```bash
git add server/src/settings/crm-custom-field-catalog.ts server/src/settings/crm-custom-field-catalog.spec.ts server/src/settings/settings.service.ts
git commit -m "refactor(settings): share CRM field catalog"
```

---

### Task 2: Add the safe audit-field presentation policy

**Files:**
- Create: `server/src/audit/audit-field-presentation.policy.ts`
- Create: `server/src/audit/audit-field-presentation.policy.spec.ts`
- Modify: `server/src/audit/audit-presentation.types.ts`

**Interfaces:**
- Consumes: `findDefaultCrmField` from Task 1.
- Produces: `AuditFieldValueType`, `AuditChangeDisplayMode`, `AuditFieldChangeInput`, `createSafeAuditChange`, and `presentAuditFieldChange`.

- [ ] **Step 1: Define the failing value-preservation tests**

```ts
it.each(['DRUMS', 'GUITAR', 'PIANO', 'VOCAL', 'Авторское направление №1'])
('preserves director value %s exactly', (value) => {
  expect(presentAuditFieldChange({
    field: 'custom_data.discipline',
    from: null,
    to: value,
  })).toMatchObject({ label: 'Направление', before: null, after: value });
});

it('preserves a previously unseen configured value and mixed case', () => {
  const value = 'Neo Soul DrUmS';
  expect(presentAuditFieldChange({
    field: 'custom_data.discipline',
    from: null,
    to: value,
  })?.after).toBe(value);
});
```

- [ ] **Step 2: Add failing structural and security tests**

```ts
it.each([
  ['custom_data.birthday', '2000-02-01', '01.02.2000'],
  ['custom_data.visitDateTime', '2026-08-31T17:21:00+03:00', '31.08.2026 17:21'],
  ['custom_data.noEmail', true, 'Да'],
  ['custom_data.disciplines', '["DRUMS","Авторское"]', 'DRUMS, Авторское'],
])('formats %s structurally without translating content', (field, value, expected) => {
  expect(presentAuditFieldChange({ field, from: null, to: value })?.after)
    .toBe(expected);
});

it.each(['closedBy', 'transitionFingerprint', 'sessionId', 'payload_hash'])
('suppresses technical field %s', (field) => {
  expect(presentAuditFieldChange({ field, from: null, to: 'secret-id' }))
    .toBeNull();
});

it('summarizes contact people without raw PII or JSON', () => {
  const change = presentAuditFieldChange({
    field: 'custom_data.contactPersons',
    from: '[]',
    to: '[{"name":"Анна","phone":"+79991234567"}]',
  });
  expect(change).toMatchObject({
    label: 'Контактные лица',
    before: 'Контактных лиц: 0',
    after: 'Контактных лиц: 1',
  });
  expect(JSON.stringify(change)).not.toContain('+79991234567');
});
```

- [ ] **Step 3: Run the policy test and verify RED**

Run: `npm --prefix server test -- --runInBand src/audit/audit-field-presentation.policy.spec.ts`

Expected: FAIL because the policy module and exported types do not exist.

- [ ] **Step 4: Define optional metadata hints**

```ts
export type AuditFieldValueType =
  | 'text' | 'date' | 'datetime' | 'boolean' | 'list'
  | 'contact_list' | 'reference' | 'technical';

export type AuditChangeDisplayMode =
  | 'values' | 'changed_only' | 'count' | 'hidden';

export interface AuditFieldChangeInput {
  field: string;
  from: unknown;
  to: unknown;
  label?: string;
  valueType?: AuditFieldValueType;
  displayMode?: AuditChangeDisplayMode;
}
```

Keep `AuditPresentationChange` and `AuditPresentationEvent` response fields
unchanged.

- [ ] **Step 5: Implement field resolution and safe formatting**

Implement `createSafeAuditChange(input): AuditFieldChangeInput | null` for
producer-side storage and
`presentAuditFieldChange(input): AuditPresentationChange | null` for read-side
compatibility. Resolution order is: valid stored label/type/display snapshot,
core snake-case alias, shared default CRM catalog, confirmed legacy alias,
neutral custom fallback. Technical suppression runs before label fallback.

Director-owned scalar values must never pass through an enum translation map.
Only booleans and syntactically valid ISO dates/date-times receive localized
formatting. Primitive lists preserve item strings exactly. Object lists use a
field-specific safe count or `changed_only`; unsupported/malformed structures
never fall back to raw JSON.

- [ ] **Step 6: Run the policy suite and verify GREEN**

Run: `npm --prefix server test -- --runInBand src/audit/audit-field-presentation.policy.spec.ts`

Expected: all policy tests PASS.

- [ ] **Step 7: Commit**

```bash
git add server/src/audit/audit-field-presentation.policy.ts server/src/audit/audit-field-presentation.policy.spec.ts server/src/audit/audit-presentation.types.ts
git commit -m "feat(audit): add safe field presentation policy"
```

---

### Task 3: Route the shared presenter through the policy

**Files:**
- Modify: `server/src/audit/audit-presentation.service.ts:73-720`
- Modify: `server/src/audit/audit-presentation.service.spec.ts`
- Modify: `lib/shared/widgets/audit_event_card.dart`
- Test: `test/shared/widgets/audit_event_card_test.dart`
- Test: `server/src/audit/audit-presentation.coverage.spec.ts`
- Test: `server/src/crm/dashboard.service.spec.ts`
- Test: `server/src/crm/clients/client-internal-context.service.spec.ts`

**Interfaces:**
- Consumes: `presentAuditFieldChange` from Task 2.
- Produces: unchanged synchronous `AuditPresentationService.present(input): AuditPresentationEvent`.

- [ ] **Step 1: Add failing shared-consumer regressions**

Add table-driven cases for `first_name`, `last_name`, `notes`, `assigned_to`,
`birthday`, `category`, `levels`, `closedBy`, and an unknown custom key. Assert:

```ts
expect(service.present(assignedToInput).changes).toEqual([
  {
    key: 'assigned_to',
    label: 'Ответственный',
    before: null,
    after: null,
  },
]);
expect(JSON.stringify(service.present(closedByInput))).not.toContain(uuid);
expect(service.present(directorValueInput).changes[0].after).toBe('DRUMS');
```

Add one shared Flutter-card case for a changed-only reference:

```dart
expect(find.text('Ответственный'), findsOneWidget);
expect(find.text('Изменено'), findsOneWidget);
expect(find.textContaining('Было:'), findsNothing);
expect(find.textContaining('Стало:'), findsNothing);
```

- [ ] **Step 2: Run presenter tests and verify RED**

Run: `npm --prefix server test -- --runInBand src/audit/audit-presentation.service.spec.ts`

Run: `flutter test test/shared/widgets/audit_event_card_test.dart`

Expected: backend FAILS with English labels, raw UUID/JSON, or unformatted
structures; Flutter FAILS because the changed-only fact still shows two
`Не указано` lines.

- [ ] **Step 3: Replace local formatting with the shared policy**

Both `extractChanges` and `extractMetadataChanges` must construct an
`AuditFieldChangeInput`, call `presentAuditFieldChange`, and omit a `null`
result. Delete `FIELD_LABELS`, `CUSTOM_DATA_LIST_FIELDS`, `fieldLabel`,
`customDataField`, `safeListChangeValue`, and duplicate value formatting that
the policy now owns. Keep action-title/entity-title behavior unchanged.

For changed-only facts, retain a change with `before: null` and `after: null`;
update the shared `_AuditChangeRow` so this exact case renders a single
`Изменено` line. Keep the existing `Было` / `Стало` layout whenever either
safe value is present. This preserves the response JSON contract and changes
both the client-card history and Analytics journal through one widget.

- [ ] **Step 4: Run all shared-consumer tests**

Run:

`npm --prefix server test -- --runInBand --runTestsByPath src/audit/audit-field-presentation.policy.spec.ts src/audit/audit-presentation.service.spec.ts src/audit/audit-presentation.coverage.spec.ts src/crm/dashboard.service.spec.ts src/crm/clients/client-internal-context.service.spec.ts`

Run: `flutter test test/shared/widgets/audit_event_card_test.dart`

Expected: five backend suites and the shared Flutter widget suite PASS;
director values remain unchanged in both consumer payloads, and changed-only
facts contain no fake old/new values.

- [ ] **Step 5: Commit**

```bash
git add server/src/audit/audit-presentation.service.ts server/src/audit/audit-presentation.service.spec.ts lib/shared/widgets/audit_event_card.dart test/shared/widgets/audit_event_card_test.dart
git commit -m "fix(audit): present every field through shared policy"
```

---

### Task 4: Make legacy/core audit producers store safe semantic changes

**Files:**
- Modify: `server/src/crm/crm-mappers.ts:174-275`
- Modify: `server/src/crm/crm-mappers.spec.ts`
- Modify: `server/src/crm/lead-command.service.spec.ts`
- Modify: `server/src/crm/students/student-command.service.spec.ts`

**Interfaces:**
- Consumes: `createSafeAuditChange` and `AuditFieldChangeInput` from Task 2.
- Produces: `diffEntityFields(...): AuditFieldChangeInput[]` with optional immutable presentation hints.

- [ ] **Step 1: Add failing producer-safety tests**

```ts
it('stores responsibility as a changed-only fact without UUIDs', () => {
  const changes = diffEntityFields(
    { assigned_to: oldUuid, custom_data: {} },
    { assigned_to: newUuid, custom_data: {} },
    ['assigned_to'],
  );
  expect(changes).toEqual([{
    field: 'assigned_to',
    from: null,
    to: null,
    label: 'Ответственный',
    valueType: 'reference',
    displayMode: 'changed_only',
  }]);
  expect(JSON.stringify(changes)).not.toContain(oldUuid);
});

it('stores contactPersons only as safe counts', () => {
  const changes = diffEntityFields(
    { custom_data: { contactPersons: [] } },
    { custom_data: { contactPersons: [{ name: 'Анна', phone: '+79991234567' }] } },
    [],
  );
  expect(changes[0]).toMatchObject({
    field: 'custom_data.contactPersons',
    from: 0,
    to: 1,
    displayMode: 'count',
  });
  expect(JSON.stringify(changes)).not.toContain('+79991234567');
});
```

- [ ] **Step 2: Run mapper tests and verify RED**

Run: `npm --prefix server test -- --runInBand src/crm/crm-mappers.spec.ts`

Expected: FAIL because raw UUIDs and JSON are still stored.

- [ ] **Step 3: Route each produced change through the policy**

Replace `toAuditScalar` and the local `AUDIT_FIELD_LABELS` with
`createSafeAuditChange`. Skip `null` results. Preserve scalar business values
exactly and preserve existing valueless email behavior. Structured arrays and
technical identifiers must be sanitized before `AuditService.record`, not only
hidden later.

- [ ] **Step 4: Prove lead/student audit metadata is safe**

Update command specs so their `audit.record` expectation checks the merged
`metadata.changes` array, Russian labels, changed-only references, exact
director values, and absence of UUID/JSON PII.

- [ ] **Step 5: Run producer and command suites**

Run:

`npm --prefix server test -- --runInBand --runTestsByPath src/crm/crm-mappers.spec.ts src/crm/lead-command.service.spec.ts src/crm/students/student-command.service.spec.ts`

Expected: three suites PASS.

- [ ] **Step 6: Commit**

```bash
git add server/src/crm/crm-mappers.ts server/src/crm/crm-mappers.spec.ts server/src/crm/lead-command.service.spec.ts server/src/crm/students/student-command.service.spec.ts
git commit -m "fix(crm): store safe semantic audit changes"
```

---

### Task 5: Snapshot typed custom-field changes inside transactions

**Files:**
- Modify: `server/src/crm/clients/client-config.repository.ts:8-140`
- Modify: `server/src/crm/clients/client-write.validator.ts:32-230`
- Modify: `server/src/crm/clients/client-write.validator.spec.ts`
- Modify: `server/src/crm/lead-write.repository.ts:20-125`
- Modify: `server/src/crm/lead-write.repository.spec.ts`
- Modify: `server/src/crm/students/student-mutation.types.ts`
- Modify: `server/src/crm/students/student-mutation.executor.ts:180-385`
- Modify: `server/src/crm/students/student-mutation.executor.spec.ts`
- Modify: `server/src/crm/lead-command.service.ts:76-122`
- Modify: `server/src/crm/students/student-command.service.ts:80-353`

**Interfaces:**
- Produces: `TypedClientCustomFieldWrite extends TypedClientCustomValue` with `fieldKey`, `label`, and `valueType`; `replaceTypedClientValues(...): Promise<AuditFieldChangeInput[]>`.
- Consumes: `createSafeAuditChange` and command metadata contract from Tasks 2 and 4.

- [ ] **Step 1: Add failing validator snapshot test**

```ts
expect(result.values[0]).toMatchObject({
  definitionId: definition.id,
  fieldKey: 'instrument',
  label: 'Любимый инструмент',
  valueType: 'select',
  valueText: 'DRUMS',
});
```

Assert `valueText` remains exactly `DRUMS`; add an unseen director value and
mixed-case case.

- [ ] **Step 2: Run validator tests and verify RED**

Run: `npm --prefix server test -- --runInBand src/crm/clients/client-write.validator.spec.ts`

Expected: FAIL because validated values do not carry definition snapshots.

- [ ] **Step 3: Extend typed writes with immutable presentation data**

```ts
export interface TypedClientCustomFieldWrite extends TypedClientCustomValue {
  fieldKey: string;
  label: string;
  valueType: ClientCustomValueType;
}
```

Build this object from the already-authoritative definition in
`ClientWriteValidator.convertValue`. Persistence continues to write only the
existing value columns.

- [ ] **Step 4: Add failing transactional diff tests**

In repository/executor specs, seed an old typed value, replace it with a new
value, and expect `replaceTypedClientValues` to return:

```ts
[{ 
  field: 'customFields.instrument',
  label: 'Любимый инструмент',
  valueType: 'text',
  displayMode: 'values',
  from: 'PIANO',
  to: 'DRUMS',
}]
```

Also cover removal, boolean, date, primitive multi-select, and unchanged
values. Every director value must remain exact.

- [ ] **Step 5: Run transactional tests and verify RED**

Run:

`npm --prefix server test -- --runInBand --runTestsByPath src/crm/lead-write.repository.spec.ts src/crm/students/student-mutation.executor.spec.ts`

Expected: FAIL because replace functions currently return `void`.

- [ ] **Step 6: Return typed changes from the existing replace operation**

Under the same row/transaction lock, read the current typed value rows joined
to definitions, perform the existing delete/upsert, compare typed values, and
return safe changes using stored definition labels/types. Do not add a second
write path. Lead and student mutation results carry `customFieldChanges` to
their command services.

- [ ] **Step 7: Merge typed and legacy changes into one audit event**

```ts
metadata: {
  changes: [
    ...diffEntityFields(before, after, AUDITED_FIELDS),
    ...customFieldChanges,
  ],
}
```

Remove the unhelpful `customFieldDefinitionIds`-only presentation metadata once
all tests prove the safe semantic changes are present. Keep definition IDs out
of user-visible values.

- [ ] **Step 8: Run all typed-field and command tests**

Run:

`npm --prefix server test -- --runInBand --runTestsByPath src/crm/clients/client-write.validator.spec.ts src/crm/lead-write.repository.spec.ts src/crm/students/student-mutation.executor.spec.ts src/crm/lead-command.service.spec.ts src/crm/students/student-command.service.spec.ts`

Expected: five suites PASS.

- [ ] **Step 9: Commit**

```bash
git add server/src/crm/clients/client-config.repository.ts server/src/crm/clients/client-write.validator.ts server/src/crm/clients/client-write.validator.spec.ts server/src/crm/lead-write.repository.ts server/src/crm/lead-write.repository.spec.ts server/src/crm/students/student-mutation.types.ts server/src/crm/students/student-mutation.executor.ts server/src/crm/students/student-mutation.executor.spec.ts server/src/crm/lead-command.service.ts server/src/crm/students/student-command.service.ts
git commit -m "feat(crm): snapshot typed field audit changes"
```

---

### Task 6: Harden platform refs and asymmetric producers

**Files:**
- Modify: `server/src/crm/tasks/shared-task.service.ts:620-635`
- Modify: `server/src/crm/tasks/shared-task-postgres.integration.spec.ts`
- Modify: `server/src/crm/schedule/lesson-transition-commit.service.ts:130-150`
- Modify: `server/src/crm/schedule/lesson-transition-order.spec.ts`
- Modify: `server/src/crm/room-lifecycle.service.ts:205-225,545-565`
- Modify: `server/src/crm/room-lifecycle.service.spec.ts`
- Modify: `server/src/audit/audit-presentation.coverage.spec.ts`

**Interfaces:**
- Consumes: read-time technical suppression from Task 2.
- Produces: symmetric business refs or explicit safe metadata changes; no technical identifiers in presentation refs.

- [ ] **Step 1: Add failing regressions for known producer defects**

Assert that closed tasks, lesson transitions, and room lifecycle events do not
produce `closedBy`, `transitionFingerprint`, UUIDs, hashes, false removals, or
English labels. For room lifecycle, unchanged `capacity` must not appear as
`Capacity: 1 → Не указано`.

- [ ] **Step 2: Run focused tests and verify RED**

Run each resolved focused suite with `npm --prefix server test -- --runInBand`.

Expected: FAIL on the current asymmetric or technical refs.

- [ ] **Step 3: Make producer refs symmetric and business-only**

When a business value is relevant, include the same key family in both refs.
Move technical identifiers into non-presented metadata only when operationally
required. Prefer explicit safe `metadata.changes` for user-visible facts. Do
not delete technical data required for reconciliation; only remove it from the
presentation surface.

- [ ] **Step 4: Strengthen production coverage**

Extend the audit production contract so every statically known presented
field is either in the shared policy/catalog or explicitly classified as
technical/changed-only. Add the known SQL/import/dynamic producer fixtures that
the current TypeScript AST inventory does not discover.

- [ ] **Step 5: Run focused and coverage tests**

Run:

`npm --prefix server test -- --runInBand --runTestsByPath src/crm/tasks/shared-task-postgres.integration.spec.ts src/crm/schedule/lesson-transition-order.spec.ts src/crm/room-lifecycle.service.spec.ts src/audit/audit-presentation.coverage.spec.ts`

Expected: all PASS; no technical user-visible values.

- [ ] **Step 6: Commit**

```bash
git add server/src/crm/tasks/shared-task.service.ts server/src/crm/tasks/shared-task-postgres.integration.spec.ts server/src/crm/schedule/lesson-transition-commit.service.ts server/src/crm/schedule/lesson-transition-order.spec.ts server/src/crm/room-lifecycle.service.ts server/src/crm/room-lifecycle.service.spec.ts server/src/audit/audit-presentation.coverage.spec.ts
git commit -m "fix(audit): remove technical and asymmetric refs"
```

---

### Task 7: Verify the complete audit contour

**Files:**
- Modify only if contract evidence requires it: `docs/architecture/NEXT-AGENT-HANDOFF.md`
- Test: all files changed in Tasks 1-6

**Interfaces:**
- Consumes: all prior task contracts.
- Produces: a release-ready code commit on `main`; it does not deploy production.

- [ ] **Step 1: Run focused audit/CRM regression**

`npm --prefix server test -- --runInBand --runTestsByPath src/settings/crm-custom-field-catalog.spec.ts src/settings/settings.service.spec.ts src/audit/audit-field-presentation.policy.spec.ts src/audit/audit-presentation.service.spec.ts src/audit/audit-presentation.coverage.spec.ts src/crm/crm-mappers.spec.ts src/crm/clients/client-write.validator.spec.ts src/crm/lead-write.repository.spec.ts src/crm/lead-command.service.spec.ts src/crm/students/student-mutation.executor.spec.ts src/crm/students/student-command.service.spec.ts src/crm/dashboard.service.spec.ts src/crm/clients/client-internal-context.service.spec.ts`

Run: `flutter test test/shared/widgets/audit_event_card_test.dart`

Expected: every backend suite and the shared Flutter-card suite PASS with zero
failed tests.

- [ ] **Step 2: Run static and security gates**

```bash
npm --prefix server run typecheck
npm --prefix server run build
npm --prefix server run security:gate
flutter analyze
```

Expected: exit code `0`; security summary `fail: 0`, `warn: 0`; Flutter reports
`No issues found`.

- [ ] **Step 3: Run the full backend suite on a dedicated local database**

Create a uniquely named local test database using the repository toolchain,
run all current migrations, set `V4_PLATFORM_TEST_DATABASE_URL`, `DATABASE_URL`,
and `MIGRATION_DATABASE_URL` to that database, then run:

`npm --prefix server test -- --runInBand`

Then run: `flutter test --reporter compact`

Expected: every backend and Flutter suite/test PASS. Drop only the exact
dedicated test database after the run.

- [ ] **Step 4: Run diff and repository checks**

```bash
git diff --check
git status --short --branch
```

Expected: only intended files are changed before the final commit; no `.env`,
PII fixture, production dump, backup, Office lock file, `.claude/`, or generated
artifact is tracked.

- [ ] **Step 5: Update the RepoWise index and inspect change risk**

Run `repowise update --index-only`, move any generated `.claude/` directory
outside the checkout, then call RepoWise `get_change_risk` for the complete
implementation range. Resolve any missing co-change or test finding before
completion.

- [ ] **Step 6: Independent two-stage review**

Dispatch one specification-compliance reviewer and one code-quality/security
reviewer. Fix every P1/P2 finding with a new red-green test and repeat the
focused gate.

- [ ] **Step 7: Push the verified implementation commits**

Run `git status --short --branch` and require a clean tree because Tasks 1-6
and every review fix commit their own exact files. Then run
`git push origin main` and verify `main...origin/main` has no ahead/behind
marker.

- [ ] **Step 8: Report release status accurately**

State the commit, exact test counts, build/security results, and that the code
is ready for release but not deployed. Production deployment waits for the
owner's explicit `Выпускай` command.
