# MagicMusicCRM v4 — Read-Only Data Preflight

**Task:** T8.1.3
**Mode:** `repeatable-read/read-only`
**Result:** PASS
**Scan digest:** `267c1cce8fb5635640c69e2b3e95a7b96a21ec04e1266240b7cdb18244010090`

## Summary

| Metric | Count |
|---|---:|
| Checks | 19 |
| Findings | 0 |
| Blockers | 0 |
| Warnings | 0 |

## Checks

| Check | Owner | Severity | Findings |
|---|---|---|---:|
| `access.user-crm-link-ambiguous` | SYS-ACCESS | blocker | 0 |
| `access.user-link-cardinality` | SYS-ACCESS | blocker | 0 |
| `commerce.duplicate-payment-external-id` | SYS-COMMERCE | blocker | 0 |
| `commerce.materialized-balance-drift` | SYS-COMMERCE | warning | 0 |
| `commerce.subscription-reference-gaps` | SYS-COMMERCE | blocker | 0 |
| `commerce.subscription-snapshot-unprovable` | SYS-COMMERCE | blocker | 0 |
| `commerce.subscription-usage-out-of-range` | SYS-COMMERCE | blocker | 0 |
| `commerce.v7-payment-linkage-drift` | SYS-COMMERCE | blocker | 0 |
| `commerce.v7-payment-version-drift` | SYS-COMMERCE | blocker | 0 |
| `commerce.v7-subscription-funding-gap` | SYS-COMMERCE | blocker | 0 |
| `crm.student-identity-missing` | SYS-CRM | blocker | 0 |
| `crm.student-phone-ambiguous` | SYS-CRM | warning | 0 |
| `schedule.active-teacher-branch-missing` | SYS-SCHEDULE | blocker | 0 |
| `schedule.future-missing-resources` | SYS-SCHEDULE | blocker | 0 |
| `schedule.future-overlaps` | SYS-SCHEDULE | blocker | 0 |
| `schedule.future-snapshot-incomplete` | SYS-SCHEDULE | blocker | 0 |
| `schedule.future-teacher-branch-missing` | SYS-SCHEDULE | blocker | 0 |
| `workflow.task-audience-ambiguous` | SYS-WORKFLOW | blocker | 0 |
| `workflow.task-entity-orphan` | SYS-WORKFLOW | blocker | 0 |

The JSON artifact contains every finding as stable entity/related IDs; it
does not include names, phones, emails, connection strings, or monetary
amounts.

## Read-only proof

- Transaction setting is read-only: true.
- A no-row UPDATE probe was rejected with SQLSTATE `25006`.
- Two scans in one repeatable-read snapshot were byte-stable: true.
- Findings digest: `267c1cce8fb5635640c69e2b3e95a7b96a21ec04e1266240b7cdb18244010090`.

## Reproduction

```powershell
npm --prefix server run v4:preflight -- --check-read-only
```
