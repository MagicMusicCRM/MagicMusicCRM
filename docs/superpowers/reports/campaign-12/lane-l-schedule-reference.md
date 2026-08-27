# Campaign-12 Lane L — Schedule Reference Settings

- Tier dependency SHA: `624f36c560ed7fb2de5f92612c3a9b2445339d68`
- Branch: `codex/campaign12-schedule-reference`
- Baseline: RepoWise health `2.14`, NLOC `763`, max CCN `11`, critical
  god-class finding; historical risk `89%` increasing with 6 fixes in 6 months

## TDD evidence

The first controller/widget run failed because
`schedule_reference_controller.dart`, `schedule_reference_models.dart`, and
`ScheduleReferenceController` did not exist. The first architecture run found
only the 796-line legacy owner instead of the six required semantic owners.
After extraction, all nine controller/widget contracts and all four AST guard
tests pass.

## Owners and structural gate

| Owner | Guard NLOC | Physical lines | Max CCN |
| --- | ---: | ---: | ---: |
| `schedule_reference_settings.dart` | 58 | 70 | 3 |
| `schedule_reference_models.dart` | 161 | 180 | 8 |
| `schedule_reference_controller.dart` | 369 | 401 | 7 |
| `schedule_reference_view.dart` | 186 | 199 | 4 |
| `schedule_reference_cards.dart` | 311 | 332 | 10 |
| `schedule_reference_dialogs.dart` | 127 | 133 | 8 |

The controller type is 364 token NLOC with 46 members and 30 callables. Its
file has 35 executable nodes, including 5 nested callbacks/closures; the type
proxy therefore measures the controller itself rather than inflating the
count with closures. The guard dynamically discovers every
`schedule_reference_*.dart`, rejects parse/part bypasses, caps each owner at
500 NLOC and each executable at CCN 10, and caps types at 400 NLOC, 50 members,
and 30 callables. Negative fixtures prove comment/string decoys, whitespace,
service aliases, new owners, syntax errors, CCN, and type-callable bypasses
fail.

## Contract proof

- Request generations reject late schedule success/failure after a newer
  branch or teacher selection; catalogues choose the first still-valid item.
- Branch save keeps version, timezone, weekly rows, exceptions, and non-null
  extension fields. Teacher assignment version `3` becomes availability
  expected version `4`; missing `activeFrom` becomes `1970-01-01`.
- Duplicate recurring rules remain in `extraRecurring`, lock editing, and are
  sent unchanged. New recurring rules retain branch timezone and deterministic
  `validFrom`; unavailable intervals are UTC, `available: false`, and require a
  non-empty reason.
- `canEdit=false` blocks every controller mutation and service write. Existing
  settings keys, selector semantics, Russian copy, weekday numbering, time
  picker flow, success toasts, and retry text remain unchanged.

## Lane gate

- Focused new tests: 13/13 PASS (9 controller/widget, 4 architecture).
- Existing named workspace smoke: 2/2 PASS (read-only split view and director
  assignment/availability version chaining).
- `flutter analyze --no-pub` on all six production owners: PASS, no issues.
- Explicit format, contract grep, `git diff --check`, generated registrant
  restoration, and six verify-only path checks: PASS.

Per lane instruction, RepoWise/Sentrux update or scan was not run. Raw indexed
health is history-sensitive and the index is behind this isolated worktree;
the root integration lane owns the exact post-commit health gate.
