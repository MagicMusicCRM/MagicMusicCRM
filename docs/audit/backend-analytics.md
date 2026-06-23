# Backend Analytics Audit — MagicMusicCRM

> Scope: `server/src/analytics/**` and task/finance code in `server/src/crm/`
> Audited: 2026-06-21

---

## 1. Overview

Analytics is a dedicated NestJS module (`AnalyticsModule`) that owns:
- `AnalyticsController` — 14 HTTP GET endpoints under `/analytics/*`
- `AnalyticsService` — all business logic; delegates overview/dashboard to `CrmService`
- `AnalyticsRefreshWorker` — background interval worker that refreshes three materialized views every 5 minutes

Finance and task logic live in the CRM module (`CrmModule`):
- Finance: `GET /crm/reports/finance`, `GET /crm/payments`, `POST /crm/payments`, `GET /crm/expected-payments`, `GET /crm/student-balances`, `GET /crm/subscriptions`
- Tasks: `GET /crm/tasks`, `POST /crm/tasks`, `PATCH /crm/tasks/:id`

All endpoints require a valid JWT (`JwtAuthGuard`). Almost every analytics and finance endpoint gates itself to manager/admin via `policy.assertCanWriteCrm()`.

---

## 2. Features (complete inventory)

### Analytics endpoints (`/analytics/*`)

- **GET /analytics/overview** — Org-wide summary KPIs: total students, teachers, branches, today's lessons, month completed lessons, open tasks, new leads, month revenue. Delegates to `CrmService.getOverview`. Requires manager/admin.
- **GET /analytics/dashboard** — Manager dashboard with configurable date range and branchId; returns: revenue, expected payments, debt students, active students, new leads, open tasks, overdue tasks, trial lessons, schedule issues, room-load lessons, staff activity count (audit events). Requires manager/admin.
- **GET /analytics/funnel** — Lead pipeline funnel: counts distinct leads that entered each `lead_status` (ordered by `sort_order`) in the given date window and branch. Computes `ratioToPrevStage` (volume ratio; can exceed 100%). Default window: last 90 days. Requires manager/admin.
- **GET /analytics/branches** — Cross-branch comparison for a date range: revenue (payments), active students, new leads, completed lessons — one row per branch. Requires manager/admin.
- **GET /analytics/loss-reasons** — Reasons why leads reached terminal statuses; groups by `lead_loss_reasons`; also counts leads with `reason_id IS NULL` (unspecified). Historical fidelity: no `deleted_at` filter on the reasons table. Requires manager/admin.
- **GET /analytics/debts** — Overdue expected payments bucketed as 0–7, 8–14, 15–30, 30+ days past due; per bucket: student count + amount sum. Also returns overall `distinctStudents` and `totalAmount`. Snapshot query (no date range). Optional branchId filter. Requires manager/admin.
- **GET /analytics/forecast** — Revenue forecast: sum of pending/open expected-payment amounts due within next 7, 14, and 30 days. Snapshot query. Optional branchId. Requires manager/admin.
- **GET /analytics/churn-risk** — Lists active students with no completed lesson within `inactiveDays` (default 21); includes students who have never had a completed lesson (`last_completed_at IS NULL`). Excludes absent/missed/no_show lesson participations. Capped at 200 rows. Requires manager/admin.
- **GET /analytics/weekly-report** — Composite report: fires `Promise.allSettled` over funnel, debts, forecast, churnRisk (summary only — no student list), branchComparison, lossReasons, chatsSla. Window is always last 7 days. Each sub-report is independently fault-tolerant (returns `{error: "..."}` on failure). Requires manager/admin.
- **GET /analytics/chats/sla** — Chat SLA stats for `type = 'administration'` chats only (branch attribution not implemented). Computes: inbound count (client message opening a turn), responded count, avg/median/p90 first-response time in minutes. Not branch-scoped by design. Requires manager/admin.
- **GET /analytics/finance/monthly** — Monthly finance summary from materialized view `app.mv_finance_monthly`: month_start, lessons, completed_lessons, revenue, expenses, new_students. Date range filterable. Requires manager/admin.
- **GET /analytics/finance/monthly.csv** — Same data as finance/monthly, serialized as RFC-4180 CSV. Sets `Content-Disposition: attachment`. Requires manager/admin.
- **GET /analytics/finance/monthly.xlsx** — Same data, serialized as dependency-free SpreadsheetML 2003 XML (not real `.xlsx`). Served with `application/vnd.ms-excel` and `.xls` filename so Excel opens it natively. Requires manager/admin.
- **GET /analytics/sources** — Leads grouped by `source` field with display name resolution from `app.lead_sources` (matched case-insensitively by canonical or display name). Returns count and percentage share. Optional date range and branchId. Requires manager/admin.
- **GET /analytics/data-quality** — Counts data gaps: leads missing phone or branch; students missing branch or discipline (via `student_disciplines` table). Optional branchId. Requires manager/admin.
- **GET /analytics/responsible** — Lead count grouped by assigned-to user for the date range. Separately counts unassigned leads. Optional branchId. Requires manager/admin.

### Finance endpoints (`/crm/*`)

- **GET /crm/reports/finance** — Full finance report: monthly breakdown (revenue, expenses, lesson counts, new students), per-teacher completed lessons + revenue, per-room lesson counts. Revenue per teacher is estimated from group price or `custom_data.individualPrice / individual_price`. No branch filter. Requires manager/admin.
- **GET /crm/payments** — Paginated list of actual payments; filtered by studentId, date range; returns page items plus period totals (`totalAmount`, `totalCount`) over the full filtered set. Manager/admin see all; client sees own student payments only.
- **POST /crm/payments** — Create a payment record for a student. Fields: studentId, amount, currency (default RUB), paymentDate, method, externalId, notes. Creates audit event `crm.payment_created`. Requires manager/admin.
- **GET /crm/expected-payments** — Paginated per-student expected payments (requires `studentId`). Ordered by due_date desc. Accessible by the student's own user, their teachers, or manager/admin.
- **GET /crm/student-balances** — Student balance report: total_paid − total_cost (lesson costs from group price or custom_data price field). Filterable by `debtOnly`, studentId, branchId. Requires manager/admin. (Inline CTE, not the matview.)
- **GET /crm/subscriptions** — Lists student subscriptions (lessons_total, lessons_used, starts_at, expires_at, status). Requires manager/admin.

### Task endpoints (`/crm/*`)

- **GET /crm/tasks** — Task board query. Filters: q (full-text over title/description/entity name), entityType, entityId, studentId, assignedTo, createdBy, branchId, status, priority, taskType, communicationMethod, from/to (due_at range). Limit 1–100 (default 50). Branch resolution works via student/lead branch or group/lesson branch_id. Role visibility: manager/admin see all; teacher sees only tasks assigned to them; client sees only tasks on their own student record.
- **POST /crm/tasks** — Create a task. Required: entityType (student|teacher|group|lesson|lead|profile), entityId, title. Optional: assignedTo, description, status (default 'open'), dueAt. Creates audit event `crm.task_created`. Requires manager/admin.
- **PATCH /crm/tasks/:id** — Update a task (all fields optional, COALESCE merge). Creates audit event `crm.task_updated`. Requires manager/admin.
- _(No DELETE for tasks — soft-delete only via status or manual DB operation; no endpoint exposed.)_

### Background refresh worker

- **AnalyticsRefreshWorker** — Runs every 5 minutes via `setInterval`. Uses `analytics_refresh_runs` table as a distributed lock: inserts a 'running' row only if no completed run in the last 1 hour and no running run in the last 10 minutes. On success, refreshes `mv_finance_monthly`, `mv_teacher_performance`, `mv_room_load` sequentially (not concurrently). On failure, marks the run as 'failed' with error message. `timer.unref()` called so the worker does not block Node.js process shutdown.

---

## 3. Per-role behavior / permissions

| Role | Analytics endpoints | Finance (read) | Finance (write) | Tasks (read) | Tasks (write) |
|---|---|---|---|---|---|
| `system_admin` | Full access | Full access | Allowed | Full (all tasks) | Allowed |
| `admin` | Full access | Full access | Allowed | Full (all tasks) | Allowed |
| `manager` | Full access | Full access | Allowed | Full (all tasks) | Allowed |
| `teacher` | Blocked (`assertCanWriteCrm` throws) | Blocked | Blocked | Only tasks assigned to self | Blocked |
| `client` | Blocked | Own student's payments only | Blocked | Only tasks on own student entity | Blocked |

Permission method `assertCanWriteCrm` rejects with HTTP 403 for any role not in `(manager, admin, system_admin)`. The isManagerOrAdminRole helper covers all three. There is no separate read-only analytics role.

---

## 4. Data / schema touched

### Tables read

| Table | Used by |
|---|---|
| `app.lead_status_history` | funnel, lossReasons |
| `app.lead_statuses` | funnel, lossReasons, leadBoard |
| `app.lead_loss_reasons` | lossReasons |
| `app.leads` | branchComparison, debts (via students), responsibleDistribution, sourceAnalytics, dataQuality, leadBoard |
| `app.lead_sources` | sourceAnalytics |
| `app.payments` | branchComparison, financeReport, listPayments |
| `app.expected_payments` | debts, revenueForecast, dashboard, listExpectedPayments |
| `app.students` | branchComparison, churnRisk, debts, revenueForecast, dashboard, dataQuality, studentBalances |
| `app.student_balances` | dashboard (debt_students count) |
| `app.student_disciplines` | dataQuality |
| `app.lessons` | branchComparison, churnRisk, financeReport, dashboard, listLessons |
| `app.lesson_participation` | churnRisk |
| `app.teachers` | financeReport |
| `app.branches` | branchComparison |
| `app.groups` | financeReport, tasks |
| `app.messages` | chatsSla |
| `app.chats` | chatsSla |
| `app.users` | chatsSla (role classification), responsibleDistribution |
| `app.profiles` | financeReport, tasks |
| `app.tasks` | dashboard, listTasks, overview |
| `app.expenses` | financeReport (read-only; no write endpoint exposed in API) |
| `app.audit_events` | dashboard (staff_activity count) |

### Materialized views read

| View | Refreshed by worker | Used by |
|---|---|---|
| `app.mv_finance_monthly` | Yes (every 1h min) | `GET /analytics/finance/monthly*` |
| `app.mv_teacher_performance` | Yes | (worker refreshes it but no endpoint reads it directly) |
| `app.mv_room_load` | Yes | (worker refreshes it but no endpoint reads it directly) |

### Tables written

| Table | Written by |
|---|---|
| `app.analytics_refresh_runs` | AnalyticsRefreshWorker (insert + update) |
| `app.payments` | `POST /crm/payments` |
| `app.tasks` | `POST /crm/tasks`, `PATCH /crm/tasks/:id` |
| `app.audit_events` | via AuditService on payment/task create/update |

### Branch resolution pattern

Branch is denormalized inconsistently: some entities have a `branch_id` column; others encode it in `custom_data->>'branchId'` or `custom_data->>'branch_id'`. The code uses a consistent helper expression:
```sql
coalesce(alias.branch_id::text, alias.custom_data->>'branchId', alias.custom_data->>'branch_id')
```
This pattern is repeated inline in `analytics.service.ts` (not imported) and in `crm.service.ts`.

---

## 5. Notable business rules / edge cases

1. **Funnel conversion ratio is NOT cohort-based.** `ratioToPrevStage` is the volume of unique leads that entered stage N vs stage N-1 in the same time window — not the same cohort of leads followed through. The ratio can exceed 100% and the comment in the source explicitly acknowledges this.

2. **Churn risk exclusion of absent/missed/no_show participations.** The churn CTE excludes `lesson_participation` rows with status in `('absent', 'missed', 'no_show')`. This means a student who attended zero lessons is treated the same as one who has never had a lesson — both surface in churn risk.

3. **Loss reasons: no deleted_at filter.** The query intentionally omits the `is_active` / `deleted_at` filter on `app.lead_loss_reasons` for historical fidelity. Deleted reasons remain counted as long as they were recorded at time of transition.

4. **Expenses have no write API.** The `app.expenses` table is read in the finance report for a monthly expense total, but there is no exposed endpoint to create, update, or delete expense entries. Manual DB writes or an unimplemented future module would be required.

5. **Debts: bucketStudentSum vs distinctStudents discrepancy is by design.** A student with overdue payments in multiple buckets is counted in each bucket's student count but only once in `distinctStudents`. The response surfaces both so the UI can display the correct total.

6. **Revenue forecast uses `expected_payments`, not actual payments.** It sums future-dated pending/open expected payments, not projected subscription revenue or any other source.

7. **Finance monthly export uses SpreadsheetML 2003, not OOXML.** The `.xlsx` endpoint actually produces `.xml` with a `<?mso-application progid="Excel.Sheet"?>` processing instruction and is served with `application/vnd.ms-excel`. This avoids an `exceljs` dependency but the MIME type and file format are mismatched with the `.xlsx` filename.

8. **Chat SLA is org-wide only.** `chats.branch_id` is not populated; the code comments mark branch-scoped chat SLA as a follow-up. All chat SLA numbers reflect the full org.

9. **Weekly report is fault-tolerant via Promise.allSettled.** If any of the 7 sub-reports throws, the weekly report still returns the rest with `{error: "..."}` in place of the failed section. Churn in the weekly report returns only `{inactiveDays, totalAtRisk}` (not the student list) to keep response size manageable.

10. **Materialized view refresh uses a distributed claim.** The refresh worker inserts a row only if no completed run in the last 1 hour or running run in the last 10 minutes, making it safe to run multiple server instances. However, the claim is NOT transactional with the refresh itself — a crash between the refresh and the `status = 'completed'` update leaves the run in 'running' status, which will unblock after 10 minutes.

11. **Task write operations are manager/admin only; no "teacher manages own tasks" flow.** Teachers can read tasks assigned to them but cannot create or update any task. There is no concept of a teacher self-assigning or closing a task via the API.

12. **No DELETE endpoint for tasks.** Tasks can be set to status `'cancelled'` but there is no soft-delete endpoint. The `tasks.deleted_at` column exists in the schema (the WHERE clause filters it) but nothing in the API sets it.

13. **Student balance uses inline CTE (not the matview `student_balances`).** The dashboard uses `app.student_balances` (presumably a view or pre-computed table) to count debt students, but `GET /crm/student-balances` recomputes the balance with a live CTE over lessons and payments. These may diverge if the view is stale.

14. **Default analytics date range is 90 days.** `rangeBounds()` defaults `from` to 90 days ago and `to` to now. The weekly report overrides this to exactly 7 days. The manager dashboard uses its own `dashboardBounds()` helper.

15. **Branch filter in tasks is resolved indirectly.** The tasks query resolves branch from the linked entity (student → branch, lead → branch, group.branch_id, lesson.branch_id) since tasks themselves have no `branch_id` column. A task linked to a profile entity type cannot be branch-filtered.
