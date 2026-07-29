# MagicMusicCRM v4 — Client Sources, Required Fields & Typed Custom Values

**Task:** T3.1.2
**Result:** PASS
**Date:** 2026-07-25

## Schema

Migration `0079_client_configuration` adds:

- versioned/archivable `lead_sources` and `leads.source_id`;
- `client_custom_field_definitions` for Lead/Student fields;
- typed `client_custom_field_values` with exactly one text/number/boolean/date
  storage column per valid value;
- locked system definitions for the required Lead and Student minimum;
- indexes for source lookup and entity value composition.

Existing source strings are matched to the active catalog. Unknown historical
strings become inactive `legacy_*` catalog entries, so no Lead loses its
source. Existing `crm_custom_fields` and `custom_data` are backfilled into the
normalized tables. Values that cannot be safely coerced remain available as
`legacy_untyped`; new writes cannot create that state.

## Validation and configuration

Strict v4 Lead validation requires first name, last name, valid Russian phone
and an active source. Strict Student validation additionally requires an
active branch and non-empty client status. Required custom definitions are
checked together with typed values before a write starts. Normalizable phone
input returns a `PHONE_NORMALIZED` warning with the canonical `+7` value.

Director and `system_admin` can manage the configuration through:

- `/api/crm/client-config/sources`;
- `/api/crm/client-config/fields`.

Admin/Manager mutations are denied by the domain policy. Updates use
`expectedVersion`; used sources/fields are archived, never physically deleted.
System required fields cannot become optional or archived. A field type cannot
change while values exist and returns `422 FIELD_TYPE_MIGRATION_REQUIRED`.

## Verification

```powershell
npm --prefix server run db:rollback
npm --prefix server run db:migrate
npm --prefix server test -- --runTestsByPath src/crm/clients/client-config-postgres.integration.spec.ts
npm --prefix server run test:actor-matrix:v4
npm --prefix server run typecheck
npm --prefix server run build
npm --prefix server test
pwsh -File scripts/v4_inventory.ps1 -Check
```

| Gate | Result |
|---|---:|
| Migration `0079` down → up | PASS |
| Exact PostgreSQL configuration suite | 1/1 suite, 6/6 tests |
| Actor Matrix + payload leak scan | 2/2 suites, 8/8 tests |
| Route decisions | 1464/1464 |
| Access coverage | 244/244 private routes |
| Backend typecheck/build | PASS / PASS |
| Full backend regression | 116/116 suites, 1051/1051 tests |
| Current-state inventory | 256 routes, 561 DTO fields, 0 unowned |
