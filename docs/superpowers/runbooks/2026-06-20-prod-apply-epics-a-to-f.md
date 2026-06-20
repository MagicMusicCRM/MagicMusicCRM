# Prod apply runbook — Epics A/B/E/C6/F (migrations 0025–0031 + HolliHop import + deploy)

**Status:** Ready. Migrations `0025–0031` Docker-validated end-to-end (full chain applies; all 7 roll back cleanly to the `0024` prod baseline; re-apply clean). Server suite 265/265, typecheck 0.

> **GATING:** Every step that touches production (pg_dump, prod migrations, the import, deploy) is **operator-executed** — run them yourself with your prod credentials. The assistant never connects to prod. Fill `PROD_DB_URL` from your own secret store (do not paste it into shared logs). Each phase has a verification gate; do not proceed past a failed gate.

---

## What this ships

- **Schema/data (migrations 0025–0031):** phone normalization + review queue (0025); CRM dictionaries — loss reasons, sources, disciplines, branch_disciplines, student_disciplines, `lead_statuses.is_terminal/requires_reason` (0026); unified `branch_id` on leads/students/payments/expenses/tasks/chats + `chats.lead_id/student_id` + guarded backfill from `custom_data` (0027); `lead_status_history`/`student_status_history` (0028); families/family_members/contacts (0029); merge_log (0030); analytics refresh-runs + 3 finance matviews owned by `magiccrm_app` (0031).
- **Server code (branch `s8-desktop-ux-stabilization`):** dual-write `branch_id`, status-history bracketing, dictionary/family/merge endpoints, `/analytics/*` (8 reports + CSV) + the refresh worker, the auto-lead-from-admin-chat hook, the HolliHop importer writing the normalized tables.
- **Data (HolliHop import):** populates `student_disciplines`/`branch_id`/`contacts` (today 0/1955 students have a branch or discipline).

---

## Phase 0 — Pre-flight (no prod writes)

- [ ] Confirm the branch is green: `cd server && npm run typecheck && npm test` → 0 errors, 265 passing.
- [ ] Confirm prod is at baseline **0024** (the runner records applied migrations). Run against prod read-only:
  ```bash
  # Lists applied migration ids. The newest should be 0024_branch_timezone.
  psql "$PROD_DB_URL" -c "select name from app.schema_migrations order by name;" 2>/dev/null \
    || psql "$PROD_DB_URL" -c "\dt app.*migrat*"   # if the tracking table name differs, find it first
  ```
  Expected: `…0024_branch_timezone` present, `0025_*`..`0031_*` ABSENT. If any 0025+ is already there, STOP and reconcile.
- [ ] Pick a low-traffic window. The migrations are additive + guarded; expected lock time is brief, but `0031` builds 3 matviews by scanning lessons/payments/expenses — at current volume this is seconds, but run off-peak.

## Phase 1 — Backup (REQUIRED before any write)

- [ ] Full logical backup, custom format, timestamped:
  ```bash
  pg_dump "$PROD_DB_URL" -Fc -f "prod_backup_pre_0025-0031_$(date +%Y%m%d_%H%M%S).dump"
  ```
- [ ] Verify the dump is non-empty and restorable-looking: `pg_restore -l prod_backup_pre_0025-0031_*.dump | head`. Keep this file until Phase 5 passes.

## Phase 2 — Apply migrations 0025–0031

- [ ] From `server/`, with prod URLs, run the migrator (applies only the 7 un-applied; transactional per migration):
  ```bash
  cd server
  MIGRATION_DATABASE_URL="$PROD_DB_URL" DATABASE_URL="$PROD_DB_URL" npm run db:migrate
  ```
  Expected tail: `Applied migrations: 0025_phone_normalization, 0026_crm_dictionaries, 0027_unified_branch_id, 0028_status_history, 0029_families, 0030_merge_log, 0031_analytics`
- [ ] **Verification gate** — all 7 objects present + matviews owned by `magiccrm_app`:
  ```bash
  psql "$PROD_DB_URL" -tA -c "select
    to_regclass('app.mv_finance_monthly') is not null,
    to_regclass('app.merge_log') is not null,
    to_regclass('app.families') is not null,
    to_regclass('app.lead_status_history') is not null,
    (select count(*) from information_schema.columns where table_schema='app' and table_name='leads' and column_name='branch_id')=1,
    to_regclass('app.lead_loss_reasons') is not null,
    (select count(*) from information_schema.columns where table_schema='app' and table_name='leads' and column_name='phone_normalized')=1;"
  # expect: t|t|t|t|t|t|t
  psql "$PROD_DB_URL" -c "select matviewname, matviewowner from pg_matviews where schemaname='app';"
  # expect 3 rows, owner = magiccrm_app
  ```
- [ ] What changed in your DATA (so you can sanity-check): `0025` filled `phone_normalized` + queued un-normalizable phones in `app.phone_review_queue`; `0027` backfilled `branch_id` from `custom_data->>'branchId'/'branch_id'` where it was a valid existing branch (guarded — unmatched rows stay NULL); `0026` seeded loss reasons/sources; `0028/0029/0030` are empty new tables; `0031` matviews are populated from current data. Spot-check:
  ```bash
  psql "$PROD_DB_URL" -tA -c "select
    (select count(*) from app.leads where phone_normalized is not null) as leads_phone,
    (select count(*) from app.phone_review_queue) as review_queue,
    (select count(*) from app.students where branch_id is not null) as students_branch_backfilled,
    (select count(*) from app.lead_loss_reasons) as loss_reasons_seeded;"
  ```

### Rollback (only if a gate fails)

Migrations are reversible to the `0024` baseline (Docker-proven). Either:
```bash
cd server   # revert the applied new ones, newest first; run once per migration to undo
MIGRATION_DATABASE_URL="$PROD_DB_URL" DATABASE_URL="$PROD_DB_URL" npm run db:rollback   # repeat up to 7×
```
…or, for a clean restore, drop+recreate from the Phase-1 dump. Prefer `db:rollback` for a partial failure; prefer the dump restore if data looks wrong.

## Phase 3 — Deploy server code

- [ ] Deploy the `s8-desktop-ux-stabilization` server build **after** Phase 2 (the new code needs the new schema; the old code tolerates the additive schema, so there is no hard ordering window, but deploy-after-migrate is the safe order).
- [ ] Confirm the app boots (the `AnalyticsRefreshWorker` + `NotificationWorker` start their timers; `MessengerModule`→`CrmModule` wiring resolves).
- [ ] **Verification gate** — the analytics surface responds (as a manager/admin token):
  ```bash
  curl -s -H "Authorization: Bearer $ADMIN_JWT" "$API/analytics/overview"        # KPIs
  curl -s -H "Authorization: Bearer $ADMIN_JWT" "$API/analytics/funnel"          # stages
  curl -s -H "Authorization: Bearer $ADMIN_JWT" "$API/analytics/weekly-report"   # composite
  ```
- [ ] Within ~5 min the refresh worker should record a run: `psql "$PROD_DB_URL" -c "select kind,status,finished_at from app.analytics_refresh_runs order by claimed_at desc limit 3;"` → a `matviews` row, `status='completed'`.

## Phase 4 — HolliHop import (the big data step — separate backup first)

> Populates `student_disciplines`/`branch_disciplines`/`disciplines`, `students.branch_id`/`leads.branch_id`, `app.contacts`. Idempotent (deterministic ids) and re-runnable. **Runbook caveat:** safe as a one-shot; a *second* re-run after HolliHop source edits can (a) trip the single-primary discipline index if a student's disciplines were reordered, and (b) leave an orphan `contacts` row if a phone/name changed — for a one-shot fresh run neither triggers.

- [ ] Fresh backup before the import: `pg_dump "$PROD_DB_URL" -Fc -f "prod_backup_pre_import_$(date +%Y%m%d_%H%M%S).dump"`.
- [ ] **Dry-run first** (no writes / audit-only) to produce a diff report — review what it WILL change before applying. Use the live key (`HOLLIHOP_AUTH_KEY=…`) or the local archive (`HOLLIHOP_IMPORT_SOURCE_DIR=…`):
  ```bash
  cd server
  HOLLIHOP_IMPORT_MODE=dry_run DATABASE_URL="$PROD_DB_URL" npm run hollihop:import   # review the diff/warnings
  ```
- [ ] Review the dry-run report (counts; "что не разрешилось" — unresolved branch/discipline/teacher warnings). If acceptable:
- [ ] **Apply:**
  ```bash
  cd server
  HOLLIHOP_IMPORT_MODE=apply DATABASE_URL="$PROD_DB_URL" npm run hollihop:import
  ```
- [ ] **Verification gate** — disciplines/branch now populated (was 0/1955):
  ```bash
  psql "$PROD_DB_URL" -tA -c "select
    (select count(*) from app.students where branch_id is not null) as students_with_branch,
    (select count(*) from app.student_disciplines) as student_disciplines,
    (select count(*) from app.student_disciplines where is_primary) as primary_disciplines,
    (select count(*) from app.branch_disciplines) as branch_disciplines,
    (select count(*) from app.contacts) as contacts;"
  ```

## Phase 5 — Post-deploy verification & sign-off

- [ ] Existing «Лиды» board + messenger still work (additive changes; no regression expected).
- [ ] Auto-lead: a non-staff user messaging the administration chat creates one «Через приложение / Новый» lead (idempotent — repeat messages don't duplicate). Check `select count(*) from app.leads where source='Через приложение';` trends up by ≈1 per new app user.
- [ ] The 8 `/analytics` reports return sane numbers for a known period.
- [ ] Keep both pg_dump files for at least a few days. Move the Linear issues (KVA-184/189/187/188/186/190/179/182/180/183) from "In Review" to "Done" once prod is verified.

---

## Known follow-ups (post-ship, non-blocking)

- Add `'auto_app'` to the `user_crm_links.link_source` constraint (auto-leads currently use `'auto_phone'`).
- The `saveContactFromChat` path shares the (now-fixed-in-autoCreate) duplicate-lead race — apply the same advisory-lock guard.
- Populate `chats.branch_id` (then chat-SLA can be branch-scoped; currently org-wide).
- A global `UuidPipe` on `branchId` query params (a non-UUID value currently 500s on `/analytics`).
- Frontend tails: A2 phone mask, the «Клиенты» Flutter window (C1–C8), the families/merge-queue UIs, report dashboards.
- F follow-ups: scheduled weekly-report email delivery (E6), F8 branch working-hours, P1/P2 reports.
