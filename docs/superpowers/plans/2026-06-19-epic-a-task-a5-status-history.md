# Epic A · Task A5 — lead_status_history + student_status_history — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record every lead status- AND owner-transition (and student status-transition) in a dedicated event table — the keystone the funnel/conversion analytics (Epic F) and the lead-card "История статусов" (Epic C) depend on.

**Architecture:** Migration `0028` adds `lead_status_history` and `student_status_history`. `updateLead` and `updateStudent` are *bracketed* (a cheap pre-SELECT of the prior status/owner, then the existing UPDATE unchanged, then a conditional INSERT only when something actually changed) — the big existing UPDATE statements are NOT rewritten, keeping risk low. One read endpoint exposes a lead's history.

**Tech Stack:** NestJS + TypeScript, PostgreSQL (numbered migrations), class-validator DTOs, Jest.

**Linear:** KVA-188 (A5) under epic KVA-178 (A). Spec §3 F2 / §4A5. Depends on `0026` (`lead_loss_reasons`) and `0027` (`branch_id`) already in the chain.

## Global Constraints

- Migration id is **`0028_status_history`**.
- `app.lead_status_history` records BOTH status and assignment transitions in ONE row per change event (do not split into two tables). Columns: `id, lead_id (fk, on delete cascade), old_status_id, new_status_id (fk lead_statuses), old_owner_id, new_owner_id (fk users), changed_by (fk users), changed_at default now(), reason_id (fk lead_loss_reasons null), comment text, branch_id (fk branches), source_snapshot text`. Index `(lead_id, changed_at desc)`.
- `app.student_status_history`: `id, student_id (fk, on delete cascade), status text not null, branch_id (fk branches), changed_at default now()`. Index `(student_id, changed_at desc)`.
- A history row is inserted ONLY when something changed: for leads, when `status_id` OR `assigned_to` differs from the prior value; for students, when `status` differs.
- Do NOT rewrite the existing `updateLead`/`updateStudent` UPDATE statements — bracket them (pre-select + conditional insert). Branch snapshot = `extractBranchId(patch) ?? <prior branch_id>`.
- `requires_reason` ENFORCEMENT (rejecting a terminal-status move without a reason) is OUT OF SCOPE here — it lands with the Epic C reason-picker. A5 only RECORDS `reason_id`/`comment` when the DTO supplies them.
- Conventions: schema `app.`; `gen_random_uuid()`; idempotent DDL; every new table ends with a guarded `grant ... to magiccrm_app` block. class-validator DTOs.
- Run from `server/`: migrations `npm run db:migrate`/`db:rollback`; tests `npm test`; types `npm run typecheck`.
- **Prod safety:** validate the migration ONLY against an ephemeral Docker Postgres (full chain 0001..0028), NEVER prod, NEVER `server/.env`/`.migration.env`.

---

## File Structure

- **Create** `server/db/migrations/0028_status_history.up.sql` / `.down.sql`.
- **Modify** `server/src/crm/dto/upsert-lead.dto.ts` — add optional `reasonId`, `statusComment`.
- **Modify** `server/src/crm/crm.service.ts` — bracket `updateLead` + `updateStudent`; add `listLeadStatusHistory`.
- **Modify** `server/src/crm/crm.controller.ts` — add `GET /crm/leads/:leadId/status-history`.
- **Modify** `server/src/crm/crm.service.spec.ts` — tests.

---

## Task 1: Migration 0028 — history tables

**Files:**
- Create: `server/db/migrations/0028_status_history.up.sql`
- Create: `server/db/migrations/0028_status_history.down.sql`

**Interfaces (DB):** tables `app.lead_status_history`, `app.student_status_history`.

- [ ] **Step 1: Write the up migration**

```sql
-- server/db/migrations/0028_status_history.up.sql
-- Event log of lead status + ownership transitions and student status transitions.

create table if not exists app.lead_status_history (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null references app.leads(id) on delete cascade,
  old_status_id uuid references app.lead_statuses(id),
  new_status_id uuid references app.lead_statuses(id),
  old_owner_id uuid references app.users(id),
  new_owner_id uuid references app.users(id),
  changed_by uuid references app.users(id),
  changed_at timestamptz not null default now(),
  reason_id uuid references app.lead_loss_reasons(id),
  comment text,
  branch_id uuid references app.branches(id),
  source_snapshot text
);
create index if not exists lead_status_history_lead_idx
  on app.lead_status_history (lead_id, changed_at desc);

create table if not exists app.student_status_history (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references app.students(id) on delete cascade,
  status text not null,
  branch_id uuid references app.branches(id),
  changed_at timestamptz not null default now()
);
create index if not exists student_status_history_student_idx
  on app.student_status_history (student_id, changed_at desc);

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert, update, delete on app.lead_status_history to magiccrm_app;
    grant select, insert, update, delete on app.student_status_history to magiccrm_app;
  end if;
end $$;
```

- [ ] **Step 2: Write the down migration**

```sql
-- server/db/migrations/0028_status_history.down.sql
drop table if exists app.student_status_history;
drop table if exists app.lead_status_history;
```

- [ ] **Step 3: Validate on an ephemeral Docker Postgres (NOT prod)**

```bash
docker run --rm -d --name mmcrm-a5-pg -e POSTGRES_PASSWORD=test -e POSTGRES_DB=mmcrm_test -p 55435:5432 postgres:16
# wait: docker exec mmcrm-a5-pg pg_isready -U postgres  (retry)
cd server && MIGRATION_DATABASE_URL='postgres://postgres:test@localhost:55435/mmcrm_test' DATABASE_URL='postgres://postgres:test@localhost:55435/mmcrm_test' npm run db:migrate
```
Expected last line includes `0028_status_history`. If `0020` fails on missing role, pre-create `magiccrm_app` and re-run. Host MUST be `localhost:55435`; abort if remote.

- [ ] **Step 4: Verify schema + FK targets + reversibility**

```bash
docker exec mmcrm-a5-pg psql -U postgres -d mmcrm_test -c "\d app.lead_status_history"
docker exec mmcrm-a5-pg psql -U postgres -d mmcrm_test -c "\d app.student_status_history"
cd server && MIGRATION_DATABASE_URL='postgres://postgres:test@localhost:55435/mmcrm_test' DATABASE_URL='postgres://postgres:test@localhost:55435/mmcrm_test' npm run db:migrate   # Expected: none
cd server && MIGRATION_DATABASE_URL='postgres://postgres:test@localhost:55435/mmcrm_test' DATABASE_URL='postgres://postgres:test@localhost:55435/mmcrm_test' npm run db:rollback  # Expected: Reverted 0028_status_history
docker exec mmcrm-a5-pg psql -U postgres -d mmcrm_test -c "select to_regclass('app.lead_status_history');"  # Expected: NULL
cd server && MIGRATION_DATABASE_URL='postgres://postgres:test@localhost:55435/mmcrm_test' DATABASE_URL='postgres://postgres:test@localhost:55435/mmcrm_test' npm run db:migrate   # Re-apply
docker stop mmcrm-a5-pg
```
Expected: both tables show the FK targets (lead_status_history.reason_id → lead_loss_reasons, branch_id → branches, *_status_id → lead_statuses, *_owner_id/changed_by → users; student_status_history.student_id → students) and the indexes.

- [ ] **Step 5: Commit**

```bash
git add server/db/migrations/0028_status_history.up.sql server/db/migrations/0028_status_history.down.sql
git commit -m "feat(db): lead_status_history + student_status_history (KVA-188)"
```

---

## Task 2: Capture transitions in updateLead + updateStudent

**Files:**
- Modify: `server/src/crm/dto/upsert-lead.dto.ts`
- Modify: `server/src/crm/crm.service.ts` (`updateLead`, `updateStudent`)
- Modify: `server/src/crm/crm.service.spec.ts`

**Interfaces:**
- Consumes: `extractBranchId(patch)` (from A4). `UpsertLeadDto` gains `reasonId?: string`, `statusComment?: string`.

- [ ] **Step 1: Extend UpsertLeadDto**

Add to `server/src/crm/dto/upsert-lead.dto.ts` (mirror the existing optional-field style):

```typescript
  @IsOptional()
  @IsUUID()
  reasonId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  statusComment?: string;
```

(Ensure `IsUUID` is imported from `class-validator` in that file; `IsString`/`MaxLength`/`IsOptional` are already there.)

- [ ] **Step 2: Write the failing tests**

Add to `server/src/crm/crm.service.spec.ts`:

```typescript
  it("records a lead_status_history row when status changes", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [{ status_id: "old-status", assigned_to: "owner-1", branch_id: "branch-1" }] }, // pre-select
      { rows: [{ id: "lead-1", status_id: "new-status", assigned_to: "owner-1", source: "site", custom_data: {} }] }, // update returning
      { rows: [] }, // history insert
    ]);
    await service.updateLead(actor, "lead-1", { statusId: "new-status" } as never);
    const insert = query.mock.calls.map((c) => String(c[0])).find((s) => s.includes("insert into app.lead_status_history"));
    expect(insert).toBeDefined();
    const params = query.mock.calls.find((c) => String(c[0]).includes("insert into app.lead_status_history"))?.[1] as unknown[];
    expect(params).toEqual(expect.arrayContaining(["lead-1", "old-status", "new-status"]));
  });

  it("does NOT record lead_status_history when neither status nor owner changed", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [{ status_id: "s1", assigned_to: "o1", branch_id: "b1" }] }, // pre-select
      { rows: [{ id: "lead-1", status_id: "s1", assigned_to: "o1", source: "site", custom_data: {} }] }, // update returning (unchanged)
    ]);
    await service.updateLead(actor, "lead-1", { firstName: "X" } as never);
    const insert = query.mock.calls.map((c) => String(c[0])).find((s) => s.includes("insert into app.lead_status_history"));
    expect(insert).toBeUndefined();
  });
```

> The implementer adjusts the mock-result ordering to match how `updateLead` issues queries (pre-select → update → optional insert). The audit-record call is mocked separately and does not consume a `query` slot.

- [ ] **Step 3: Run to verify failure**

Run: `cd server && npx jest src/crm/crm.service.spec.ts -t "lead_status_history"`
Expected: FAIL — no `insert into app.lead_status_history` is emitted.

- [ ] **Step 4: Bracket `updateLead`**

In `server/src/crm/crm.service.ts` `updateLead`, AFTER `const branchId = this.extractBranchId(dto.customDataPatch);` and BEFORE the existing UPDATE, add the pre-select:

```typescript
    const beforeRes = await this.database.query<{
      status_id: string | null;
      assigned_to: string | null;
      branch_id: string | null;
    }>(
      `select status_id, assigned_to, branch_id from app.leads where id = $1 and deleted_at is null`,
      [leadId],
    );
    const before = beforeRes.rows[0] ?? null;
```

Leave the existing UPDATE and `const lead = result.rows[0]; if (!lead) ...` exactly as they are. Then, AFTER the `this.audit.record(...)` call and BEFORE `return this.toLeadDto(lead);`, add:

```typescript
    if (
      before &&
      (before.status_id !== lead.status_id || before.assigned_to !== lead.assigned_to)
    ) {
      await this.database.query(
        `insert into app.lead_status_history
           (lead_id, old_status_id, new_status_id, old_owner_id, new_owner_id,
            changed_by, reason_id, comment, branch_id, source_snapshot)
         values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
        [
          leadId,
          before.status_id,
          lead.status_id,
          before.assigned_to,
          lead.assigned_to,
          actor.userId,
          dto.reasonId ?? null,
          dto.statusComment ?? null,
          branchId ?? before.branch_id,
          lead.source,
        ],
      );
    }
```

- [ ] **Step 5: Bracket `updateStudent`**

In `updateStudent`, AFTER `const branchId = this.extractBranchId(dto.customDataPatch);` and BEFORE the existing CTE query, add:

```typescript
    const beforeStudent = (
      await this.database.query<{ status: string | null; branch_id: string | null }>(
        `select status, branch_id from app.students where id = $1 and deleted_at is null`,
        [studentId],
      )
    ).rows[0] ?? null;
```

Leave the big CTE and `const student = result.rows[0]; if (!student) ...` unchanged. AFTER the `this.audit.record(...)` for the student and before the method returns, add:

```typescript
    if (beforeStudent && beforeStudent.status !== student.status) {
      await this.database.query(
        `insert into app.student_status_history (student_id, status, branch_id)
         values ($1, $2, $3)`,
        [studentId, student.status, branchId ?? beforeStudent.branch_id],
      );
    }
```

- [ ] **Step 6: Run tests + typecheck**

Run: `cd server && npm run typecheck && npm test`
Expected: typecheck 0; the two new lead tests pass; full suite green (existing updateLead/updateStudent tests still pass — the pre-select adds a query each, so any existing test that asserts exact `query` call counts/order for these methods may need its mocked-result list extended by the implementer; adjust those tests minimally to add the pre-select result, without changing their existing assertions' intent).

- [ ] **Step 7: Commit**

```bash
git add server/src/crm/dto/upsert-lead.dto.ts server/src/crm/crm.service.ts server/src/crm/crm.service.spec.ts
git commit -m "feat(crm): record status/owner transitions to history on lead/student update (KVA-188)"
```

---

## Task 3: Read endpoint for a lead's status history

**Files:**
- Modify: `server/src/crm/crm.service.ts` (`listLeadStatusHistory`)
- Modify: `server/src/crm/crm.controller.ts` (route)
- Modify: `server/src/crm/crm.service.spec.ts` (test)

**Interfaces:**
- Produces: `listLeadStatusHistory(actor, leadId): Promise<{ items: Array<{ id; oldStatus: string|null; newStatus: string|null; oldOwnerId; newOwnerId; changedBy; changedAt; reasonId; comment; }> }>`; route `GET /crm/leads/:leadId/status-history`.

- [ ] **Step 1: Write the failing test**

Add to `server/src/crm/crm.service.spec.ts`:

```typescript
  it("lists a lead's status history newest-first", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "h1",
            old_status: "Новый",
            new_status: "Пробный Урок",
            old_owner_id: null,
            new_owner_id: "u1",
            changed_by: "u1",
            changed_at: "2026-06-19T00:00:00.000Z",
            reason_id: null,
            comment: null,
          },
        ],
      },
    ]);
    const result = await service.listLeadStatusHistory(actor, "lead-1");
    expect(result.items[0]).toEqual({
      id: "h1",
      oldStatus: "Новый",
      newStatus: "Пробный Урок",
      oldOwnerId: null,
      newOwnerId: "u1",
      changedBy: "u1",
      changedAt: "2026-06-19T00:00:00.000Z",
      reasonId: null,
      comment: null,
    });
    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("app.lead_status_history");
    expect(query.mock.calls[0][1]).toEqual(["lead-1"]);
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `cd server && npx jest src/crm/crm.service.spec.ts -t "status history newest-first"`
Expected: FAIL — `service.listLeadStatusHistory is not a function`.

- [ ] **Step 3: Implement the service method**

Add to `CrmService` in `server/src/crm/crm.service.ts`:

```typescript
  async listLeadStatusHistory(actor: ActorContext, leadId: string) {
    this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<{
      id: string;
      old_status: string | null;
      new_status: string | null;
      old_owner_id: string | null;
      new_owner_id: string | null;
      changed_by: string | null;
      changed_at: string;
      reason_id: string | null;
      comment: string | null;
    }>(
      `select h.id,
              os.name as old_status,
              ns.name as new_status,
              h.old_owner_id, h.new_owner_id, h.changed_by, h.changed_at,
              h.reason_id, h.comment
         from app.lead_status_history h
         left join app.lead_statuses os on os.id = h.old_status_id
         left join app.lead_statuses ns on ns.id = h.new_status_id
        where h.lead_id = $1
        order by h.changed_at desc`,
      [leadId],
    );
    return {
      items: result.rows.map((row) => ({
        id: row.id,
        oldStatus: row.old_status,
        newStatus: row.new_status,
        oldOwnerId: row.old_owner_id,
        newOwnerId: row.new_owner_id,
        changedBy: row.changed_by,
        changedAt: row.changed_at,
        reasonId: row.reason_id,
        comment: row.comment,
      })),
    };
  }
```

- [ ] **Step 4: Add the controller route**

Add to `server/src/crm/crm.controller.ts` (mirror the existing lead routes with `@Param(..., ParseUUIDPipe)`):

```typescript
  @Get("leads/:leadId/status-history")
  listLeadStatusHistory(
    @CurrentActor() actor: ActorContext,
    @Param("leadId", ParseUUIDPipe) leadId: string,
  ) {
    return this.crm.listLeadStatusHistory(actor, leadId);
  }
```

- [ ] **Step 5: Run tests + typecheck**

Run: `cd server && npm run typecheck && npm test`
Expected: typecheck 0; the new test passes; full suite green.

- [ ] **Step 6: Commit**

```bash
git add server/src/crm/crm.service.ts server/src/crm/crm.controller.ts server/src/crm/crm.service.spec.ts
git commit -m "feat(crm): GET lead status-history endpoint (KVA-188)"
```

---

## Self-Review

- **Spec coverage (§4A5):** both history tables ✅ (Task 1); one row per change capturing status AND owner ✅ (Task 2, leads); student status transitions ✅ (Task 2); insert only on actual change ✅ (the `before.X !== lead.X` guards); reason_id/comment recorded from DTO ✅; read endpoint ✅ (Task 3). `requires_reason` enforcement explicitly deferred to Epic C.
- **Placeholder scan:** none — full SQL/TS/tests with exact commands.
- **Low-risk bracketing:** the existing `updateLead`/`updateStudent` UPDATE statements are untouched; only a pre-SELECT and a guarded INSERT are added around them.
- **Type consistency:** `listLeadStatusHistory` and the new `lead_status_history`/`student_status_history` names are identical across migration, service, controller, and tests; the insert column order matches the params array.
- **Branch snapshot:** uses `branchId ?? before.branch_id` (the post-update branch), consistent with A4's dual-write.

## Dependency note

A5 is the keystone for Epic F #1/#2/#7 (status history, conversion funnel stage timestamps, assignment history) and the lead-card "История статусов" timeline in Epic C. Migration `0028` is applied to prod later, batched with the other Epic A migrations.
