# MagicMusicCRM v4 — staged rollout and recovery

This runbook enables v4 only after `T8.4.1` is green. A
`pass_with_owner_exception` result may be used only for the isolated staging
rehearsal and must keep `productionApproved=false`. Production execution
requires Critical/High=0 and the separate `INT-S6` owner decision; the
rehearsal command accepts only `staging` and cannot target production.

## Ownership

| Responsibility | Owner |
|---|---|
| Release decision and business UAT | Product owner |
| Maintenance window, deploy and rollback | Release operator |
| PostgreSQL backup/restore and reconciliation | Data operator |
| Worker/outbox metrics and alerts | On-call operator |
| Security incident or access leak | Security owner; immediately kill-switch |

## Pre-deploy

1. Freeze writes for the maintenance window and record the candidate commit.
2. Require the signed `docs/audits/v4-release-gate-result.json`: 29/29 REQ,
   zero drift and Windows/Android pass. Production additionally requires
   Critical/High=0. The owner-deferred security exception is staging-only and
   must point to backlog #16/#17.
3. Pause the completion worker with
   `LESSON_COMPLETION_WORKER_ENABLED=false`; wait for claimed work to finish.
4. Drain `app.platform_outbox_events`; pending, dead-letter and poison must be
   visible. Dead-letter or poison greater than zero blocks enable.
5. Create an encrypted off-host PostgreSQL backup, verify its SHA-256, then
   restore it into an isolated database and check the latest migration.

## Deploy and observe

1. Deploy an immutable image tag matching the accepted commit.
2. Start with `V4_ACCESS_MODE=shadow` and `V4_SCHEDULE_MODE=shadow`; keep both
   kill switches `false` and require `V4_PARITY_UNEXPLAINED_DIFFS=0`.
3. Check `/api/health/live` and `/api/health/ready`, authentication, one scoped
   REST read per role, realtime reconnect, outbox lag and worker backlog.
4. Enable one domain at a time by changing its mode to `v4`. Observe at least
   one normal workload interval before enabling the next domain.
5. Resume the worker with `LESSON_COMPLETION_WORKER_ENABLED=true`; confirm due,
   retry, poison and oldest-due metrics. Confirm outbox returns to zero lag.

## Rollback and forward recovery

Rollback is a compatibility switch, not a destructive schema down-migration:

1. Set the affected `V4_*_KILL_SWITCH=true`; readiness must report the legacy
   effective path.
2. Pause the worker, preserve logs/request IDs, and drain committed outbox.
3. Verify financial fact counts and signed reconciliation. Never delete or
   rewrite new immutable payment, settlement or lifecycle facts.
4. If storage recovery is required, restore the verified backup into an
   isolated database first. A production restore needs a separate explicit
   decision and documented recovery point.
5. Apply a forward fix, set unexplained parity to zero, clear the kill switch,
   return to `shadow`, then re-enable `v4` one domain at a time.

## Alerts and incident threshold

Page the on-call operator for readiness failure, non-zero unexplained drift,
dead-letter outbox, poison completion work, oldest due work above 120 seconds,
or any access/privacy leak. A Critical/High security finding or cross-role data
leak immediately blocks rollout and activates both kill switches.

## Rehearsal

```powershell
pwsh -File scripts/v4_rollout_rehearsal.ps1 -Target staging -Rollback
```

The rehearsal consumes the isolated restore created by `T8.4.1`, checks
preflight, shadow/enable/block/rollback/forward states, runs health/auth/
realtime/outbox smoke, and proves immutable financial fact counts are stable.
Its machine evidence is `docs/audits/v4-rollout-rehearsal.json`.
