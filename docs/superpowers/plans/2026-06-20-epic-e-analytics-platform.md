# Epic E · Analytics platform (matviews + refresh worker + /analytics + CSV export) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the read-side analytics substrate (F3) — materialized views for the heavy finance rollups, a refresh worker on the project's existing setInterval+claim pattern, a `/analytics/*` read-only namespace, and CSV export — so Epic F's reports read precomputed data instead of hammering OLTP.

**Architecture:** Migration `0031` creates `analytics_refresh_runs` (claim/idempotency) + 3 materialized views (`mv_finance_monthly`, `mv_teacher_performance`, `mv_room_load`) **owned by `magiccrm_app`** (so the app-role worker can `REFRESH` them). An `AnalyticsRefreshWorker` (copied from `NotificationWorker`: `OnModuleInit/OnModuleDestroy` + `setInterval` + a DB claim) refreshes them at most once per refresh-gap. An `AnalyticsModule` (`AnalyticsController` + `AnalyticsService`) exposes `/analytics/*` — overview/dashboard delegate to the existing CRM service; finance reads the matviews — plus a CSV export. F-specific matviews (funnel/retention/student_activity) and XLSX/scheduled-delivery are deferred to Epic F.

**Tech Stack:** NestJS/TypeScript, PostgreSQL (materialized views), Jest. No new npm dependency (CSV is built inline).

**Linear:** KVA-182 (Epic E). Spec §3 F3 / §4E. Depends on Epic A `branch_id` (0027) for branch-scoped reads (delegated dashboard already takes branchId).

## Global Constraints

- Migration id is **`0031_analytics`**.
- Materialized views MUST be reassigned to `magiccrm_app` in the migration (`alter materialized view app.<name> owner to magiccrm_app`, guarded by the role-exists check) so the app-role refresh worker can `REFRESH MATERIALIZED VIEW` them. Non-concurrent refresh (no unique-index requirement).
- `analytics_refresh_runs(id, kind text, status text, claimed_at, ran_at, finished_at, error text)` — the worker claims a run only if no run of that kind finished within the refresh-gap and none is `running` within the stale window.
- The refresh worker copies `NotificationWorker` EXACTLY in shape: `implements OnModuleInit, OnModuleDestroy`; `setInterval(CHECK_INTERVAL_MS)` with `timer.unref?.()`; `clearInterval` on destroy; injected `DatabaseService`; registered in its module's `providers`. CHECK_INTERVAL_MS = 5 min; REFRESH_GAP = 1 hour; STALE = 10 min.
- `AnalyticsModule` mirrors `crm.module.ts` (imports DatabaseModule, AuditModule, JwtModule.register({}); controllers [AnalyticsController]; providers [AnalyticsService, AnalyticsRefreshWorker, JwtAuthGuard]) and is added to `app.module.ts` imports. Routes gate `assertCanReadOperationalData` via the reused `CrmPolicy` (import CrmModule to get it, or inject CrmService for delegation).
- `/analytics/overview` and `/analytics/dashboard` DELEGATE to `CrmService.getOverview` / `getManagerDashboard` (no logic duplication). `/analytics/finance` reads the matviews (date-range-filtered).
- CSV export builds the string inline (RFC-4180 quoting), returned via the `files.controller.ts` streaming pattern (`@Res({ passthrough: true })` + `StreamableFile` + Content-Disposition). No exceljs/papaparse dependency.
- Conventions: schema `app.`; idempotent DDL where possible (matviews use `drop materialized view if exists` then `create` in up; or `create materialized view if not exists`); guarded grants.
- Run from `server/`: migrations `npm run db:migrate`/`db:rollback`; tests `npm test`; types `npm run typecheck`.
- **Prod safety:** validate the migration ONLY on ephemeral Docker (chain 0001..0031 + refresh), NEVER prod, NEVER `server/.env`/`.migration.env`.

---

## File Structure

- **Create** `server/db/migrations/0031_analytics.up.sql` / `.down.sql`.
- **Create** `server/src/analytics/analytics.module.ts`, `analytics.service.ts`, `analytics.controller.ts`, `analytics-refresh.worker.ts`, and specs.
- **Modify** `server/src/app.module.ts` — add `AnalyticsModule` to imports.

---

## Task 1: Migration 0031 — refresh-runs table + 3 materialized views

**Files:**
- Create: `server/db/migrations/0031_analytics.up.sql`
- Create: `server/db/migrations/0031_analytics.down.sql`

**Interfaces (DB):** table `app.analytics_refresh_runs`; matviews `app.mv_finance_monthly`, `app.mv_teacher_performance`, `app.mv_room_load`.

- [ ] **Step 1: Write the up migration**

```sql
-- server/db/migrations/0031_analytics.up.sql
-- Analytics substrate: refresh-run log + finance materialized views (owned by
-- magiccrm_app so the app-role refresh worker can REFRESH them).

create table if not exists app.analytics_refresh_runs (
  id uuid primary key default gen_random_uuid(),
  kind text not null,
  status text not null default 'running',
  claimed_at timestamptz not null default now(),
  ran_at timestamptz,
  finished_at timestamptz,
  error text,
  constraint analytics_refresh_runs_status_check check (status in ('running', 'completed', 'failed'))
);
create index if not exists analytics_refresh_runs_kind_idx
  on app.analytics_refresh_runs (kind, finished_at desc);

drop materialized view if exists app.mv_finance_monthly;
create materialized view app.mv_finance_monthly as
with bounds as (
  select coalesce(min(date_trunc('month', scheduled_at)), date_trunc('month', now())) as min_month
  from app.lessons where deleted_at is null
),
months as (
  select d::date as month_start
  from bounds, generate_series(bounds.min_month, date_trunc('month', now()), interval '1 month') as d
),
lesson_stats as (
  select date_trunc('month', scheduled_at)::date as m, count(*) as lessons,
         count(*) filter (where status in ('completed', 'done')) as completed
  from app.lessons where deleted_at is null group by 1
),
payment_stats as (
  select date_trunc('month', payment_date)::date as m, sum(amount) as revenue
  from app.payments where deleted_at is null group by 1
),
expense_stats as (
  select date_trunc('month', created_at)::date as m, sum(amount) as expenses
  from app.expenses where deleted_at is null group by 1
),
student_stats as (
  select date_trunc('month', created_at)::date as m, count(*) as new_students
  from app.students where deleted_at is null group by 1
)
select mo.month_start,
       coalesce(ls.lessons, 0) as lessons,
       coalesce(ls.completed, 0) as completed_lessons,
       coalesce(ps.revenue, 0) as revenue,
       coalesce(es.expenses, 0) as expenses,
       coalesce(ss.new_students, 0) as new_students
from months mo
left join lesson_stats ls on ls.m = mo.month_start
left join payment_stats ps on ps.m = mo.month_start
left join expense_stats es on es.m = mo.month_start
left join student_stats ss on ss.m = mo.month_start
order by mo.month_start;
create index if not exists mv_finance_monthly_month_idx on app.mv_finance_monthly (month_start);

drop materialized view if exists app.mv_teacher_performance;
create materialized view app.mv_teacher_performance as
select l.teacher_id,
       btrim(concat_ws(' ', tp.first_name, tp.last_name)) as teacher_name,
       count(*) filter (where l.status in ('completed', 'done')) as completed_lessons,
       coalesce(sum(g.price_per_lesson) filter (where l.status in ('completed', 'done')), 0) as revenue
from app.lessons l
left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
left join app.groups g on g.id = l.group_id and g.deleted_at is null
where l.deleted_at is null and l.teacher_id is not null
group by l.teacher_id, tp.first_name, tp.last_name;
create index if not exists mv_teacher_performance_teacher_idx on app.mv_teacher_performance (teacher_id);

drop materialized view if exists app.mv_room_load;
create materialized view app.mv_room_load as
select l.room_id, r.name as room_name, count(*) as lessons
from app.lessons l
left join app.rooms r on r.id = l.room_id and r.deleted_at is null
where l.deleted_at is null and l.room_id is not null
group by l.room_id, r.name;
create index if not exists mv_room_load_room_idx on app.mv_room_load (room_id);

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert, update, delete on app.analytics_refresh_runs to magiccrm_app;
    alter materialized view app.mv_finance_monthly owner to magiccrm_app;
    alter materialized view app.mv_teacher_performance owner to magiccrm_app;
    alter materialized view app.mv_room_load owner to magiccrm_app;
  end if;
end $$;
```

> Note: `price_per_lesson` is summed only for completed lessons (mirrors getFinanceReport's revenue intent; the individual-price jsonb path is omitted from the matview for simplicity — document as a known approximation). If `app.groups` has no `price_per_lesson` column, the implementer confirms the real column during validation and adjusts, reporting it.

- [ ] **Step 2: Write the down migration**

```sql
-- server/db/migrations/0031_analytics.down.sql
drop materialized view if exists app.mv_room_load;
drop materialized view if exists app.mv_teacher_performance;
drop materialized view if exists app.mv_finance_monthly;
drop table if exists app.analytics_refresh_runs;
```

- [ ] **Step 3: Validate on ephemeral Docker (apply + REFRESH + select + reversibility)**

```bash
docker run --rm -d --name mmcrm-e-pg -e POSTGRES_PASSWORD=test -e POSTGRES_DB=mmcrm_test -p 55441:5432 postgres:16
# wait ready; create role:
docker exec mmcrm-e-pg psql -U postgres -d mmcrm_test -c "create role magiccrm_app login password 'x'" || true
URL='postgres://postgres:test@localhost:55441/mmcrm_test'
cd server && MIGRATION_DATABASE_URL="$URL" DATABASE_URL="$URL" npm run db:migrate   # incl 0031
# Matviews exist + are owned by magiccrm_app + refreshable:
docker exec mmcrm-e-pg psql -U postgres -d mmcrm_test -c "select matviewname, matviewowner from pg_matviews where schemaname='app' order by 1;"   # 3 rows owned by magiccrm_app
docker exec mmcrm-e-pg psql -U postgres -d mmcrm_test -c "refresh materialized view app.mv_finance_monthly; refresh materialized view app.mv_teacher_performance; refresh materialized view app.mv_room_load; select 'refreshed';"
docker exec mmcrm-e-pg psql -U postgres -d mmcrm_test -c "select count(*) from app.mv_finance_monthly;"   # 0 on empty DB, no error
# Refresh AS magiccrm_app (the real worker role) — must succeed because it owns them:
docker exec mmcrm-e-pg psql -U magiccrm_app -d mmcrm_test -c "refresh materialized view app.mv_finance_monthly; select 'app-role-refresh-ok';"
# reversibility:
cd server && MIGRATION_DATABASE_URL="$URL" DATABASE_URL="$URL" npm run db:migrate     # none
cd server && MIGRATION_DATABASE_URL="$URL" DATABASE_URL="$URL" npm run db:rollback    # Reverted 0031_analytics
docker exec mmcrm-e-pg psql -U postgres -d mmcrm_test -c "select to_regclass('app.mv_finance_monthly');"  # NULL
cd server && MIGRATION_DATABASE_URL="$URL" DATABASE_URL="$URL" npm run db:migrate      # re-apply
docker stop mmcrm-e-pg
```
Expected: 3 matviews owned by `magiccrm_app`; the `magiccrm_app`-role REFRESH succeeds (proves the owner reassignment); counts are 0 on the empty DB without error; rollback drops all; re-apply clean. If `magiccrm_app` cannot be created with login in your environment, the ownership check still holds via `pg_matviews.matviewowner = 'magiccrm_app'` from the postgres-role query.

- [ ] **Step 4: Commit**

```bash
git add server/db/migrations/0031_analytics.up.sql server/db/migrations/0031_analytics.down.sql
git commit -m "feat(db): analytics refresh-runs + finance materialized views (KVA-182)"
```

---

## Task 2: Analytics module + refresh worker

**Files:**
- Create: `server/src/analytics/analytics-refresh.worker.ts`, `analytics-refresh.worker.spec.ts`, `analytics.module.ts`
- Modify: `server/src/app.module.ts`

**Interfaces:**
- Produces: `AnalyticsRefreshWorker` (`OnModuleInit`/`OnModuleDestroy`, `refreshNow(): Promise<{ refreshed: boolean }>`); `AnalyticsModule`.

- [ ] **Step 1: Write the failing test**

```typescript
// server/src/analytics/analytics-refresh.worker.spec.ts
import { AnalyticsRefreshWorker } from "./analytics-refresh.worker";
import { DatabaseService } from "../db/database.service";

describe("AnalyticsRefreshWorker", () => {
  const build = (claimRows: Record<string, unknown>[]) => {
    const query = jest.fn();
    query.mockResolvedValueOnce({ rows: claimRows }); // claim insert
    query.mockResolvedValue({ rows: [] });            // refreshes + finalize
    const worker = new AnalyticsRefreshWorker({ query } as unknown as DatabaseService);
    return { worker, query };
  };

  it("refreshes the matviews when it wins the claim", async () => {
    const { worker, query } = build([{ id: "run-1" }]);
    const result = await worker.refreshNow();
    expect(result).toEqual({ refreshed: true });
    const sql = query.mock.calls.map((c) => String(c[0])).join("\n");
    expect(sql).toContain("insert into app.analytics_refresh_runs");
    expect(sql).toContain("refresh materialized view app.mv_finance_monthly");
    expect(sql).toContain("update app.analytics_refresh_runs");
  });

  it("skips when another run holds the claim (no row returned)", async () => {
    const { worker, query } = build([]); // claim insert returns nothing
    const result = await worker.refreshNow();
    expect(result).toEqual({ refreshed: false });
    const sql = query.mock.calls.map((c) => String(c[0])).join("\n");
    expect(sql).not.toContain("refresh materialized view");
  });
});
```

- [ ] **Step 2: Run to verify failure**

Run: `cd server && npx jest src/analytics/analytics-refresh.worker.spec.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement the worker**

```typescript
// server/src/analytics/analytics-refresh.worker.ts
import { Injectable, OnModuleDestroy, OnModuleInit } from "@nestjs/common";
import { DatabaseService } from "../db/database.service";

const CHECK_INTERVAL_MS = 5 * 60_000;
const MATVIEWS = ["mv_finance_monthly", "mv_teacher_performance", "mv_room_load"] as const;

@Injectable()
export class AnalyticsRefreshWorker implements OnModuleInit, OnModuleDestroy {
  private timer: ReturnType<typeof setInterval> | null = null;

  constructor(private readonly database: DatabaseService) {}

  onModuleInit(): void {
    this.timer = setInterval(() => {
      void this.refreshNow().catch(() => undefined);
    }, CHECK_INTERVAL_MS);
    this.timer.unref?.();
  }

  onModuleDestroy(): void {
    if (this.timer) clearInterval(this.timer);
  }

  // Claim a refresh run (idempotent across instances/intervals); refresh the
  // matviews only if this caller wins the claim.
  async refreshNow(): Promise<{ refreshed: boolean }> {
    const claim = await this.database.query<{ id: string }>(
      `insert into app.analytics_refresh_runs (kind, status)
       select 'matviews', 'running'
       where not exists (
         select 1 from app.analytics_refresh_runs
          where kind = 'matviews'
            and (
              (status = 'completed' and finished_at > now() - interval '1 hour')
              or (status = 'running' and claimed_at > now() - interval '10 minutes')
            )
       )
       returning id`,
    );
    const runId = claim.rows[0]?.id;
    if (!runId) return { refreshed: false };
    try {
      for (const mv of MATVIEWS) {
        await this.database.query(`refresh materialized view app.${mv}`);
      }
      await this.database.query(
        `update app.analytics_refresh_runs set status = 'completed', ran_at = now(), finished_at = now() where id = $1`,
        [runId],
      );
      return { refreshed: true };
    } catch (error) {
      await this.database.query(
        `update app.analytics_refresh_runs set status = 'failed', finished_at = now(), error = $2 where id = $1`,
        [runId, error instanceof Error ? error.message : String(error)],
      );
      throw error;
    }
  }
}
```

- [ ] **Step 4: Run the test to verify pass**

Run: `cd server && npx jest src/analytics/analytics-refresh.worker.spec.ts`
Expected: PASS (2 tests).

- [ ] **Step 5: Create the module + register it**

```typescript
// server/src/analytics/analytics.module.ts
import { Module } from "@nestjs/common";
import { JwtModule } from "@nestjs/jwt";
import { AuditModule } from "../audit/audit.module";
import { DatabaseModule } from "../db/database.module";
import { CrmModule } from "../crm/crm.module";
import { AnalyticsController } from "./analytics.controller";
import { AnalyticsService } from "./analytics.service";
import { AnalyticsRefreshWorker } from "./analytics-refresh.worker";
import { JwtAuthGuard } from "../auth/jwt-auth.guard";

@Module({
  imports: [DatabaseModule, AuditModule, CrmModule, JwtModule.register({})],
  controllers: [AnalyticsController],
  providers: [AnalyticsService, AnalyticsRefreshWorker, JwtAuthGuard],
})
export class AnalyticsModule {}
```

(`AnalyticsController`/`AnalyticsService` come in Task 3 — this module will not compile until then; the implementer creates Task-3 files in the same task sequence OR stubs them. To keep Task 2 self-contained, create minimal empty `analytics.controller.ts` (`@Controller("analytics")` empty) and `analytics.service.ts` (`@Injectable()` empty class) now, fleshed out in Task 3. Import `CrmModule` so Task 3 can inject `CrmService`/`CrmPolicy` — ensure `crm.module.ts` exports them; if `CrmPolicy` isn't exported, add it to crm.module's exports.)

Add to `server/src/app.module.ts` imports (after the CrmModule import line):
```typescript
import { AnalyticsModule } from "./analytics/analytics.module";
// ... and add `AnalyticsModule,` to the @Module imports array.
```

- [ ] **Step 6: Typecheck + suite**

Run: `cd server && npm run typecheck && npm test`
Expected: typecheck 0 (with the Task-3 stubs present); worker tests pass; full suite green; the Nest app still boots (app.module compiles with AnalyticsModule).

- [ ] **Step 7: Commit**

```bash
git add server/src/analytics/analytics-refresh.worker.ts server/src/analytics/analytics-refresh.worker.spec.ts server/src/analytics/analytics.module.ts server/src/analytics/analytics.controller.ts server/src/analytics/analytics.service.ts server/src/app.module.ts
git commit -m "feat(analytics): refresh worker + module (setInterval+claim) (KVA-182)"
```

---

## Task 3: /analytics namespace + finance read + CSV export

**Files:**
- Modify: `server/src/analytics/analytics.service.ts`, `analytics.controller.ts`
- Create: `server/src/analytics/analytics.service.spec.ts`

**Interfaces:**
- Produces:
  - `AnalyticsService.financeMonthly(actor, { from?, to? }): Promise<{ items: Array<{ monthStart; lessons; completedLessons; revenue; expenses; newStudents }> }>` (reads `mv_finance_monthly`).
  - `AnalyticsService.financeMonthlyCsv(actor, query): Promise<string>` (RFC-4180 CSV of the same).
  - Routes: `GET /analytics/overview` (→ CrmService.getOverview), `GET /analytics/dashboard` (→ CrmService.getManagerDashboard), `GET /analytics/finance/monthly`, `GET /analytics/finance/monthly.csv` (download).

- [ ] **Step 1: Write the failing tests**

```typescript
// server/src/analytics/analytics.service.spec.ts
import { AnalyticsService } from "./analytics.service";
import { DatabaseService } from "../db/database.service";
import { CrmService } from "../crm/crm.service";
import { CrmPolicy } from "../crm/crm.policy";

describe("AnalyticsService", () => {
  const actor = { userId: "u1", role: "manager" as const };
  const build = (rows: Record<string, unknown>[]) => {
    const query = jest.fn().mockResolvedValue({ rows });
    const policy = { assertCanReadOperationalData: jest.fn() };
    const crm = {} as unknown as CrmService;
    const service = new AnalyticsService(
      { query } as unknown as DatabaseService,
      crm,
      policy as unknown as CrmPolicy,
    );
    return { service, query, policy };
  };

  it("reads finance monthly from the matview with a date filter", async () => {
    const { service, query, policy } = build([
      { month_start: "2026-06-01", lessons: 10, completed_lessons: 8, revenue: 5000, expenses: 1200, new_students: 3 },
    ]);
    const result = await service.financeMonthly(actor, { from: "2026-01-01", to: "2026-07-01" });
    expect(result.items[0]).toEqual({
      monthStart: "2026-06-01", lessons: 10, completedLessons: 8, revenue: 5000, expenses: 1200, newStudents: 3,
    });
    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("app.mv_finance_monthly");
  });

  it("renders finance monthly as RFC-4180 CSV with a header row", async () => {
    const { service } = build([
      { month_start: "2026-06-01", lessons: 10, completed_lessons: 8, revenue: 5000, expenses: 1200, new_students: 3 },
    ]);
    const csv = await service.financeMonthlyCsv(actor, {});
    const lines = csv.trim().split("\n");
    expect(lines[0]).toBe("month_start,lessons,completed_lessons,revenue,expenses,new_students");
    expect(lines[1]).toBe("2026-06-01,10,8,5000,1200,3");
  });
});
```

- [ ] **Step 2: Run to verify failure**

Run: `cd server && npx jest src/analytics/analytics.service.spec.ts`
Expected: FAIL — `financeMonthly is not a function`.

- [ ] **Step 3: Implement the service**

```typescript
// server/src/analytics/analytics.service.ts
import { Injectable } from "@nestjs/common";
import { DatabaseService } from "../db/database.service";
import { CrmService } from "../crm/crm.service";
import { CrmPolicy } from "../crm/crm.policy";
import type { ActorContext } from "../crm/crm.service";

@Injectable()
export class AnalyticsService {
  constructor(
    private readonly database: DatabaseService,
    private readonly crm: CrmService,
    private readonly policy: CrmPolicy,
  ) {}

  overview(actor: ActorContext) {
    return this.crm.getOverview(actor);
  }

  dashboard(actor: ActorContext, query: Parameters<CrmService["getManagerDashboard"]>[1]) {
    return this.crm.getManagerDashboard(actor, query);
  }

  async financeMonthly(actor: ActorContext, query: { from?: string; to?: string }) {
    this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<{
      month_start: string;
      lessons: number;
      completed_lessons: number;
      revenue: number;
      expenses: number;
      new_students: number;
    }>(
      `select month_start, lessons, completed_lessons, revenue, expenses, new_students
         from app.mv_finance_monthly
        where ($1::date is null or month_start >= $1::date)
          and ($2::date is null or month_start < $2::date)
        order by month_start`,
      [query.from ?? null, query.to ?? null],
    );
    return {
      items: result.rows.map((r) => ({
        monthStart: r.month_start,
        lessons: Number(r.lessons),
        completedLessons: Number(r.completed_lessons),
        revenue: Number(r.revenue),
        expenses: Number(r.expenses),
        newStudents: Number(r.new_students),
      })),
    };
  }

  async financeMonthlyCsv(actor: ActorContext, query: { from?: string; to?: string }): Promise<string> {
    const { items } = await this.financeMonthly(actor, query);
    const header = "month_start,lessons,completed_lessons,revenue,expenses,new_students";
    const escape = (v: unknown) => {
      const s = String(v ?? "");
      return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
    };
    const lines = items.map((i) =>
      [i.monthStart, i.lessons, i.completedLessons, i.revenue, i.expenses, i.newStudents].map(escape).join(","),
    );
    return [header, ...lines].join("\n") + "\n";
  }
}
```

> If `ActorContext` is not exported from `crm.service.ts`, import it from wherever it is defined (check the existing imports in `crm.controller.ts`).

- [ ] **Step 4: Implement the controller**

```typescript
// server/src/analytics/analytics.controller.ts
import { Controller, Get, Query, Res, StreamableFile, UseGuards } from "@nestjs/common";
import type { Response } from "express";
import { AnalyticsService } from "./analytics.service";
import { JwtAuthGuard } from "../auth/jwt-auth.guard";
import { CurrentActor } from "../auth/current-actor.decorator";
import type { ActorContext } from "../crm/crm.service";

@Controller("analytics")
@UseGuards(JwtAuthGuard)
export class AnalyticsController {
  constructor(private readonly analytics: AnalyticsService) {}

  @Get("overview")
  overview(@CurrentActor() actor: ActorContext) {
    return this.analytics.overview(actor);
  }

  @Get("dashboard")
  dashboard(@CurrentActor() actor: ActorContext, @Query() query: Record<string, string>) {
    return this.analytics.dashboard(actor, query as never);
  }

  @Get("finance/monthly")
  financeMonthly(@CurrentActor() actor: ActorContext, @Query() query: { from?: string; to?: string }) {
    return this.analytics.financeMonthly(actor, query);
  }

  @Get("finance/monthly.csv")
  async financeMonthlyCsv(
    @CurrentActor() actor: ActorContext,
    @Query() query: { from?: string; to?: string },
    @Res({ passthrough: true }) res: Response,
  ): Promise<StreamableFile> {
    const csv = await this.analytics.financeMonthlyCsv(actor, query);
    res.setHeader("Content-Type", "text/csv; charset=utf-8");
    res.setHeader("Content-Disposition", 'attachment; filename="finance-monthly.csv"');
    return new StreamableFile(Buffer.from(csv, "utf-8"));
  }
}
```

> Confirm the import paths for `JwtAuthGuard`, `CurrentActor`, and `ActorContext` against how `crm.controller.ts` imports them — copy those exact paths.

- [ ] **Step 5: Run tests + typecheck**

Run: `cd server && npm run typecheck && npm test`
Expected: typecheck 0; the analytics service tests pass; full suite green.

- [ ] **Step 6: Commit**

```bash
git add server/src/analytics/analytics.service.ts server/src/analytics/analytics.controller.ts server/src/analytics/analytics.service.spec.ts
git commit -m "feat(analytics): /analytics namespace (overview/dashboard delegate, finance matview read + CSV) (KVA-182)"
```

---

## Self-Review

- **Spec coverage (§4E):** `analytics_refresh_runs` + 3 finance matviews ✅ (Task 1); refresh worker on the notification-worker setInterval+claim pattern ✅ (Task 2); `/analytics/*` namespace (overview/dashboard delegate, finance from matview) ✅ (Task 3); CSV export ✅ (Task 3). Matviews ARE the cache (E4). XLSX (exceljs), scheduled weekly delivery (E6), and the F-specific matviews (funnel/retention/student_activity) are deferred to Epic F. Snapshot-table metrics (`daily_analytics_snapshots`) deferred — matviews cover the heavy finance reads now.
- **Placeholder scan:** none — full SQL/TS/tests + exact commands.
- **Permission correctness:** matviews reassigned to `magiccrm_app` so the app-role worker can REFRESH (validated by the `magiccrm_app`-role refresh in Task 1 Step 3).
- **No logic duplication:** overview/dashboard delegate to `CrmService`; only finance reads the precomputed matview.
- **Idempotent refresh:** the claim insert prevents concurrent/over-frequent refreshes (tested both win and skip paths).

## Dependency note

Epic E is the read-side substrate for Epic F: F's reports read these matviews (and add funnel/retention/student_activity matviews + the `daily_analytics_snapshots` rollups + XLSX + scheduled weekly delivery on the same `analytics_refresh_runs` worker). Migration `0031` is applied to prod later, batched with the Epic A migrations (after which the worker begins refreshing). The matview revenue uses `groups.price_per_lesson` for completed lessons — a documented approximation of `getFinanceReport`'s revenue (which also considers an individual-price jsonb path); F can refine if needed.
