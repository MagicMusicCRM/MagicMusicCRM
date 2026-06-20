# Epic A · Task A4 — Unified branch_id — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote branch from the `custom_data->>'branchId'` JSON hack to a real indexed `branch_id` FK on leads, students, payments, expenses, tasks, and chats — with a transition-safe read fallback and a dual-write so nothing regresses before the prod backfill runs.

**Architecture:** Migration `0027` adds the columns + indexes + a guarded backfill. Reads go through one private SQL helper `branchIdExpr(alias)` that prefers the real column and falls back to the legacy JSON keys (kept as text to preserve the existing text-comparison semantics — no risky `jsonb::uuid` casts). Writes dual-write: when `customDataPatch.branchId` is present, the service also sets the `branch_id` column. The column is left nullable in A4; NOT NULL comes later after the data-quality report (Epic F) confirms backfill completeness.

**Tech Stack:** NestJS + TypeScript, PostgreSQL (numbered up/down SQL migrations via `MigrationRunner`), Jest (`jest --runInBand`).

**Linear:** KVA-187 (A4) under epic KVA-178 (A). Spec: `docs/superpowers/specs/2026-06-19-clients-window-and-management-analytics-design.md` (§3 F1, §4A4).

## Global Constraints

- Migration id is **`0027_unified_branch_id`** (next free number after `0026_crm_dictionaries`).
- Add `branch_id uuid references app.branches(id)` to `app.leads`, `app.students`, `app.payments`, `app.expenses`, `app.tasks`, `app.chats`. Add `lead_id uuid references app.leads(id)` and `student_id uuid references app.students(id)` to `app.chats`. Partial index `(branch_id) where deleted_at is null` on the soft-deletable tables (leads/students/tasks/expenses — `app.chats` and `app.payments` have no `deleted_at`; index them unconditionally). The column stays NULLABLE in this task.
- Backfill order matters: students & leads from their own `custom_data`; THEN payments from `students.branch_id`; tasks from their linked student/lead. Cast to uuid ONLY when the value matches a UUID regex AND exists in `app.branches` (so the FK never fails and a malformed value never throws). expenses & chats are left NULL (no source).
- Reads: introduce ONE helper `private branchIdExpr(alias: string): string` returning `coalesce(${alias}.branch_id::text, ${alias}.custom_data->>'branchId', ${alias}.custom_data->>'branch_id')`. Replace every legacy `coalesce(<alias>.custom_data->>'branchId', <alias>.custom_data->>'branch_id')` with `${this.branchIdExpr('<alias>')}`, leaving the surrounding comparison/cast (`= $N::text`, `b.id::text = ...`) unchanged. Comparisons stay TEXT-based — do NOT cast the JSON side to uuid.
- Writes: dual-write. When the incoming `customDataPatch` contains a `branchId` (or `branch_id`) that is a valid UUID, also set the `branch_id` column (keep writing custom_data unchanged). Invalid/absent → leave the column untouched.
- **Deploy ordering (operational note, no action in this task):** this code references the `branch_id` column, so it must NOT be deployed to prod before migration `0027` is applied. The migration is prod-deferred and batched with the other Epic A migrations; nothing is pushed/deployed in this task.
- Conventions: schema `app.`; idempotent DDL (`add column if not exists`, `create index if not exists`). ALTER TABLE ADD COLUMN needs no new grants (table grants already cover new columns).
- Run from `server/`: migrations `npm run db:migrate` / `db:rollback`; tests `npm test`; types `npm run typecheck`.
- **Prod safety:** validate the migration ONLY against an ephemeral Docker Postgres (full chain 0001..0027), NEVER prod, NEVER `server/.env`/`.migration.env`.

---

## File Structure

- **Create** `server/db/migrations/0027_unified_branch_id.up.sql` / `.down.sql`.
- **Modify** `server/src/crm/crm.service.ts` — add the `branchIdExpr` helper; switch the ~15 read sites; dual-write in createLead/updateLead/createStudent/updateStudent.
- **Modify** `server/src/crm/crm.service.spec.ts` — tests for the read helper usage and the dual-write.

---

## Task 1: Migration 0027 — columns, indexes, guarded backfill

**Files:**
- Create: `server/db/migrations/0027_unified_branch_id.up.sql`
- Create: `server/db/migrations/0027_unified_branch_id.down.sql`

**Interfaces (DB produced):** `branch_id` on leads/students/payments/expenses/tasks/chats; `lead_id`, `student_id` on chats; partial/plain indexes.

- [ ] **Step 1: Write the up migration**

```sql
-- server/db/migrations/0027_unified_branch_id.up.sql
-- Promote branch from custom_data->>'branchId' to a real branch_id FK across
-- the CRM entities. Column stays nullable; backfilled from existing data.

alter table app.leads    add column if not exists branch_id uuid references app.branches(id);
alter table app.students add column if not exists branch_id uuid references app.branches(id);
alter table app.payments add column if not exists branch_id uuid references app.branches(id);
alter table app.expenses add column if not exists branch_id uuid references app.branches(id);
alter table app.tasks    add column if not exists branch_id uuid references app.branches(id);
alter table app.chats    add column if not exists branch_id uuid references app.branches(id);
alter table app.chats    add column if not exists lead_id uuid references app.leads(id);
alter table app.chats    add column if not exists student_id uuid references app.students(id);

create index if not exists leads_branch_id_idx    on app.leads (branch_id)    where deleted_at is null;
create index if not exists students_branch_id_idx on app.students (branch_id) where deleted_at is null;
create index if not exists tasks_branch_id_idx     on app.tasks (branch_id)    where deleted_at is null;
create index if not exists expenses_branch_id_idx  on app.expenses (branch_id) where deleted_at is null;
create index if not exists payments_branch_id_idx  on app.payments (branch_id);
create index if not exists chats_branch_id_idx     on app.chats (branch_id);
create index if not exists chats_lead_id_idx       on app.chats (lead_id);
create index if not exists chats_student_id_idx    on app.chats (student_id);

-- Backfill students from custom_data, guarded so the cast/FK can never fail.
update app.students s
set branch_id = (coalesce(s.custom_data->>'branchId', s.custom_data->>'branch_id'))::uuid
where s.branch_id is null
  and coalesce(s.custom_data->>'branchId', s.custom_data->>'branch_id')
      ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  and exists (
    select 1 from app.branches b
    where b.id = (coalesce(s.custom_data->>'branchId', s.custom_data->>'branch_id'))::uuid
  );

-- Backfill leads from custom_data (same guard).
update app.leads l
set branch_id = (coalesce(l.custom_data->>'branchId', l.custom_data->>'branch_id'))::uuid
where l.branch_id is null
  and coalesce(l.custom_data->>'branchId', l.custom_data->>'branch_id')
      ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  and exists (
    select 1 from app.branches b
    where b.id = (coalesce(l.custom_data->>'branchId', l.custom_data->>'branch_id'))::uuid
  );

-- Backfill payments from their student (after students are backfilled).
update app.payments p
set branch_id = s.branch_id
from app.students s
where p.branch_id is null and p.student_id = s.id and s.branch_id is not null;

-- Backfill tasks from their linked student / lead entity.
update app.tasks t
set branch_id = s.branch_id
from app.students s
where t.branch_id is null and t.entity_type = 'student' and t.entity_id = s.id and s.branch_id is not null;

update app.tasks t
set branch_id = l.branch_id
from app.leads l
where t.branch_id is null and t.entity_type = 'lead' and t.entity_id = l.id and l.branch_id is not null;
```

> Note: `app.payments` is referenced via `payments.student_id`. If `app.payments` has no `student_id` column in this schema, the implementer must confirm the real linking column during validation and adjust the payments backfill (or skip it, leaving payments.branch_id null) — report it as a concern rather than guessing.

- [ ] **Step 2: Write the down migration**

```sql
-- server/db/migrations/0027_unified_branch_id.down.sql
alter table app.chats    drop column if exists student_id;
alter table app.chats    drop column if exists lead_id;
alter table app.chats    drop column if exists branch_id;
alter table app.tasks    drop column if exists branch_id;
alter table app.expenses drop column if exists branch_id;
alter table app.payments drop column if exists branch_id;
alter table app.students drop column if exists branch_id;
alter table app.leads    drop column if exists branch_id;
```

- [ ] **Step 3: Validate on an ephemeral Docker Postgres (NOT prod)**

```bash
docker run --rm -d --name mmcrm-a4-pg -e POSTGRES_PASSWORD=test -e POSTGRES_DB=mmcrm_test -p 55434:5432 postgres:16
# wait: docker exec mmcrm-a4-pg pg_isready -U postgres  (retry until ready)
cd server && MIGRATION_DATABASE_URL='postgres://postgres:test@localhost:55434/mmcrm_test' DATABASE_URL='postgres://postgres:test@localhost:55434/mmcrm_test' npm run db:migrate
```
Expected last line includes `0027_unified_branch_id`. If `0020` fails on missing role `magiccrm_app`, pre-create it (`docker exec mmcrm-a4-pg psql -U postgres -d mmcrm_test -c "create role magiccrm_app"`) and re-run. Host MUST be `localhost:55434`; abort if anything targets a remote host. If migration `0027` itself fails (e.g. `payments.student_id` does not exist), STOP and report BLOCKED with the exact error.

- [ ] **Step 4: Verify columns + a seeded backfill case**

```bash
docker exec mmcrm-a4-pg psql -U postgres -d mmcrm_test -c "select table_name, column_name from information_schema.columns where table_schema='app' and column_name in ('branch_id','lead_id','student_id') and table_name in ('leads','students','payments','expenses','tasks','chats') order by table_name, column_name;"
# Seeded backfill: a branch + a student whose custom_data points at it must backfill; a garbage value must NOT throw and stays null.
docker exec mmcrm-a4-pg psql -U postgres -d mmcrm_test <<'SQL'
insert into app.branches (id, name) values ('11111111-1111-1111-1111-111111111111','TestBranch') on conflict do nothing;
insert into app.students (id, custom_data) values
  ('22222222-2222-2222-2222-222222222222', '{"branchId":"11111111-1111-1111-1111-111111111111"}'::jsonb),
  ('33333333-3333-3333-3333-333333333333', '{"branchId":"not-a-uuid"}'::jsonb);
-- Re-run only the students backfill statement (copy from up.sql) and check:
update app.students s
set branch_id = (coalesce(s.custom_data->>'branchId', s.custom_data->>'branch_id'))::uuid
where s.branch_id is null
  and coalesce(s.custom_data->>'branchId', s.custom_data->>'branch_id') ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  and exists (select 1 from app.branches b where b.id = (coalesce(s.custom_data->>'branchId', s.custom_data->>'branch_id'))::uuid);
select id, branch_id from app.students where id in ('22222222-2222-2222-2222-222222222222','33333333-3333-3333-3333-333333333333') order by id;
SQL
```
Expected: all 8 columns listed; the first student's `branch_id` = the TestBranch uuid; the garbage student's `branch_id` is NULL (no error thrown).

- [ ] **Step 5: Verify idempotency + reversibility, then clean up**

```bash
cd server && MIGRATION_DATABASE_URL='postgres://postgres:test@localhost:55434/mmcrm_test' DATABASE_URL='postgres://postgres:test@localhost:55434/mmcrm_test' npm run db:migrate    # Expected: Applied migrations: none
cd server && MIGRATION_DATABASE_URL='postgres://postgres:test@localhost:55434/mmcrm_test' DATABASE_URL='postgres://postgres:test@localhost:55434/mmcrm_test' npm run db:rollback   # Expected: Reverted migration: 0027_unified_branch_id
docker exec mmcrm-a4-pg psql -U postgres -d mmcrm_test -c "select 1 from information_schema.columns where table_schema='app' and table_name='leads' and column_name='branch_id';"  # Expected: 0 rows
cd server && MIGRATION_DATABASE_URL='postgres://postgres:test@localhost:55434/mmcrm_test' DATABASE_URL='postgres://postgres:test@localhost:55434/mmcrm_test' npm run db:migrate    # Re-apply
docker stop mmcrm-a4-pg
```

- [ ] **Step 6: Commit**

```bash
git add server/db/migrations/0027_unified_branch_id.up.sql server/db/migrations/0027_unified_branch_id.down.sql
git commit -m "feat(db): unified branch_id FK + backfill across CRM entities (KVA-187)"
```

---

## Task 2: Read switch via `branchIdExpr` helper

**Files:**
- Modify: `server/src/crm/crm.service.ts`
- Modify: `server/src/crm/crm.service.spec.ts`

**Interfaces:**
- Produces: `private branchIdExpr(alias: string): string` returning `coalesce(${alias}.branch_id::text, ${alias}.custom_data->>'branchId', ${alias}.custom_data->>'branch_id')`.

- [ ] **Step 1: Write the failing tests**

Add to `server/src/crm/crm.service.spec.ts`:

```typescript
  it("lead board branch filter prefers the branch_id column", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [] }, // statuses
      { rows: [] }, // board rows
    ]);
    await service.listLeadBoard(actor, { branchId: "b-1" } as never);
    const sql = query.mock.calls.map((c) => String(c[0])).join("\n");
    expect(sql).toContain("l.branch_id::text");
  });

  it("student search branch filter prefers the branch_id column", async () => {
    const { service, query } = createServiceWithQueryResults([{ rows: [] }]);
    await service.searchStudents(actor, { branchId: "b-1" } as never);
    const sql = query.mock.calls.map((c) => String(c[0])).join("\n");
    expect(sql).toContain("s.branch_id::text");
  });
```

> The exact arity of `createServiceWithQueryResults` for these methods may differ; the implementer adjusts the number of mocked `{ rows: [] }` results to match how many queries each method issues, keeping the assertion (SQL contains `<alias>.branch_id::text`).

- [ ] **Step 2: Run to verify failure**

Run: `cd server && npx jest src/crm/crm.service.spec.ts -t "branch_id column"`
Expected: FAIL — the SQL still contains only `custom_data->>'branchId'`, not `l.branch_id::text` / `s.branch_id::text`.

- [ ] **Step 3: Add the helper**

Add to `CrmService` in `server/src/crm/crm.service.ts` (near the other private SQL helpers):

```typescript
  // Transition-safe branch read: prefer the real branch_id column, fall back to
  // the legacy custom_data keys. Returns text to preserve the existing
  // text-based comparison semantics (no jsonb::uuid casts).
  private branchIdExpr(alias: string): string {
    return `coalesce(${alias}.branch_id::text, ${alias}.custom_data->>'branchId', ${alias}.custom_data->>'branch_id')`;
  }
```

- [ ] **Step 4: Replace every legacy branch read with the helper**

At EACH site below, replace the literal `coalesce(<alias>.custom_data->>'branchId', <alias>.custom_data->>'branch_id')` with `${this.branchIdExpr('<alias>')}`. Leave the surrounding comparison/cast (`= $N::text`, `b.id::text = ...`, `as branch_id`, `nullif(..., '')`) exactly as-is.

Shape A — dashboard `$3` filter (alias `s` for students, `l` for leads):
- `crm.service.ts:541`, `:549`, `:556`, `:563` (students, getManagerDashboard) — each `($3::uuid is null or coalesce(s.custom_data->>'branchId', s.custom_data->>'branch_id') = $3::text)` → `($3::uuid is null or ${this.branchIdExpr('s')} = $3::text)`.
- `crm.service.ts:571` (leads, getManagerDashboard) → `($3::uuid is null or ${this.branchIdExpr('l')} = $3::text)`.

Shape B — SELECT projection `... as branch_id`:
- `crm.service.ts:883` (searchStudents) `coalesce(s.custom_data->>'branchId', s.custom_data->>'branch_id') as branch_id` → `${this.branchIdExpr('s')} as branch_id`.
- `crm.service.ts:3914` (listLeadBoard) → `${this.branchIdExpr('l')} as branch_id`.
- `crm.service.ts:4022` (getLeadCard) → `${this.branchIdExpr('l')} as branch_id`.

Shape C — JOIN `on b.id::text = ...`:
- `crm.service.ts:921` (searchStudents) `on b.id::text = coalesce(s.custom_data->>'branchId', s.custom_data->>'branch_id')` → `on b.id::text = ${this.branchIdExpr('s')}`.
- `crm.service.ts:3949` (listLeadBoard) → `on b.id::text = ${this.branchIdExpr('l')}`.
- `crm.service.ts:4053` (getLeadCard) → `on b.id::text = ${this.branchIdExpr('l')}`.

Shape D — dynamic-param filters (alias as written):
- `crm.service.ts:4501` (buildStudentSearchFilter) `coalesce(s.custom_data->>'branchId', s.custom_data->>'branch_id') = ${p}::text` → `${this.branchIdExpr('s')} = ${p}::text`.
- `crm.service.ts:4650` (buildLeadBoardFilter) → `${this.branchIdExpr('l')} = ${p}::text`.

Shape E — listTasks combined student/lead branch (aliases `student`, `lead`):
- `crm.service.ts:3284-3285` (SELECT projection): replace each inner `coalesce(student.custom_data->>'branchId', student.custom_data->>'branch_id')` with `${this.branchIdExpr('student')}` and the `lead.` one with `${this.branchIdExpr('lead')}`.
- `crm.service.ts:3305-3306` (JOIN to branches): same two replacements.
- `crm.service.ts:3347-3348` (WHERE `$11` filter): same two replacements.

> Verify by grepping after the edit: `grep -n "custom_data->>'branchId'" server/src/crm/crm.service.ts` must return ZERO matches in SQL strings (the helper is now the only producer of that fragment).

- [ ] **Step 5: Run tests + typecheck**

Run: `cd server && npm run typecheck && npm test`
Expected: typecheck 0; the two new tests pass; full suite green (the existing branch-filter tests still pass because the helper still compares as text and still falls back to custom_data).

- [ ] **Step 6: Commit**

```bash
git add server/src/crm/crm.service.ts server/src/crm/crm.service.spec.ts
git commit -m "refactor(crm): read branch through branchIdExpr (column-preferring, jsonb fallback) (KVA-187)"
```

---

## Task 3: Dual-write the branch_id column

**Files:**
- Modify: `server/src/crm/crm.service.ts` (createLead, updateLead, createStudent, updateStudent)
- Modify: `server/src/crm/crm.service.spec.ts`

**Interfaces:**
- Produces: `private extractBranchId(patch: Record<string, unknown> | undefined | null): string | null` — returns the patch's `branchId`/`branch_id` if it is a valid UUID string, else null.

- [ ] **Step 1: Write the failing test**

Add to `server/src/crm/crm.service.spec.ts`:

```typescript
  it("dual-writes branch_id column when customDataPatch carries a branchId", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [{ id: "lead-1" }] },
    ]);
    await service.createLead(actor, {
      firstName: "A",
      customDataPatch: { branchId: "44444444-4444-4444-4444-444444444444" },
    } as never);
    const insert = query.mock.calls.map((c) => String(c[0])).find((s) => s.includes("insert into app.leads"));
    expect(insert).toContain("branch_id");
    const params = query.mock.calls.find((c) => String(c[0]).includes("insert into app.leads"))?.[1] as unknown[];
    expect(params).toContain("44444444-4444-4444-4444-444444444444");
  });
```

> The implementer confirms the exact mocked-result count `createLead` needs and the param position; the assertion is that the new branch_id param value appears and the insert column list includes `branch_id`.

- [ ] **Step 2: Run to verify failure**

Run: `cd server && npx jest src/crm/crm.service.spec.ts -t "dual-writes branch_id"`
Expected: FAIL — the insert does not include `branch_id`.

- [ ] **Step 3: Add the extractor helper**

Add to `CrmService` in `server/src/crm/crm.service.ts`:

```typescript
  private static readonly UUID_RE =
    /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

  // Pull a valid branch UUID out of a customDataPatch (branchId or branch_id),
  // for dual-writing the real column alongside the legacy json.
  private extractBranchId(
    patch: Record<string, unknown> | undefined | null,
  ): string | null {
    const raw = patch?.["branchId"] ?? patch?.["branch_id"];
    return typeof raw === "string" && CrmService.UUID_RE.test(raw) ? raw : null;
  }
```

- [ ] **Step 4: Dual-write in create/update for leads and students**

For each of `createLead`, `updateLead`, `createStudent`, `updateStudent`: compute `const branchId = this.extractBranchId(dto.customDataPatch);` and thread it into the SQL.

- `createLead` (insert at `crm.service.ts:4369-4373`, custom_data param `$9`): add `branch_id` to the column list and a new bind param; set it to the extracted value (or null). Pattern: append `, branch_id` to the columns, `, $N` to the values (N = next param index), and push `branchId` into the params array in the same position.
- `updateLead` (update at `crm.service.ts:4415` `custom_data = custom_data || $10::jsonb`): add `branch_id = coalesce($N::uuid, branch_id)` to the SET list (so a null extracted value leaves the existing column untouched), with `branchId` as the new `$N` param.
- `createStudent` (insert at `crm.service.ts:1013`, custom_data `$8`): same as createLead — add `branch_id` column + param.
- `updateStudent` (update at `crm.service.ts:1309` `custom_data = coalesce(s.custom_data, '{}'::jsonb) || $7::jsonb`): add `branch_id = coalesce($N::uuid, s.branch_id)` to the SET list with `branchId` as `$N`.

Keep all existing custom_data writes unchanged (dual-write, not replace). Use `coalesce($N::uuid, <existing>)` on UPDATE so an absent branchId never nulls an existing column value.

- [ ] **Step 5: Run tests + typecheck**

Run: `cd server && npm run typecheck && npm test`
Expected: typecheck 0; the dual-write test passes; full suite green.

- [ ] **Step 6: Commit**

```bash
git add server/src/crm/crm.service.ts server/src/crm/crm.service.spec.ts
git commit -m "feat(crm): dual-write branch_id column on lead/student create+update (KVA-187)"
```

---

## Self-Review

- **Spec coverage (§4A4):** branch_id FK on all 6 tables + chats lead_id/student_id ✅ (Task 1); guarded backfill ✅ (Task 1); reads prefer column with fallback ✅ (Task 2, all 15 sites enumerated); dual-write keeps custom_data in sync ✅ (Task 3); column left nullable, NOT NULL deferred to Epic F QA ✅ (stated).
- **Placeholder scan:** none — full SQL/TS/tests + exact site list with the uniform transform.
- **Transition safety:** the read helper returns text and falls back to custom_data, so queries work whether or not the prod backfill has run; the dual-write on UPDATE uses `coalesce($N::uuid, existing)` so it never nulls a populated column. No `jsonb::uuid` cast in any hot path (only in the one-time, regex+exists-guarded migration backfill).
- **Type consistency:** `branchIdExpr(alias)` / `extractBranchId(patch)` names used identically across helper, sites, and tests; the UUID regex is shared via `CrmService.UUID_RE`.
- **Risk note:** payments backfill assumes `payments.student_id`; the migration step flags this for confirmation rather than guessing.

## Dependency note

A4 unblocks every "by branch" report in Epic F (funnel, branch comparison, finance-by-branch, SLA-by-branch via chats), the per-branch Ученики board (Epic C), and the data-quality "students without branch" check. Migration `0027` is applied to prod later, batched with the other Epic A migrations, AFTER which this code may be deployed (deploy ordering: migrate, then deploy).
