# Epic F · P0 reports wave 2 (debts, forecast, churn) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three more management reports on the `/analytics` namespace — debts bucketed by how overdue they are (F2), an unpaid-revenue forecast for the next 7/14/30 days (F3), and a churn-risk list of active students with no recent completed lesson (F5).

**Architecture:** Three new `AnalyticsService` methods (live SQL, no new tables) + three `AnalyticsController` routes, each gated to manager/admin via `CrmPolicy.assertCanWriteCrm`. Unlike the wave-1 reports these are **now-relative** (overdue/forecast/inactivity), so they do NOT use `rangeBounds`; each takes its own params. Branch scoping uses the same `branchOf` coalesce (mirror of `CrmService.branchIdExpr`) the wave-1 branch report uses.

**Tech Stack:** NestJS/TypeScript, PostgreSQL, Jest. No migration, no new dependency.

**Linear:** KVA-183 (Epic F) — tasks F2, F3, F5. Spec §4F. Depends on A4 (`branch_id`); reads `expected_payments`/`student_balances`/`lessons`/`lesson_participation` (all pre-existing, migration 0002).

## Global Constraints

- All three methods gate `this.policy.assertCanWriteCrm(actor)` FIRST (manager/admin only — financial/operational data).
- Unpaid expected payments = `status in ('pending', 'open')`. `expected_payments` has NO `deleted_at`; always join `app.students s ... and s.deleted_at is null`.
- `expected_payments.due_date` is a `date` (nullable). Overdue arithmetic: `now()::date - ep.due_date` (integer days). Forecast windows: `ep.due_date between now()::date and now()::date + N`.
- Branch scoping uses `branchOf(a) = coalesce(<a>.branch_id::text, <a>.custom_data->>'branchId', <a>.custom_data->>'branch_id')` (inline mirror of `CrmService.branchIdExpr`) compared to `$n::text`; optional `branchId` param, `null` = all branches.
- Churn: a student's last completed lesson = `max(l.scheduled_at)` over `coalesce(l.student_id, lp.student_id)` where `l.status in ('completed','done') and l.deleted_at is null` (mirror the existing `lesson_costs` CTE in `crm.service.ts` — individual via `lessons.student_id`, group via `lesson_participation.student_id`). `student_status = 'active'` only.
- Numeric DB outputs coerced with `Number(...)`.
- New endpoints on the existing `AnalyticsController`; import `ActorContext`/`CurrentActor` from `../common/security/...`.
- No `rangeBounds` use in these three (they are now-relative). Run from `server/`: tests `npm test`; types `npm run typecheck`.

---

## File Structure

- **Modify** `server/src/analytics/analytics.service.ts` — `debts`, `revenueForecast`, `churnRisk`.
- **Modify** `server/src/analytics/analytics.controller.ts` — `GET /analytics/debts`, `/analytics/forecast`, `/analytics/churn-risk`.
- **Modify** `server/src/analytics/analytics.service.spec.ts` — tests for all three.

---

## Task 1: Debts by overdue bucket (F2)

**Files:**
- Modify: `server/src/analytics/analytics.service.ts`, `analytics.controller.ts`, `analytics.service.spec.ts`

**Interfaces:**
- Produces: `debts(actor, { branchId? })` → `{ buckets: Array<{ bucket; students; amount }>, totalStudents, totalAmount }`; route `GET /analytics/debts`.

- [ ] **Step 1: Write the failing test**

Add to `analytics.service.spec.ts` (use the existing `build(rows)` harness whose `policy` mock includes `assertCanWriteCrm`):

```typescript
  it("debts buckets overdue payments in fixed order with zero-fill, gated to manager/admin", async () => {
    const { service, query, policy } = build([
      { bucket: "0-7", students: "5", amount: "50000" },
      { bucket: "30+", students: "2", amount: "30000" },
    ]);
    const result = await service.debts(actor, {});
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("app.expected_payments");
    expect(result.buckets).toEqual([
      { bucket: "0-7", students: 5, amount: 50000 },
      { bucket: "8-14", students: 0, amount: 0 },
      { bucket: "15-30", students: 0, amount: 0 },
      { bucket: "30+", students: 2, amount: 30000 },
    ]);
    expect(result.totalStudents).toBe(7);
    expect(result.totalAmount).toBe(80000);
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `cd server && npx jest src/analytics/analytics.service.spec.ts -t debts`
Expected: FAIL — `service.debts is not a function`.

- [ ] **Step 3: Implement `debts`**

```typescript
  async debts(actor: ActorContext, query: { branchId?: string }) {
    this.policy.assertCanWriteCrm(actor);
    const branchOf = (a: string) =>
      `coalesce(${a}.branch_id::text, ${a}.custom_data->>'branchId', ${a}.custom_data->>'branch_id')`;
    const result = await this.database.query<{ bucket: string; students: string; amount: string }>(
      `select
         case
           when now()::date - ep.due_date between 0 and 7 then '0-7'
           when now()::date - ep.due_date between 8 and 14 then '8-14'
           when now()::date - ep.due_date between 15 and 30 then '15-30'
           else '30+'
         end as bucket,
         count(distinct ep.student_id) as students,
         coalesce(sum(ep.amount), 0) as amount
       from app.expected_payments ep
       join app.students s on s.id = ep.student_id and s.deleted_at is null
      where ep.status in ('pending', 'open')
        and ep.due_date is not null
        and ep.due_date <= now()::date
        and ($1::uuid is null or ${branchOf("s")} = $1::text)
      group by 1`,
      [query.branchId ?? null],
    );
    const order = ["0-7", "8-14", "15-30", "30+"];
    const byBucket = new Map(result.rows.map((r) => [r.bucket, r]));
    const buckets = order.map((bucket) => {
      const row = byBucket.get(bucket);
      return { bucket, students: Number(row?.students ?? 0), amount: Number(row?.amount ?? 0) };
    });
    return {
      buckets,
      totalStudents: buckets.reduce((n, b) => n + b.students, 0),
      totalAmount: buckets.reduce((n, b) => n + b.amount, 0),
    };
  }
```

> `totalStudents` sums the per-bucket distinct counts; a student with debts in two buckets is counted in each (acceptable for a bucketed view — document if asked). Overdue = `due_date <= now()::date` (due today counts as 0 days → `0-7`). Future-dated payments are excluded (they belong to the forecast).

- [ ] **Step 4: Add the controller route**

```typescript
  @Get("debts")
  debts(@CurrentActor() actor: ActorContext, @Query() query: { branchId?: string }) {
    return this.analytics.debts(actor, query);
  }
```

- [ ] **Step 5: Run tests + typecheck**

Run: `cd server && npm run typecheck && npm test`
Expected: typecheck 0; the debts test passes; full suite green.

- [ ] **Step 6: Commit**

```bash
git add server/src/analytics/analytics.service.ts server/src/analytics/analytics.controller.ts server/src/analytics/analytics.service.spec.ts
git commit -m "feat(analytics): debts-by-overdue-bucket report (KVA-183)"
```

---

## Task 2: Revenue forecast (F3)

**Files:**
- Modify: `server/src/analytics/analytics.service.ts`, `analytics.controller.ts`, `analytics.service.spec.ts`

**Interfaces:**
- Produces: `revenueForecast(actor, { branchId? })` → `{ next7, next14, next30 }` (cumulative); route `GET /analytics/forecast`.

- [ ] **Step 1: Write the failing test**

```typescript
  it("revenueForecast sums unpaid payments due within 7/14/30 days, gated", async () => {
    const { service, query, policy } = build([{ next7: "10000", next14: "25000", next30: "60000" }]);
    const result = await service.revenueForecast(actor, {});
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("app.expected_payments");
    expect(result).toEqual({ next7: 10000, next14: 25000, next30: 60000 });
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `cd server && npx jest src/analytics/analytics.service.spec.ts -t revenueForecast`
Expected: FAIL — `service.revenueForecast is not a function`.

- [ ] **Step 3: Implement `revenueForecast`**

```typescript
  async revenueForecast(actor: ActorContext, query: { branchId?: string }) {
    this.policy.assertCanWriteCrm(actor);
    const branchOf = (a: string) =>
      `coalesce(${a}.branch_id::text, ${a}.custom_data->>'branchId', ${a}.custom_data->>'branch_id')`;
    const result = await this.database.query<{ next7: string; next14: string; next30: string }>(
      `select
         coalesce(sum(ep.amount) filter (where ep.due_date >= now()::date and ep.due_date <= now()::date + 7), 0) as next7,
         coalesce(sum(ep.amount) filter (where ep.due_date >= now()::date and ep.due_date <= now()::date + 14), 0) as next14,
         coalesce(sum(ep.amount) filter (where ep.due_date >= now()::date and ep.due_date <= now()::date + 30), 0) as next30
       from app.expected_payments ep
       join app.students s on s.id = ep.student_id and s.deleted_at is null
      where ep.status in ('pending', 'open')
        and ($1::uuid is null or ${branchOf("s")} = $1::text)`,
      [query.branchId ?? null],
    );
    const row = result.rows[0];
    return { next7: Number(row?.next7 ?? 0), next14: Number(row?.next14 ?? 0), next30: Number(row?.next30 ?? 0) };
  }
```

> Windows are CUMULATIVE (next14 includes next7, next30 includes next14) — the natural "expected to come in within N days" reading. No `subscription_id` linkage exists, so the forecast is purely `expected_payments.due_date` driven — document that.

- [ ] **Step 4: Add the controller route**

```typescript
  @Get("forecast")
  revenueForecast(@CurrentActor() actor: ActorContext, @Query() query: { branchId?: string }) {
    return this.analytics.revenueForecast(actor, query);
  }
```

- [ ] **Step 5: Run tests + typecheck**

Run: `cd server && npm run typecheck && npm test`
Expected: typecheck 0; the forecast test passes; full suite green.

- [ ] **Step 6: Commit**

```bash
git add server/src/analytics/analytics.service.ts server/src/analytics/analytics.controller.ts server/src/analytics/analytics.service.spec.ts
git commit -m "feat(analytics): revenue forecast (next 7/14/30 days) report (KVA-183)"
```

---

## Task 3: Churn risk (F5)

**Files:**
- Modify: `server/src/analytics/analytics.service.ts`, `analytics.controller.ts`, `analytics.service.spec.ts`

**Interfaces:**
- Produces: `churnRisk(actor, { inactiveDays?, branchId? })` → `{ inactiveDays, students: Array<{ studentId; name; lastCompletedAt; daysSinceLast }> }`; route `GET /analytics/churn-risk`.

- [ ] **Step 1: Write the failing test**

```typescript
  it("churnRisk lists active students with no recent completed lesson, gated", async () => {
    const { service, query, policy } = build([
      { student_id: "stu1", name: "Иван Петров", last_completed_at: "2026-03-01T10:00:00Z", days_since_last: "40" },
      { student_id: "stu2", name: "Без занятий", last_completed_at: null, days_since_last: null },
    ]);
    const result = await service.churnRisk(actor, { inactiveDays: 30 });
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("app.lessons");
    expect(sql).toContain("lesson_participation");
    expect(result.inactiveDays).toBe(30);
    expect(result.students).toEqual([
      { studentId: "stu1", name: "Иван Петров", lastCompletedAt: "2026-03-01T10:00:00Z", daysSinceLast: 40 },
      { studentId: "stu2", name: "Без занятий", lastCompletedAt: null, daysSinceLast: null },
    ]);
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `cd server && npx jest src/analytics/analytics.service.spec.ts -t churnRisk`
Expected: FAIL — `service.churnRisk is not a function`.

- [ ] **Step 3: Implement `churnRisk`**

```typescript
  async churnRisk(actor: ActorContext, query: { inactiveDays?: number | string; branchId?: string }) {
    this.policy.assertCanWriteCrm(actor);
    const inactiveDays = Number(query.inactiveDays ?? 21);
    const branchOf = (a: string) =>
      `coalesce(${a}.branch_id::text, ${a}.custom_data->>'branchId', ${a}.custom_data->>'branch_id')`;
    const result = await this.database.query<{
      student_id: string;
      name: string;
      last_completed_at: string | null;
      days_since_last: string | null;
    }>(
      `with last_lesson as (
         select coalesce(l.student_id, lp.student_id) as student_id,
                max(l.scheduled_at) as last_completed_at
           from app.lessons l
           left join app.lesson_participation lp on lp.lesson_id = l.id
          where l.deleted_at is null
            and l.status in ('completed', 'done')
            and coalesce(l.student_id, lp.student_id) is not null
          group by coalesce(l.student_id, lp.student_id)
       )
       select s.id as student_id,
              btrim(concat_ws(' ', p.first_name, p.last_name)) as name,
              ll.last_completed_at,
              case when ll.last_completed_at is null then null
                   else (now()::date - ll.last_completed_at::date) end as days_since_last
         from app.students s
         left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
         left join last_lesson ll on ll.student_id = s.id
        where s.deleted_at is null and s.status = 'active'
          and ($2::uuid is null or ${branchOf("s")} = $2::text)
          and (ll.last_completed_at is null
               or ll.last_completed_at < now() - make_interval(days => $1::int))
        order by ll.last_completed_at asc nulls first
        limit 200`,
      [inactiveDays, query.branchId ?? null],
    );
    return {
      inactiveDays,
      students: result.rows.map((r) => ({
        studentId: r.student_id,
        name: r.name,
        lastCompletedAt: r.last_completed_at,
        daysSinceLast: r.days_since_last === null ? null : Number(r.days_since_last),
      })),
    };
  }
```

> `inactiveDays` defaults to 21 (≈3 missed weekly lessons). Students with no completed lesson ever (`last_completed_at is null`) are included (sorted first) — `lastCompletedAt: null` signals never-attended; the consumer can distinguish. Capped at 200 rows — if the cap is hit it is logged as a known limit by the caller (document the cap).

- [ ] **Step 4: Add the controller route**

```typescript
  @Get("churn-risk")
  churnRisk(
    @CurrentActor() actor: ActorContext,
    @Query() query: { inactiveDays?: string; branchId?: string },
  ) {
    return this.analytics.churnRisk(actor, query);
  }
```

- [ ] **Step 5: Run tests + typecheck**

Run: `cd server && npm run typecheck && npm test`
Expected: typecheck 0; the churnRisk test passes; full suite green.

- [ ] **Step 6: Commit**

```bash
git add server/src/analytics/analytics.service.ts server/src/analytics/analytics.controller.ts server/src/analytics/analytics.service.spec.ts
git commit -m "feat(analytics): churn-risk report (active students, no recent lesson) (KVA-183)"
```

---

## Self-Review

- **Spec coverage (§4F P0 wave 2):** F2 debts-by-overdue-bucket ✅; F3 revenue forecast 7/14/30 ✅; F5 churn risk ✅ — all gated manager/admin, branch-filterable.
- **Placeholder scan:** none — full SQL/TS/tests + exact commands.
- **Data correctness:** debts/forecast read `expected_payments` with the canonical `status in ('pending','open')` filter + `students.deleted_at is null` (no soft-delete column on payments); churn uses the established `coalesce(l.student_id, lp.student_id)` lesson-participation pattern; no `subscription_id`/`next_payment_date` exists, so forecast is `due_date`-driven (documented).
- **Honest labeling:** forecast windows are cumulative (documented); debts `totalStudents` may double-count a student across buckets (documented); churn includes never-attended students with `lastCompletedAt: null` (documented); churn list capped at 200 (documented).
- **Gate consistency:** all three `assertCanWriteCrm`, matching wave 1 + the CRM dashboard.

## Dependency note

Remaining Epic-F P0: F6 chat SLA (first-response avg/median/p90 in the administration chat — needs message→reply pairing) and F7 the weekly management report (aggregates F1–F6 into one payload, deliverable via the Epic-E `report_deliveries`/worker) — wave 3. If any of these now-relative reports gets hot, the lesson/payment scans can move behind an Epic-E matview. CSV/XLSX export of any report reuses the Epic-E CSV pattern.
