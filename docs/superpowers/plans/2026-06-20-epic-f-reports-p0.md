# Epic F · P0 management reports (funnel, branch comparison, loss reasons) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the three highest-value management reports on top of the Epic-A data and the Epic-E `/analytics` namespace — a lead conversion funnel (from `lead_status_history`), a branch comparison, and a loss-reasons breakdown — each as a gated, date-ranged, read-only endpoint.

**Architecture:** Three new `AnalyticsService` methods (live SQL, no new tables) + three `AnalyticsController` routes under the existing `/analytics` namespace, each gated to manager/admin via `CrmPolicy.assertCanWriteCrm`. A shared private `rangeBounds(query)` resolves an optional `from`/`to` to a concrete range (default last 90 days). Funnel and loss-reasons read `app.lead_status_history` (A5); branch comparison reads the unified `branch_id` columns (A4) using the same `branchIdExpr` coalesce the CRM dashboard uses.

**Tech Stack:** NestJS/TypeScript, PostgreSQL, Jest. No migration, no new dependency.

**Linear:** KVA-183 (Epic F). Spec §4F. Depends on A4 (`branch_id`), A5 (`lead_status_history`), A6 (`lead_loss_reasons`, `lead_statuses.is_terminal`) — all merged.

## Global Constraints

- All three methods gate `this.policy.assertCanWriteCrm(actor)` FIRST (these are management revenue/operational reports — manager/admin only, matching `getManagerDashboard`/`getFinanceReport`).
- `rangeBounds(query: { from?: string; to?: string }): { from: string; to: string }` — if `from`/`to` are provided, use them; else default `to = now`, `from = now − 90 days` (ISO strings). Defined once (Task 1), reused by Tasks 2 & 3.
- Branch filtering on `lead_status_history` uses its own `branch_id` column directly (`lsh.branch_id = $n::uuid`). Branch comparison reads students'/leads' branch via the coalesce expression `coalesce(<a>.branch_id::text, <a>.custom_data->>'branchId', <a>.custom_data->>'branch_id')` (mirror of `CrmService.branchIdExpr`, inlined — document the mirror); `payments` join through students; `lessons` use `l.branch_id` directly (as `getManagerDashboard` does).
- Terminal statuses identified by `lead_statuses.is_terminal = true` (NOT by name/color).
- All SQL uses parameterized placeholders; date params cast `::timestamptz`, branch params `::uuid`. Half-open ranges `>= from and < to`.
- Numeric DB outputs coerced with `Number(...)` in the mapping (counts come back as strings).
- New endpoints live on the existing `AnalyticsController` (`@Controller("analytics")`, `@UseGuards(JwtAuthGuard)`); import `ActorContext`/`CurrentActor` from `../common/security/...` (already imported there).
- Run from `server/`: tests `npm test`; types `npm run typecheck`.

---

## File Structure

- **Modify** `server/src/analytics/analytics.service.ts` — `rangeBounds`, `funnel`, `branchComparison`, `lossReasons`.
- **Modify** `server/src/analytics/analytics.controller.ts` — `GET /analytics/funnel`, `/analytics/branches`, `/analytics/loss-reasons`.
- **Modify** `server/src/analytics/analytics.service.spec.ts` — tests for all three.

---

## Task 1: Conversion funnel

**Files:**
- Modify: `server/src/analytics/analytics.service.ts`, `analytics.controller.ts`, `analytics.service.spec.ts`

**Interfaces:**
- Produces: `rangeBounds(query)` (private, reused by Tasks 2 & 3); `funnel(actor, { from?, to?, branchId? })`; route `GET /analytics/funnel`.

- [ ] **Step 1: Write the failing tests**

Add to `server/src/analytics/analytics.service.spec.ts` (mirror the existing `build(rows)` harness that mocks `database.query`, `policy`, `crm`):

```typescript
  it("funnel returns stage counts ordered by sort_order, gated to manager/admin", async () => {
    const { service, query, policy } = build([
      { status_id: "s1", name: "Новый", sort_order: 0, leads_entered: "100" },
      { status_id: "s2", name: "Пробный", sort_order: 1, leads_entered: "40" },
    ]);
    const result = await service.funnel(actor, { from: "2026-01-01", to: "2026-04-01" });
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("app.lead_status_history");
    expect(result.stages).toEqual([
      { statusId: "s1", name: "Новый", sortOrder: 0, leadsEntered: 100, conversionFromPrev: null },
      { statusId: "s2", name: "Пробный", sortOrder: 1, leadsEntered: 40, conversionFromPrev: 40 },
    ]);
  });
```

> The `build` helper's `policy` mock must include `assertCanWriteCrm: jest.fn()` (add it if the existing helper only mocked `assertCanReadOperationalData`).

- [ ] **Step 2: Run to verify failure**

Run: `cd server && npx jest src/analytics/analytics.service.spec.ts -t funnel`
Expected: FAIL — `service.funnel is not a function`.

- [ ] **Step 3: Implement `rangeBounds` + `funnel`**

Add to `AnalyticsService` (import `ActorContext` if not already imported):

```typescript
  private rangeBounds(query: { from?: string; to?: string }): { from: string; to: string } {
    const to = query.to ?? new Date().toISOString();
    const from =
      query.from ?? new Date(Date.now() - 90 * 24 * 60 * 60 * 1000).toISOString();
    return { from, to };
  }

  async funnel(actor: ActorContext, query: { from?: string; to?: string; branchId?: string }) {
    this.policy.assertCanWriteCrm(actor);
    const { from, to } = this.rangeBounds(query);
    const result = await this.database.query<{
      status_id: string;
      name: string;
      sort_order: number;
      leads_entered: string;
    }>(
      `select ls.id as status_id, ls.name, ls.sort_order,
              count(distinct lsh.lead_id) as leads_entered
         from app.lead_status_history lsh
         join app.lead_statuses ls on ls.id = lsh.new_status_id
        where lsh.new_status_id is not null
          and lsh.changed_at >= $1::timestamptz
          and lsh.changed_at < $2::timestamptz
          and ($3::uuid is null or lsh.branch_id = $3::uuid)
        group by ls.id, ls.name, ls.sort_order
        order by ls.sort_order`,
      [from, to, query.branchId ?? null],
    );
    let prev: number | null = null;
    const stages = result.rows.map((r) => {
      const leadsEntered = Number(r.leads_entered);
      const conversionFromPrev =
        prev === null || prev === 0 ? (prev === null ? null : 0) : Math.round((leadsEntered / prev) * 100);
      prev = leadsEntered;
      return { statusId: r.status_id, name: r.name, sortOrder: r.sort_order, leadsEntered, conversionFromPrev };
    });
    return { from, to, stages };
  }
```

> `conversionFromPrev` is the percentage of the previous stage's entrants (null for the first stage). It's a stage-over-stage ratio of distinct leads that entered each status in the window — document it as such (not a per-lead cohort progression).

- [ ] **Step 4: Add the controller route**

Add to `AnalyticsController`:
```typescript
  @Get("funnel")
  funnel(
    @CurrentActor() actor: ActorContext,
    @Query() query: { from?: string; to?: string; branchId?: string },
  ) {
    return this.analytics.funnel(actor, query);
  }
```

- [ ] **Step 5: Run tests + typecheck**

Run: `cd server && npm run typecheck && npm test`
Expected: typecheck 0; the funnel test passes; full suite green.

- [ ] **Step 6: Commit**

```bash
git add server/src/analytics/analytics.service.ts server/src/analytics/analytics.controller.ts server/src/analytics/analytics.service.spec.ts
git commit -m "feat(analytics): conversion funnel report from lead_status_history (KVA-183)"
```

---

## Task 2: Branch comparison

**Files:**
- Modify: `server/src/analytics/analytics.service.ts`, `analytics.controller.ts`, `analytics.service.spec.ts`

**Interfaces:**
- Consumes: `rangeBounds` (Task 1).
- Produces: `branchComparison(actor, { from?, to? })`; route `GET /analytics/branches`.

- [ ] **Step 1: Write the failing test**

```typescript
  it("branchComparison returns per-branch metrics, gated to manager/admin", async () => {
    const { service, query, policy } = build([
      { branch_id: "b1", name: "Сокол", revenue: "500000", active_students: "120", new_leads: "30", completed_lessons: "800" },
    ]);
    const result = await service.branchComparison(actor, { from: "2026-01-01", to: "2026-04-01" });
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("app.branches");
    expect(result.branches).toEqual([
      { branchId: "b1", name: "Сокол", revenue: 500000, activeStudents: 120, newLeads: 30, completedLessons: 800 },
    ]);
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `cd server && npx jest src/analytics/analytics.service.spec.ts -t branchComparison`
Expected: FAIL — `service.branchComparison is not a function`.

- [ ] **Step 3: Implement `branchComparison`**

```typescript
  async branchComparison(actor: ActorContext, query: { from?: string; to?: string }) {
    this.policy.assertCanWriteCrm(actor);
    const { from, to } = this.rangeBounds(query);
    // Mirror of CrmService.branchIdExpr (column preferred, custom_data fallback).
    const branchOf = (a: string) =>
      `coalesce(${a}.branch_id::text, ${a}.custom_data->>'branchId', ${a}.custom_data->>'branch_id')`;
    const result = await this.database.query<{
      branch_id: string;
      name: string;
      revenue: string;
      active_students: string;
      new_leads: string;
      completed_lessons: string;
    }>(
      `select b.id as branch_id, b.name,
         (select coalesce(sum(p.amount), 0) from app.payments p
            join app.students s on s.id = p.student_id and s.deleted_at is null
           where p.deleted_at is null and p.payment_date >= $1::timestamptz and p.payment_date < $2::timestamptz
             and ${branchOf("s")} = b.id::text) as revenue,
         (select count(*) from app.students s
           where s.deleted_at is null and s.status = 'active' and ${branchOf("s")} = b.id::text) as active_students,
         (select count(*) from app.leads l
           where l.deleted_at is null and l.created_at >= $1::timestamptz and l.created_at < $2::timestamptz
             and ${branchOf("l")} = b.id::text) as new_leads,
         (select count(*) from app.lessons les
           where les.deleted_at is null and les.status in ('completed', 'done')
             and les.scheduled_at >= $1::timestamptz and les.scheduled_at < $2::timestamptz
             and les.branch_id = b.id) as completed_lessons
       from app.branches b
       where b.deleted_at is null
       order by b.name`,
      [from, to],
    );
    return {
      from,
      to,
      branches: result.rows.map((r) => ({
        branchId: r.branch_id,
        name: r.name,
        revenue: Number(r.revenue),
        activeStudents: Number(r.active_students),
        newLeads: Number(r.new_leads),
        completedLessons: Number(r.completed_lessons),
      })),
    };
  }
```

- [ ] **Step 4: Add the controller route**

```typescript
  @Get("branches")
  branchComparison(@CurrentActor() actor: ActorContext, @Query() query: { from?: string; to?: string }) {
    return this.analytics.branchComparison(actor, query);
  }
```

- [ ] **Step 5: Run tests + typecheck**

Run: `cd server && npm run typecheck && npm test`
Expected: typecheck 0; the branchComparison test passes; full suite green.

- [ ] **Step 6: Commit**

```bash
git add server/src/analytics/analytics.service.ts server/src/analytics/analytics.controller.ts server/src/analytics/analytics.service.spec.ts
git commit -m "feat(analytics): branch comparison report (revenue/students/leads/lessons) (KVA-183)"
```

---

## Task 3: Loss reasons

**Files:**
- Modify: `server/src/analytics/analytics.service.ts`, `analytics.controller.ts`, `analytics.service.spec.ts`

**Interfaces:**
- Consumes: `rangeBounds` (Task 1).
- Produces: `lossReasons(actor, { from?, to?, branchId? })`; route `GET /analytics/loss-reasons`.

- [ ] **Step 1: Write the failing test**

```typescript
  it("lossReasons groups terminal-transition reasons, gated to manager/admin", async () => {
    const { service, query, policy } = build([
      { reason_id: "r1", name: "Дорого", kind: "lost", leads_lost: "25" },
      { reason_id: "r2", name: "Переезд", kind: "lost", leads_lost: "10" },
    ]);
    const result = await service.lossReasons(actor, { from: "2026-01-01", to: "2026-04-01" });
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("app.lead_status_history");
    expect(sql).toContain("is_terminal");
    expect(result.reasons).toEqual([
      { reasonId: "r1", name: "Дорого", kind: "lost", leadsLost: 25 },
      { reasonId: "r2", name: "Переезд", kind: "lost", leadsLost: 10 },
    ]);
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `cd server && npx jest src/analytics/analytics.service.spec.ts -t lossReasons`
Expected: FAIL — `service.lossReasons is not a function`.

- [ ] **Step 3: Implement `lossReasons`**

```typescript
  async lossReasons(actor: ActorContext, query: { from?: string; to?: string; branchId?: string }) {
    this.policy.assertCanWriteCrm(actor);
    const { from, to } = this.rangeBounds(query);
    const result = await this.database.query<{
      reason_id: string;
      name: string;
      kind: string;
      leads_lost: string;
    }>(
      `select lr.id as reason_id, lr.name, lr.kind,
              count(distinct lsh.lead_id) as leads_lost
         from app.lead_status_history lsh
         join app.lead_statuses ls on ls.id = lsh.new_status_id and ls.is_terminal = true
         join app.lead_loss_reasons lr on lr.id = lsh.reason_id
        where lsh.reason_id is not null
          and lsh.changed_at >= $1::timestamptz
          and lsh.changed_at < $2::timestamptz
          and ($3::uuid is null or lsh.branch_id = $3::uuid)
        group by lr.id, lr.name, lr.kind
        order by leads_lost desc`,
      [from, to, query.branchId ?? null],
    );
    return {
      from,
      to,
      reasons: result.rows.map((r) => ({
        reasonId: r.reason_id,
        name: r.name,
        kind: r.kind,
        leadsLost: Number(r.leads_lost),
      })),
    };
  }
```

- [ ] **Step 4: Add the controller route**

```typescript
  @Get("loss-reasons")
  lossReasons(
    @CurrentActor() actor: ActorContext,
    @Query() query: { from?: string; to?: string; branchId?: string },
  ) {
    return this.analytics.lossReasons(actor, query);
  }
```

- [ ] **Step 5: Run tests + typecheck**

Run: `cd server && npm run typecheck && npm test`
Expected: typecheck 0; the lossReasons test passes; full suite green.

- [ ] **Step 6: Commit**

```bash
git add server/src/analytics/analytics.service.ts server/src/analytics/analytics.controller.ts server/src/analytics/analytics.service.spec.ts
git commit -m "feat(analytics): loss-reasons report from terminal status transitions (KVA-183)"
```

---

## Self-Review

- **Spec coverage (§4F P0):** conversion funnel ✅; branch comparison ✅; loss reasons ✅ — all gated manager/admin, date-ranged, branch-filterable where meaningful.
- **Placeholder scan:** none — full SQL/TS/tests + exact commands.
- **Data correctness:** funnel/loss read `lead_status_history` (the only place transitions + reasons live — no per-lead `loss_reason_id` exists, confirmed); branch comparison uses the `branchIdExpr` coalesce (dual-write safe) for students/leads and the `branch_id` column for lessons (as the dashboard does); terminal via `is_terminal`.
- **Gate consistency:** all three use `assertCanWriteCrm` (manager/admin), matching the CRM dashboard/finance reports.
- **Type consistency:** `rangeBounds` defined once (Task 1), reused by Tasks 2 & 3; counts coerced via `Number`.

## Dependency note

These are live OLTP queries (acceptable at this data size, and gated to a few managers). If any becomes hot, it can move behind an Epic-E matview refreshed by the existing `AnalyticsRefreshWorker` (the funnel/loss matviews `mv_funnel_stage_counts` were the ones deferred from E). Remaining Epic-F reports (debts-by-due-date, revenue forecast, churn risk, chat SLA, retention, teacher/admin analytics, the scheduled weekly report on E6, data-quality alerts) are subsequent F sub-plans on the same `/analytics` + worker substrate. CSV/XLSX export of these reports reuses the Epic-E CSV pattern.
