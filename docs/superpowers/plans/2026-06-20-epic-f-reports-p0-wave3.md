# Epic F · P0 reports wave 3 (chat SLA, weekly report) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the administration-chat first-response SLA (F6 — avg/median/p90 response time) and a one-shot weekly management report (F7 — an aggregate of all the existing `/analytics` reports for the last 7 days) to the `/analytics` namespace.

**Architecture:** Two new `AnalyticsService` methods + two `AnalyticsController` routes, gated `assertCanWriteCrm`. `chatsSla` is a window-function query over `app.messages` in `administration` chats: classify each message's sender as staff/client by `users.role`, detect each "new inbound turn" (a client message whose previous message was staff or none), find the next staff message, and aggregate the gaps with `percentile_cont`. `weeklyReport` composes the other report methods (funnel/debts/forecast/churn/branches/lossReasons/chatsSla) over a 7-day window into one payload — no new SQL, just orchestration. Scheduled email delivery (E6) is a separate later wave.

**Tech Stack:** NestJS/TypeScript, PostgreSQL (window functions, `percentile_cont`), Jest. No migration, no new dependency.

**Linear:** KVA-183 (Epic F) — tasks F6, F7. Spec §4F. Reads `messages`/`chats`/`users` (migrations 0003/0001/0017); `chats.branch_id` from 0027.

## Global Constraints

- Both methods gate `this.policy.assertCanWriteCrm(actor)` FIRST (manager/admin).
- Staff = `users.role in ('admin','manager','system_admin')`; everything else (incl. `teacher`, `client`, null sender) = client side. Exclude `message_type = 'system'` and `deleted_at is not null` and `sender_id is null` from the classification. (A non-staff message opens an inbound turn.)
- "New inbound turn" = a client-classified message whose immediately-previous message in the chat (by `created_at`) was staff-classified OR there was none (first message). First-response time = (next staff message after the inbound) − (inbound). Inbound turns are filtered to the `[from, to)` window by the INBOUND message's `created_at`; the response may land after `to`.
- SLA response times reported in MINUTES (`extract(epoch from (response_at - inbound_at)) / 60.0`), rounded to 1 decimal in TS. `percentile_cont(0.5)`/`(0.9)`; avg via `avg(...)`. Empty set → 0 (coalesced).
- `chatsSla` branch filter uses `chats.branch_id = $3::uuid` (note: `chats.branch_id` may be sparsely populated — document that branch-scoped SLA only covers chats with a branch set).
- `weeklyReport` window = `to = now`, `from = now − 7 days` (ISO). Date-ranged sub-reports (funnel, branchComparison, lossReasons, chatsSla) get `{from, to, branchId}`; now-relative ones (debts, revenueForecast, churnRisk) get `{branchId}`. It includes the churn SUMMARY (`inactiveDays`, `totalAtRisk`) — NOT the 200-row student list.
- `rangeBounds` already exists (F wave-1 Task 1) — `chatsSla` uses it.
- Numeric DB outputs coerced with `Number(...)`. New endpoints on the existing `AnalyticsController`.
- Run from `server/`: tests `npm test`; types `npm run typecheck`.

---

## File Structure

- **Modify** `server/src/analytics/analytics.service.ts` — `chatsSla`, `weeklyReport`.
- **Modify** `server/src/analytics/analytics.controller.ts` — `GET /analytics/chats/sla`, `GET /analytics/weekly-report`.
- **Modify** `server/src/analytics/analytics.service.spec.ts` — tests for both.

---

## Task 1: Chat first-response SLA (F6)

**Files:**
- Modify: `server/src/analytics/analytics.service.ts`, `analytics.controller.ts`, `analytics.service.spec.ts`

**Interfaces:**
- Consumes: `rangeBounds` (wave-1 Task 1).
- Produces: `chatsSla(actor, { from?, to?, branchId? })` → `{ from, to, inboundCount, respondedCount, responseRate, avgMinutes, medianMinutes, p90Minutes }`; route `GET /analytics/chats/sla`.

- [ ] **Step 1: Write the failing test**

Add to `analytics.service.spec.ts` (existing `build(rows)` harness; `policy` mock has `assertCanWriteCrm`):

```typescript
  it("chatsSla computes first-response stats over administration chats, gated", async () => {
    const { service, query, policy } = build([
      {
        inbound_count: "10",
        responded_count: "8",
        avg_minutes: "12.5",
        median_minutes: "9",
        p90_minutes: "30",
      },
    ]);
    const result = await service.chatsSla(actor, { from: "2026-06-01", to: "2026-06-08" });
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("'administration'");
    expect(sql).toContain("percentile_cont");
    expect(result).toEqual({
      from: "2026-06-01",
      to: "2026-06-08",
      inboundCount: 10,
      respondedCount: 8,
      responseRate: 0.8,
      avgMinutes: 12.5,
      medianMinutes: 9,
      p90Minutes: 30,
    });
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `cd server && npx jest src/analytics/analytics.service.spec.ts -t chatsSla`
Expected: FAIL — `service.chatsSla is not a function`.

- [ ] **Step 3: Implement `chatsSla`**

```typescript
  async chatsSla(actor: ActorContext, query: { from?: string; to?: string; branchId?: string }) {
    this.policy.assertCanWriteCrm(actor);
    const { from, to } = this.rangeBounds(query);
    const result = await this.database.query<{
      inbound_count: string;
      responded_count: string;
      avg_minutes: string | null;
      median_minutes: string | null;
      p90_minutes: string | null;
    }>(
      `with classified as (
         select m.chat_id, m.created_at,
                case when u.role in ('admin', 'manager', 'system_admin') then 'staff' else 'client' end as cls
           from app.messages m
           join app.chats c on c.id = m.chat_id and c.type = 'administration' and c.deleted_at is null
           left join app.users u on u.id = m.sender_id and u.deleted_at is null
          where m.deleted_at is null
            and m.message_type <> 'system'
            and m.sender_id is not null
            and ($3::uuid is null or c.branch_id = $3::uuid)
       ),
       seq as (
         select chat_id, created_at, cls,
                lag(cls) over (partition by chat_id order by created_at) as prev_cls
           from classified
       ),
       inbound as (
         select chat_id, created_at as inbound_at
           from seq
          where cls = 'client'
            and (prev_cls is null or prev_cls = 'staff')
            and created_at >= $1::timestamptz and created_at < $2::timestamptz
       ),
       gaps as (
         select extract(epoch from (resp.response_at - i.inbound_at)) / 60.0 as minutes
           from inbound i
           cross join lateral (
             select min(s.created_at) as response_at
               from classified s
              where s.chat_id = i.chat_id and s.cls = 'staff' and s.created_at > i.inbound_at
           ) resp
          where resp.response_at is not null
       )
       select
         (select count(*) from inbound) as inbound_count,
         (select count(*) from gaps) as responded_count,
         coalesce(avg(minutes), 0) as avg_minutes,
         coalesce(percentile_cont(0.5) within group (order by minutes), 0) as median_minutes,
         coalesce(percentile_cont(0.9) within group (order by minutes), 0) as p90_minutes
       from gaps`,
      [from, to, query.branchId ?? null],
    );
    const row = result.rows[0];
    const inboundCount = Number(row?.inbound_count ?? 0);
    const respondedCount = Number(row?.responded_count ?? 0);
    const round1 = (v: string | null) => Math.round(Number(v ?? 0) * 10) / 10;
    return {
      from,
      to,
      inboundCount,
      respondedCount,
      responseRate: inboundCount === 0 ? 0 : Math.round((respondedCount / inboundCount) * 100) / 100,
      avgMinutes: round1(row?.avg_minutes ?? null),
      medianMinutes: round1(row?.median_minutes ?? null),
      p90Minutes: round1(row?.p90_minutes ?? null),
    };
  }
```

> Staff = admin/manager/system_admin; teachers/clients/system are the client side (documented). `responseRate` = responded/inbound (2 dp). Inbound turns are bucketed by the inbound message's `created_at`; the staff response may fall after `to`. Branch-scoped SLA only covers chats whose `branch_id` is set (sparse — documented).

- [ ] **Step 4: Add the controller route**

```typescript
  @Get("chats/sla")
  chatsSla(
    @CurrentActor() actor: ActorContext,
    @Query() query: { from?: string; to?: string; branchId?: string },
  ) {
    return this.analytics.chatsSla(actor, query);
  }
```

- [ ] **Step 5: Run tests + typecheck**

Run: `cd server && npm run typecheck && npm test`
Expected: typecheck 0; the chatsSla test passes; full suite green.

- [ ] **Step 6: Commit**

```bash
git add server/src/analytics/analytics.service.ts server/src/analytics/analytics.controller.ts server/src/analytics/analytics.service.spec.ts
git commit -m "feat(analytics): administration-chat first-response SLA (avg/median/p90) (KVA-183)"
```

---

## Task 2: Weekly management report (F7)

**Files:**
- Modify: `server/src/analytics/analytics.service.ts`, `analytics.controller.ts`, `analytics.service.spec.ts`

**Interfaces:**
- Consumes: `funnel`, `debts`, `revenueForecast`, `churnRisk`, `branchComparison`, `lossReasons`, `chatsSla` (all existing).
- Produces: `weeklyReport(actor, { branchId? })` → `{ window:{from,to}, funnel, debts, forecast, churn:{inactiveDays,totalAtRisk}, branches, lossReasons, chatSla }`; route `GET /analytics/weekly-report`.

- [ ] **Step 1: Write the failing test**

This is an orchestrator — spy on the composed methods rather than mocking SQL:

```typescript
  it("weeklyReport composes the sub-reports over a 7-day window, gated", async () => {
    const { service, policy } = build([]);
    jest.spyOn(service, "funnel").mockResolvedValue({ from: "x", to: "y", stages: ["F"] } as never);
    jest.spyOn(service, "debts").mockResolvedValue({ buckets: ["D"] } as never);
    jest.spyOn(service, "revenueForecast").mockResolvedValue({ next7: 1, next14: 2, next30: 3 } as never);
    jest.spyOn(service, "churnRisk").mockResolvedValue({ inactiveDays: 21, students: [{}], totalAtRisk: 42 } as never);
    jest.spyOn(service, "branchComparison").mockResolvedValue({ branches: ["B"] } as never);
    jest.spyOn(service, "lossReasons").mockResolvedValue({ reasons: ["L"], unspecifiedCount: 3 } as never);
    jest.spyOn(service, "chatsSla").mockResolvedValue({ avgMinutes: 5 } as never);

    const result = await service.weeklyReport(actor, {});

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(result.funnel).toEqual({ from: "x", to: "y", stages: ["F"] });
    expect(result.debts).toEqual({ buckets: ["D"] });
    expect(result.forecast).toEqual({ next7: 1, next14: 2, next30: 3 });
    expect(result.churn).toEqual({ inactiveDays: 21, totalAtRisk: 42 }); // summary only, no student list
    expect(result.branches).toEqual({ branches: ["B"] });
    expect(result.lossReasons).toEqual({ reasons: ["L"], unspecifiedCount: 3 });
    expect(result.chatSla).toEqual({ avgMinutes: 5 });
    expect(result.window.from).toBeDefined();
    expect(result.window.to).toBeDefined();
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `cd server && npx jest src/analytics/analytics.service.spec.ts -t weeklyReport`
Expected: FAIL — `service.weeklyReport is not a function`.

- [ ] **Step 3: Implement `weeklyReport`**

```typescript
  async weeklyReport(actor: ActorContext, query: { branchId?: string }) {
    this.policy.assertCanWriteCrm(actor);
    const to = new Date().toISOString();
    const from = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
    const branchId = query.branchId;
    const dated = { from, to, branchId };
    const [funnel, debts, forecast, churn, branches, lossReasons, chatSla] = await Promise.all([
      this.funnel(actor, dated),
      this.debts(actor, { branchId }),
      this.revenueForecast(actor, { branchId }),
      this.churnRisk(actor, { branchId }),
      this.branchComparison(actor, { from, to }),
      this.lossReasons(actor, dated),
      this.chatsSla(actor, dated),
    ]);
    return {
      window: { from, to },
      funnel,
      debts,
      forecast,
      churn: { inactiveDays: churn.inactiveDays, totalAtRisk: churn.totalAtRisk },
      branches,
      lossReasons,
      chatSla,
    };
  }
```

> Each sub-method re-asserts its own gate (harmless); the top-level gate fails fast. `branchComparison` takes only `{from,to}` (it IS the per-branch breakdown). The churn list is dropped — only the `{inactiveDays, totalAtRisk}` summary is included to keep the report compact.

- [ ] **Step 4: Add the controller route**

```typescript
  @Get("weekly-report")
  weeklyReport(@CurrentActor() actor: ActorContext, @Query() query: { branchId?: string }) {
    return this.analytics.weeklyReport(actor, query);
  }
```

- [ ] **Step 5: Run tests + typecheck**

Run: `cd server && npm run typecheck && npm test`
Expected: typecheck 0; the weeklyReport test passes; full suite green.

- [ ] **Step 6: Commit**

```bash
git add server/src/analytics/analytics.service.ts server/src/analytics/analytics.controller.ts server/src/analytics/analytics.service.spec.ts
git commit -m "feat(analytics): weekly management report aggregator (KVA-183)"
```

---

## Self-Review

- **Spec coverage (§4F P0 wave 3):** F6 chat first-response SLA (avg/median/p90 + response rate) ✅; F7 weekly report aggregate ✅. The scheduled EMAIL DELIVERY of the weekly report (E6 — `report_deliveries` + email transport + a worker job) is explicitly a separate later wave.
- **Placeholder scan:** none — full SQL/TS/tests + exact commands.
- **Data correctness:** SLA classifies staff via `users.role in ('admin','manager','system_admin')`, excludes system/deleted/null-sender messages, detects new inbound turns via `lag`, measures the gap to the next staff message via lateral; `percentile_cont` for median/p90. Weekly report composes the existing (already-reviewed) methods — no new SQL.
- **Honest labeling:** SLA only counts inbound turns that got a response in the percentiles (response rate surfaces unanswered separately); branch-scoped SLA covers only chats with a `branch_id` (documented); teachers are on the client side of the admin-chat SLA (documented); weekly churn is the summary count, not the capped list (documented).
- **Gate consistency:** both `assertCanWriteCrm`; sub-reports re-gate (harmless).

## Dependency note

This completes the F P0 report SET (funnel, branches, loss, debts, forecast, churn, SLA, weekly). Remaining Epic-F: the scheduled weekly-report DELIVERY (E6 substrate — `report_deliveries` table + email transport + a refresh-worker-style job), F8 branch working-hours/holidays (unblocks the "within working hours / overdue" SLA cut), and the P1/P2 reports (responsible-assignment history, data quality, task lifecycle, retention cohorts, deep teacher/financial analytics). If any report gets hot it can move behind an Epic-E matview; CSV/XLSX export reuses the Epic-E pattern.
