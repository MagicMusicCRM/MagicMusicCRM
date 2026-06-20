# Lead-board cleanup — prod-data migration + board filter — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Spec **C3** — clean up the imported lead board: (1) remove the 3 empty legacy columns (**Контакт / Переговоры / Договор**) — only when they hold 0 leads (`status_id` FK is `on delete set null`); (2) migrate `NULL`-status leads («Без статуса») to the **«Новый»** status; (3) mark **«Успешный»** and **«Отказ»** as `is_terminal = true`, set **«Отказ».`requires_reason` = true** and recolor it to the danger color; (4) renumber the surviving statuses' `sort_order` to a dense `0..N`; (5) add a server-side board filter that **hides leads already converted to students** (linked via `students.lead_id`, OR a phone+name match against an active student) so converted leads stop polluting the board.

**Architecture:** The lead statuses come from the **prod import** (a fresh Docker DB has zero rows in `app.lead_statuses` and `app.leads`), so the cleanup is a single **idempotent, guarded data migration** `0032_lead_board_cleanup` that **no-ops on absent data** — every statement keys off `name`/`color` lookups and `not exists`/count guards, never hardcoded ids. The board-hide is a code change: a new optional `hideConverted` flag on `LeadBoardQuery` consumed by `buildLeadBoardFilter` (`server/src/crm/crm.service.ts:4741`), exercised by `listLeadBoard` (`:3898`), unit-tested against the existing `crm.service.spec.ts` harness. **Validation is prod-shaped:** the migration is Docker-validated against a seeded fixture only (never prod); the gated prod apply is documented, not executed by this plan.

**Tech Stack:** NestJS + `pg`, PostgreSQL. Migrations: numbered `NNNN_name.up.sql` / `.down.sql` run by `server/src/db/migration-runner.ts` (each file runs in one `begin/commit`). Server tests: `jest` (`npm test` from `server/`).

## Global Constraints

- **Schema facts (verified):** `app.lead_statuses` has columns `id, name (unique), sort_order, created_at` (`0002_profile_crm.up.sql:56`), plus `color text` (`0010_lead_management.up.sql:1`), plus `is_terminal boolean not null default false` and `requires_reason boolean not null default false` (`0026_crm_dictionaries.up.sql:20-21`). **There is no `deleted_at` and no `is_active` on `lead_statuses`** — so "remove a column" = **hard `delete`** of the `lead_statuses` row. `app.leads.status_id` is `uuid references app.lead_statuses(id) on delete set null` (`0002:65`) — deleting a status with leads would silently orphan them, hence the **0-leads guard is mandatory**.
- **Convert-detection facts (verified):** `app.students` has `lead_id uuid references app.leads(id) on delete set null` (`0002:82`) and `profile_id uuid references app.profiles(id)` (`0002:81`); students carry **no phone/name directly** — phone+name live on the linked `app.profiles` row, which has `phone_normalized` (`0025_phone_normalization.up.sql:4`) and `first_name`/`last_name`. `app.leads` has `phone_normalized` (`0025:3`). `listLeadBoard` already left-joins `app.students linked_student on linked_student.lead_id = l.id and linked_student.deleted_at is null` (`crm.service.ts:3969-3971`).
- **Idempotency:** every migration statement must be safe to run twice and on an empty DB. Use name/color lookups (`where ls.name = '…'`), `not exists`, count guards, and `coalesce`. Never reference a hardcoded uuid. Color of «Отказ» is set only if not already the target.
- **Danger color:** the codebase has no server-side color constant; the Flutter danger red is `#E53935` (used as the lead-board danger swatch). Use literal `'#E53935'` in SQL with an inline comment.
- **Migration runner:** files are discovered by `*.up.sql` glob, sorted lexically, each applied inside `begin`/`commit` (`migration-runner.ts:26-41`). No DO-block transaction control needed; raw statements are fine. Mirror the `do $$ … grant … $$` role-guard footer from `0025`/`0026` only if new grants are needed — **none are** (no new tables), so omit it.
- **Filter shape:** `buildLeadBoardFilter` builds a `{ where, params }` pair with a local `add(value)` that pushes a param and returns `$N` (`crm.service.ts:4742-4747`). The board query references table alias `l` (leads) and `ls` (lead_statuses) — both are in scope in the count query (`:3917`), the lead CTE (`:3963`), AND the `getLeadCard` join, but `getLeadCard` does **not** call `buildLeadBoardFilter`, so the new predicate only affects the board lists.
- **Run from `server/`:** `npm test` (full suite ~279, must stay green) and `npm run build` (tsc, must compile).

---

## File Structure

- **Create** `server/db/migrations/0032_lead_board_cleanup.up.sql` — the guarded prod-data cleanup.
- **Create** `server/db/migrations/0032_lead_board_cleanup.down.sql` — best-effort, documented-irreversible note + flag/color revert.
- **Modify** `server/src/crm/dto/lead-board.query.ts` — add the optional `hideConverted` boolean.
- **Modify** `server/src/crm/crm.service.ts` — consume `hideConverted` in `buildLeadBoardFilter` (`:4741`).
- **Modify** `server/src/crm/crm.service.spec.ts` — unit tests for the filter (added rows; no behavior change to the existing board test).
- **Create** `server/db/migrations/__fixtures__/0032_lead_board_cleanup.seed.sql` — a tiny seed used only for Docker validation (NOT auto-run; referenced from the validation step).

---

## Task 1: The guarded prod-data migration `0032_lead_board_cleanup`

**Files:**
- Create: `server/db/migrations/0032_lead_board_cleanup.up.sql`, `server/db/migrations/0032_lead_board_cleanup.down.sql`, `server/db/migrations/__fixtures__/0032_lead_board_cleanup.seed.sql`

**Interfaces (produces):** a migration that, given imported prod data, leaves `app.lead_statuses` with no empty legacy columns, dense `sort_order`, terminal/requires-reason/color flags set, and zero `NULL`-status leads — and that is a no-op on an empty DB.

- [ ] **Step 1: Read the patterns to mirror**

Read these so the SQL matches house style exactly:
- `0026_crm_dictionaries.up.sql:69-103` — the `insert … select … where not exists (…)` idempotent-seed idiom.
- `0027_unified_branch_id.up.sql:23-61` — guarded `update` backfills (regex/exists guards so casts can't fail).
- `0018_seed_system_admin_staff.up.sql` — `with … as (…)` CTE upsert idiom + name-based lookups (no hardcoded ids).
- `migration-runner.ts:26-41` — each file is one transaction; ordering by filename.

- [ ] **Step 2: Write `0032_lead_board_cleanup.up.sql`**

Every statement is guarded. Order matters: **migrate NULL leads → flag/recolor terminals → delete empty legacy columns (0-leads only) → dense renumber.** Deleting before re-pointing would risk re-orphaning; the NULL-migration runs first so the «Новый» column exists.

```sql
-- server/db/migrations/0032_lead_board_cleanup.up.sql
-- Spec C3 lead-board cleanup. IDEMPOTENT + GUARDED: every statement no-ops on an
-- empty DB (fresh Docker has zero lead_statuses/leads — all rows come from the prod
-- import). Keyed on status NAME, never on a hardcoded uuid. Safe to re-run.

-- (1) Migrate NULL-status leads ('Без статуса') -> the «Новый» status, but only if a
--     «Новый» status actually exists (import present). No-op on empty DB.
update app.leads l
set status_id = ns.id,
    updated_at = now()
from app.lead_statuses ns
where ns.name = 'Новый'
  and l.status_id is null
  and l.deleted_at is null;

-- (2) Mark terminal statuses. is_terminal := true for «Успешный» and «Отказ».
update app.lead_statuses
set is_terminal = true
where name in ('Успешный', 'Отказ')
  and is_terminal is distinct from true;

-- (2a) «Отказ» also requires a loss reason on transition.
update app.lead_statuses
set requires_reason = true
where name = 'Отказ'
  and requires_reason is distinct from true;

-- (2b) Recolor «Отказ» -> danger red (#E53935), only if not already that color.
update app.lead_statuses
set color = '#E53935'  -- danger swatch (matches the Flutter lead-board danger color)
where name = 'Отказ'
  and color is distinct from '#E53935';

-- (3) Remove the 3 empty legacy columns. HARD delete (no deleted_at on lead_statuses),
--     guarded so a status that still holds ANY lead is never deleted (FK is
--     'on delete set null' — deleting a non-empty status would silently orphan leads).
delete from app.lead_statuses ls
where ls.name in ('Контакт', 'Переговоры', 'Договор')
  and not exists (
    select 1 from app.leads l
    where l.status_id = ls.id  -- includes soft-deleted leads on purpose: never orphan
  );

-- (4) Dense renumber sort_order 0..N over the survivors, preserving the existing order
--     (sort_order, then name) so the board column order is stable. CTE keeps it
--     deterministic and idempotent (re-running yields the same 0..N).
with ordered as (
  select id,
    (row_number() over (order by sort_order asc, name asc, id asc) - 1) as new_order
  from app.lead_statuses
)
update app.lead_statuses ls
set sort_order = ordered.new_order
from ordered
where ordered.id = ls.id
  and ls.sort_order is distinct from ordered.new_order;
```

**Design notes to keep in the file's intent:**
- The delete guard intentionally counts **all** leads (including soft-deleted) on the legacy status — a soft-deleted lead still FK-references the status, and `on delete set null` would mutate it. If a legacy column is genuinely empty in prod it deletes; otherwise it is left in place and the cleanup is a partial no-op (logged at apply time, see Step 6).
- `is distinct from` (not `=`/`<>`) so the guards behave correctly against the `not null default false` flag columns and the nullable `color`.

- [ ] **Step 3: Write `0032_lead_board_cleanup.down.sql`**

The deletes and the NULL→«Новый» remap are **not losslessly reversible** (the original `status_id` per lead is gone; deleted statuses had server-generated uuids). Document that and revert only what is mechanically safe — the terminal/requires-reason/color flags. Mirror `0031_analytics.down.sql`'s terse style.

```sql
-- server/db/migrations/0032_lead_board_cleanup.down.sql
-- NOTE: data cleanup is largely irreversible — the per-lead original status_id and the
-- deleted legacy statuses (Контакт/Переговоры/Договор) cannot be reconstructed. We only
-- revert the flag/color changes that are mechanically safe; renumbering and the
-- delete/remap are left as-is by design.
update app.lead_statuses set requires_reason = false where name = 'Отказ';
update app.lead_statuses set is_terminal = false where name in ('Успешный', 'Отказ');
```

(Do not re-insert the legacy statuses or recolor back — that would fabricate ids/colors that never matched prod.)

- [ ] **Step 4: Write the Docker validation fixture**

`server/db/migrations/__fixtures__/0032_lead_board_cleanup.seed.sql` — a minimal, realistic prod-shaped seed (NOT auto-discovered: it lives under `__fixtures__/`, not `migrations/` root, so the runner's `*.up.sql` glob ignores it). Used only by Step 5.

```sql
-- Fixture for Docker validation of 0032 (run AFTER 0031, BEFORE 0032).
insert into app.lead_statuses (name, sort_order, color, is_terminal, requires_reason) values
  ('Новый', 10, '#C5A059', false, false),
  ('Контакт', 20, null, false, false),       -- legacy, will be empty -> deleted
  ('Переговоры', 30, null, false, false),     -- legacy, empty -> deleted
  ('Договор', 40, null, false, false),        -- legacy, NON-empty below -> NOT deleted
  ('Успешный', 50, '#43A047', false, false),
  ('Отказ', 60, '#888888', false, false);

-- One lead with NULL status (-> migrates to «Новый»).
insert into app.leads (first_name, last_name, phone) values ('Без', 'Статуса', '+70000000001');
-- One lead pinned to «Договор» so that legacy column is NON-empty (must survive).
insert into app.leads (status_id, first_name, last_name)
select id, 'Имеет', 'Договор' from app.lead_statuses where name = 'Договор';
```

- [ ] **Step 5: Docker validation (the gated apply rehearsal)**

Run against a **disposable Docker Postgres** only. From `server/`:

```bash
# 1. Bring up a throwaway pg, apply all migrations through 0031 (the app's runner or psql).
# 2. Load the fixture, then apply ONLY 0032:
psql "$DATABASE_URL" -f db/migrations/__fixtures__/0032_lead_board_cleanup.seed.sql
psql "$DATABASE_URL" -1 -f db/migrations/0032_lead_board_cleanup.up.sql
# 3. Assert post-conditions:
psql "$DATABASE_URL" -c "select name, sort_order, is_terminal, requires_reason, color from app.lead_statuses order by sort_order;"
# expect: Контакт+Переговоры GONE; Договор PRESENT (had a lead); sort_order dense 0..N;
#         Отказ is_terminal+requires_reason=true, color='#E53935'; Успешный is_terminal=true.
psql "$DATABASE_URL" -c "select count(*) from app.leads where status_id is null and deleted_at is null;"  -- expect 0
# 4. IDEMPOTENCY: re-run 0032 up; assert the SAME output (no further deletes, sort_order unchanged).
psql "$DATABASE_URL" -1 -f db/migrations/0032_lead_board_cleanup.up.sql
# 5. EMPTY-DB no-op: on a fresh pg with migrations 0001..0031 and NO fixture, apply 0032 -> 0 rows affected, no error.
```

Record the assertions as passed in the commit body. **Never run against prod from this plan** — the prod apply is the operator's gated step (Step 6).

- [ ] **Step 6: Document the gated prod apply (no execution)**

In the migration file's header comment block (already added in Step 2) the idempotency contract is stated. Add a one-paragraph operator note to the commit message: prod apply runs the standard runner (`0032` picked up automatically after deploy), is wrapped in the runner's transaction, and — because the legacy-column delete is 0-leads-guarded — is safe to run even if an operator earlier hand-cleaned some columns. If a legacy column is unexpectedly non-empty in prod, the migration leaves it and the operator reassigns those leads manually, then re-runs (idempotent).

- [ ] **Step 7: Commit**

```bash
git add server/db/migrations/0032_lead_board_cleanup.up.sql \
        server/db/migrations/0032_lead_board_cleanup.down.sql \
        server/db/migrations/__fixtures__/0032_lead_board_cleanup.seed.sql
git commit -m "feat(db): 0032 lead-board cleanup — guarded idempotent prod-data migration (C3)"
```

---

## Task 2: `hideConverted` board filter (DTO + `buildLeadBoardFilter` + tests)

**Files:**
- Modify: `server/src/crm/dto/lead-board.query.ts`, `server/src/crm/crm.service.ts`, `server/src/crm/crm.service.spec.ts`

**Interfaces (produces):** `LeadBoardQuery.hideConverted?: boolean`; when true, `buildLeadBoardFilter` appends a predicate that excludes leads with a linked active student (via `students.lead_id`) OR a phone+name match against an active student's profile.

**Interfaces (consumes):** the existing `buildLeadBoardFilter` `add()`/`filters[]` mechanics (`crm.service.ts:4742-4747`); `app.students.lead_id` (`0002:82`); `app.profiles.phone_normalized`/`first_name`/`last_name` (`0025:4`); `app.leads.phone_normalized` (`0025:3`).

- [ ] **Step 1: Add the DTO flag**

In `server/src/crm/dto/lead-board.query.ts`, mirror the existing `openTasks` boolean (`:85-88`) — same `@Transform` coercion so `?hideConverted=true` string-or-bool both work:

```ts
  @IsOptional()
  @Transform(({ value }) => value === true || value === "true")
  @IsBoolean()
  hideConverted?: boolean;
```

Add it right after the `openTasks` block (`:88`). No new imports (`Transform`, `IsBoolean`, `IsOptional` already imported `:1-13`).

- [ ] **Step 2: Write the failing tests**

In `server/src/crm/crm.service.spec.ts`, add two tests in the `CrmService` describe block (mirror the existing board test at `:1767` and the `createServiceWithQueryResults` 3-result shape — statuses, counts, leads). The filter is built into the **count** query (call index 1) and the **lead** query (call index 2); assert the SQL fragment is present/absent. Keep them minimal — assert the WHERE text, not full board output.

```ts
it("hides converted leads from the board when hideConverted is set", async () => {
  const { service, query } = createServiceWithQueryResults([
    { rows: [] }, // statuses
    { rows: [] }, // counts
    { rows: [] }, // leads
  ]);
  await service.listLeadBoard(actor, { hideConverted: true });
  // count query (call 1) and lead query (call 2) both carry the predicate
  expect(query.mock.calls[1][0]).toContain("from app.students");
  expect(query.mock.calls[1][0]).toContain("linked_conv.lead_id = l.id");
  expect(query.mock.calls[1][0]).toContain("p_conv.phone_normalized = l.phone_normalized");
  expect(query.mock.calls[2][0]).toContain("not exists");
});

it("does not add the converted filter by default", async () => {
  const { service, query } = createServiceWithQueryResults([
    { rows: [] },
    { rows: [] },
    { rows: [] },
  ]);
  await service.listLeadBoard(actor, {});
  expect(query.mock.calls[2][0]).not.toContain("linked_conv.lead_id = l.id");
});
```

- [ ] **Step 3: Run to verify failure** — from `server/`: `npm test -- crm.service.spec` → FAIL (predicate not emitted; `linked_conv` absent).

- [ ] **Step 4: Implement the filter**

In `buildLeadBoardFilter` (`crm.service.ts:4741`), add the predicate after the `openTasks` block (`:4828`) and before the cursor block (`:4829`). It uses `not exists` against `app.students` so it cannot duplicate rows. Two convert signals: (a) a direct `students.lead_id` link; (b) a phone+name match against the student's profile (the canonical phone + a case-insensitive trimmed name match), restricted to active, non-deleted students. No params needed (correlated subquery only references `l`).

```ts
    if (query.hideConverted === true) {
      filters.push(`
        not exists (
          select 1
          from app.students linked_conv
          left join app.profiles p_conv
            on p_conv.id = linked_conv.profile_id
           and p_conv.deleted_at is null
          where linked_conv.deleted_at is null
            and linked_conv.status = 'active'
            and (
              linked_conv.lead_id = l.id
              or (
                l.phone_normalized is not null
                and p_conv.phone_normalized = l.phone_normalized
                and lower(btrim(coalesce(p_conv.first_name, ''))) = lower(btrim(coalesce(l.first_name, '')))
                and lower(btrim(coalesce(p_conv.last_name, '')))  = lower(btrim(coalesce(l.last_name, '')))
              )
            )
        )
      `);
    }
```

Notes embodied here:
- `status = 'active'` mirrors the students-table default/active convention (`students.status` default `'active'`, `0002:83`) so a withdrawn ex-student doesn't permanently hide a re-engaged lead.
- The phone arm requires BOTH a matching canonical phone (`phone_normalized`, populated by `0025`) AND first+last name — phone-only would over-hide shared family numbers. `l.phone_normalized is not null` short-circuits leads with no canonical phone (the `students.lead_id` arm still applies to them).
- No `add()` call → no new param; safe for both the count and lead queries which share `buildLeadBoardFilter`.

- [ ] **Step 5: Run tests + build** — from `server/`: `npm test -- crm.service.spec` → green; then `npm test` (full ~279 suite stays green — the existing board test at `:1767` is unaffected because it never sets `hideConverted`); then `npm run build` (tsc compiles the new DTO field).

- [ ] **Step 6: Commit**

```bash
git add server/src/crm/dto/lead-board.query.ts server/src/crm/crm.service.ts server/src/crm/crm.service.spec.ts
git commit -m "feat(crm): hideConverted lead-board filter — exclude leads converted to students (C3)"
```

---

## Self-Review

- **Coverage vs spec C3:** (1) legacy columns removed — Task 1 delete, 0-leads-guarded; (2) NULL→«Новый» — Task 1 update #1; (3) terminal flags + requires_reason + recolor «Отказ» — Task 1 updates #2/#2a/#2b; (4) dense `sort_order 0..N` — Task 1 update #4; (5) hide converted leads — Task 2 filter. All five spec bullets land.
- **Idempotency + empty-DB no-op:** every Task-1 statement keys on `name`/`color` with `is distinct from`/`not exists`/count guards; on a fresh Docker DB (no statuses, no leads) all statements affect 0 rows and the file commits cleanly. Re-running yields identical output (validated Step 5 idempotency + empty-DB checks). No hardcoded uuids.
- **Safety of the delete:** the FK `on delete set null` (`0002:65`) means deleting a non-empty status would silently orphan leads — the `not exists` guard counts ALL leads (incl. soft-deleted) on the status, so a column with any lead is never deleted. Worst case is a partial, re-runnable no-op, never data loss.
- **Prod-shaped validation, not prod execution:** the migration is validated against a Docker fixture (`__fixtures__/…seed.sql`) covering the delete, the survive-because-non-empty case, the NULL remap, the flags, and the dense renumber; the gated prod apply is documented (Task 1 Step 6) and left to the operator. Per project rules, migrations are Docker-validated only, never run against prod here.
- **Filter correctness:** `hideConverted` is opt-in (default off → existing board test `:1767` and all current callers unchanged); it uses `not exists` (no row duplication) and a conservative phone+name match (both phone AND full name) to avoid over-hiding; it's emitted into both the count and lead queries since they share `buildLeadBoardFilter`, keeping column totals consistent with visible items.
- **Reuse, not reinvent:** SQL mirrors `0026`/`0027`/`0018` guard idioms; the DTO field mirrors `openTasks`; the test mirrors the existing board test harness (`createServiceWithQueryResults`, 3-result shape). No new tables → no new grants → no `do $$ grant $$` footer.

## Dependency / sequencing notes

- **Ordering:** Task 1 (migration) and Task 2 (filter) are independent and can land in either order; the Flutter board UI that surfaces the `hideConverted` toggle is a separate downstream Flutter sub-plan (add the query param in `magic_crm_service.dart`'s `listLeadBoard` and a board-header switch). This plan stops at the backend.
- **«Новый» status assumption:** the NULL-remap (Task 1 update #1) targets a status literally named `'Новый'`. If the prod import named it differently (e.g. `'Новая'` / `'New'`), confirm the exact imported name via `select name from app.lead_statuses order by sort_order;` during the gated apply and adjust the single literal before applying — the migration no-ops (leaves NULLs) rather than mis-assigning if the name doesn't match, which is the safe failure mode.
- **No controller change:** `LeadBoardQuery` flows straight through `@Query()` in `crm.controller.ts:588`; adding the DTO field is sufficient for the endpoint to accept `?hideConverted=true`.
