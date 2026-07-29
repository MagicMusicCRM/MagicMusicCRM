# MagicMusicCRM v4 — Read-Only Data Preflight

**Task:** T8.1.3
**Mode:** `repeatable-read/read-only`
**Result:** PASS
**Scan digest:** `350b1b1841252f42f1dffe0bc792a19870e3f7a1ad955f31870fa4f87c6a1df8`

## Summary

| Metric | Count |
|---|---:|
| Checks | 16 |
| Findings | 20 |
| Blockers | 19 |
| Warnings | 1 |

## Checks

| Check | Owner | Severity | Findings |
|---|---|---|---:|
| `access.user-crm-link-ambiguous` | SYS-ACCESS | blocker | 0 |
| `access.user-link-cardinality` | SYS-ACCESS | blocker | 2 |
| `commerce.duplicate-payment-external-id` | SYS-COMMERCE | blocker | 1 |
| `commerce.materialized-balance-drift` | SYS-COMMERCE | warning | 1 |
| `commerce.subscription-reference-gaps` | SYS-COMMERCE | blocker | 0 |
| `commerce.subscription-snapshot-unprovable` | SYS-COMMERCE | blocker | 1 |
| `commerce.subscription-usage-out-of-range` | SYS-COMMERCE | blocker | 1 |
| `crm.student-identity-missing` | SYS-CRM | blocker | 2 |
| `crm.student-phone-ambiguous` | SYS-CRM | warning | 0 |
| `schedule.active-teacher-branch-missing` | SYS-SCHEDULE | blocker | 1 |
| `schedule.future-missing-resources` | SYS-SCHEDULE | blocker | 1 |
| `schedule.future-overlaps` | SYS-SCHEDULE | blocker | 3 |
| `schedule.future-snapshot-incomplete` | SYS-SCHEDULE | blocker | 3 |
| `schedule.future-teacher-branch-missing` | SYS-SCHEDULE | blocker | 2 |
| `workflow.task-audience-ambiguous` | SYS-WORKFLOW | blocker | 1 |
| `workflow.task-entity-orphan` | SYS-WORKFLOW | blocker | 1 |

The JSON artifact contains every finding as stable entity/related IDs; it
does not include names, phones, emails, connection strings, or monetary
amounts.

## Read-only proof

- Transaction setting is read-only: true.
- A no-row UPDATE probe was rejected with SQLSTATE `25006`.
- Two scans in one repeatable-read snapshot were byte-stable: true.
- Findings digest: `350b1b1841252f42f1dffe0bc792a19870e3f7a1ad955f31870fa4f87c6a1df8`.

## Reproduction

```powershell
npm --prefix server run v4:preflight -- --check-read-only
```
