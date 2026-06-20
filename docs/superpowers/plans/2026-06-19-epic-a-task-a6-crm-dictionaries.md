# Epic A · Task A6 — CRM Dictionaries (loss reasons, sources, disciplines) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the free-text/HolliHop-only dictionaries into first-class local tables — lead loss/pause reasons, normalized lead sources, and disciplines with per-branch ordering and per-student primary direction — plus read and config endpoints.

**Architecture:** One numbered migration (`0026_crm_dictionaries`) adds five dictionary tables + two `lead_statuses` flags + idempotent seed. Read endpoints expose them; write endpoints let an admin create/assign/reorder. The student↔discipline `is_primary` link is *written* by Epic B (reimport) and Epic C (conversion), not by a standalone endpoint here — A6 only provides the table + read.

**Tech Stack:** NestJS + TypeScript, PostgreSQL (numbered up/down SQL migrations via `MigrationRunner`), class-validator DTOs, Jest (`jest --runInBand`).

**Linear:** KVA-189 (A6) under epic KVA-178 (A). Spec: `docs/superpowers/specs/2026-06-19-clients-window-and-management-analytics-design.md` (§4A6).

## Global Constraints

- Migration id is **`0026_crm_dictionaries`** (next free number after `0025_phone_normalization`).
- New tables: `app.lead_loss_reasons`, `app.lead_sources`, `app.disciplines`, `app.branch_disciplines`, `app.student_disciplines`. New `app.lead_statuses` columns: `is_terminal boolean not null default false`, `requires_reason boolean not null default false`.
- `app.student_disciplines` MUST enforce **at most one primary discipline per student** via a partial unique index `(student_id) where is_primary and deleted_at is null`.
- Seeds MUST be idempotent — guard each seed `insert ... select ... where not exists (select 1 from <table>)` (re-running the migration does not duplicate rows). Seed loss reasons from §6 of the spec; seed lead sources from §9.
- Conventions: schema prefix `app.`; `id uuid primary key default gen_random_uuid()`; idempotent DDL (`create table if not exists`, `add column if not exists`, `create index if not exists`); EVERY new table ends with a `grant select, insert, update, delete ... to magiccrm_app` block guarded by `if exists (select 1 from pg_roles where rolname = 'magiccrm_app')`.
- DTOs use class-validator (`@IsString`, `@MaxLength`, `@IsOptional`, `@IsInt`, `@Min`, `@IsUUID`, `@IsIn`, `@IsArray`), mirroring `server/src/crm/dto/upsert-lead-status.dto.ts`.
- Policy: read endpoints call `this.policy.assertCanReadOperationalData(actor)`; write endpoints call `this.policy.assertCanWriteCrm(actor)`.
- Run from `server/`: migrations `npm run db:migrate` / `db:rollback`; tests `npm test`; types `npm run typecheck`.
- **Prod safety:** validate the migration ONLY against an ephemeral Docker Postgres (full chain 0001..0026), NEVER against `api.phantom-net.ru` and NEVER using `server/.env` / `server/.migration.env`. Pass the throwaway connection string inline on every migrate command.

---

## File Structure

- **Create** `server/db/migrations/0026_crm_dictionaries.up.sql` / `.down.sql` — the five tables, two flags, seed, grants.
- **Create** `server/src/crm/dto/create-discipline.dto.ts`, `upsert-branch-discipline.dto.ts`, `reorder-branch-disciplines.dto.ts`, `create-loss-reason.dto.ts`.
- **Modify** `server/src/crm/crm.service.ts` — add read methods (`listLossReasons`, `listLeadSources`, `listDisciplines`, `listBranchDisciplines`) and write methods (`createDiscipline`, `createLossReason`, `assignBranchDiscipline`, `reorderBranchDisciplines`).
- **Modify** `server/src/crm/crm.controller.ts` — add the GET/POST/PATCH routes.
- **Modify** `server/src/crm/crm.service.spec.ts` — add tests for the new methods.

---

## Task 1: Migration 0026 — dictionary tables, flags, seed

**Files:**
- Create: `server/db/migrations/0026_crm_dictionaries.up.sql`
- Create: `server/db/migrations/0026_crm_dictionaries.down.sql`

**Interfaces (DB produced):** tables `app.lead_loss_reasons`, `app.lead_sources`, `app.disciplines`, `app.branch_disciplines`, `app.student_disciplines`; columns `app.lead_statuses.is_terminal`, `app.lead_statuses.requires_reason`.

- [ ] **Step 1: Write the up migration**

```sql
-- server/db/migrations/0026_crm_dictionaries.up.sql
-- CRM dictionaries: loss reasons, lead sources, disciplines (+ per-branch order,
-- per-student primary), and terminal/requires-reason flags on lead statuses.

create table if not exists app.lead_loss_reasons (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  kind text not null default 'lost',
  sort_order integer not null default 0,
  is_active boolean not null default true,
  color text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint lead_loss_reasons_kind_check check (kind in ('lost', 'paused'))
);
create unique index if not exists lead_loss_reasons_name_kind_idx
  on app.lead_loss_reasons (lower(name), kind) where deleted_at is null;

alter table app.lead_statuses add column if not exists is_terminal boolean not null default false;
alter table app.lead_statuses add column if not exists requires_reason boolean not null default false;

create table if not exists app.lead_sources (
  id uuid primary key default gen_random_uuid(),
  canonical_name text not null,
  display_name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);
create unique index if not exists lead_sources_canonical_idx
  on app.lead_sources (lower(canonical_name)) where deleted_at is null;

create table if not exists app.disciplines (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create unique index if not exists disciplines_name_idx
  on app.disciplines (lower(name)) where deleted_at is null;

create table if not exists app.branch_disciplines (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references app.branches(id) on delete cascade,
  discipline_id uuid not null references app.disciplines(id) on delete cascade,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint branch_disciplines_unique unique (branch_id, discipline_id)
);
create index if not exists branch_disciplines_branch_idx
  on app.branch_disciplines (branch_id, sort_order) where deleted_at is null;

create table if not exists app.student_disciplines (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references app.students(id) on delete cascade,
  discipline_id uuid not null references app.disciplines(id) on delete cascade,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint student_disciplines_unique unique (student_id, discipline_id)
);
create unique index if not exists student_disciplines_one_primary_idx
  on app.student_disciplines (student_id) where is_primary and deleted_at is null;

-- Seed loss/pause reasons (idempotent: only when table empty).
insert into app.lead_loss_reasons (name, kind, sort_order)
select name, kind, sort_order
from (values
  ('Дорого', 'lost', 1),
  ('Неудобное расписание', 'lost', 2),
  ('Нет нужного преподавателя', 'lost', 3),
  ('Выбрали конкурента', 'lost', 4),
  ('Не отвечает', 'lost', 5),
  ('Передумал', 'lost', 6),
  ('Дубль', 'lost', 7),
  ('Нецелевой лид', 'lost', 8),
  ('Филиал далеко', 'lost', 9),
  ('Пауза (семейные обстоятельства)', 'paused', 10),
  ('Другое', 'lost', 99)
) as v(name, kind, sort_order)
where not exists (select 1 from app.lead_loss_reasons);

-- Seed lead sources (idempotent: only when table empty).
insert into app.lead_sources (canonical_name, display_name, is_active)
select canonical_name, display_name, true
from (values
  ('site', 'Сайт'),
  ('ads', 'Реклама'),
  ('referral', 'Рекомендации'),
  ('social', 'Соцсети'),
  ('messenger', 'Мессенджер'),
  ('call', 'Звонок'),
  ('offline', 'Офлайн'),
  ('partners', 'Партнёры'),
  ('repeat', 'Повторное обращение'),
  ('app', 'Через приложение'),
  ('chat', 'Чат')
) as v(canonical_name, display_name)
where not exists (select 1 from app.lead_sources);

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert, update, delete on app.lead_loss_reasons to magiccrm_app;
    grant select, insert, update, delete on app.lead_sources to magiccrm_app;
    grant select, insert, update, delete on app.disciplines to magiccrm_app;
    grant select, insert, update, delete on app.branch_disciplines to magiccrm_app;
    grant select, insert, update, delete on app.student_disciplines to magiccrm_app;
  end if;
end $$;
```

- [ ] **Step 2: Write the down migration**

```sql
-- server/db/migrations/0026_crm_dictionaries.down.sql
drop table if exists app.student_disciplines;
drop table if exists app.branch_disciplines;
drop table if exists app.disciplines;
drop table if exists app.lead_sources;
drop table if exists app.lead_loss_reasons;
alter table app.lead_statuses drop column if exists requires_reason;
alter table app.lead_statuses drop column if exists is_terminal;
```

- [ ] **Step 3: Validate on an ephemeral Docker Postgres (NOT prod)**

```bash
docker run --rm -d --name mmcrm-a6-pg -e POSTGRES_PASSWORD=test -e POSTGRES_DB=mmcrm_test -p 55433:5432 postgres:16
# wait until ready: docker exec mmcrm-a6-pg pg_isready -U postgres   (retry until ready)
cd server && MIGRATION_DATABASE_URL='postgres://postgres:test@localhost:55433/mmcrm_test' DATABASE_URL='postgres://postgres:test@localhost:55433/mmcrm_test' npm run db:migrate
```
Expected last line includes `0026_crm_dictionaries`. If migration `0020` fails because role `magiccrm_app` is absent, pre-create it (`docker exec mmcrm-a6-pg psql -U postgres -d mmcrm_test -c "create role magiccrm_app"`) and re-run — this replicates the prod precondition (known pre-existing chain quirk). The connection host MUST be `localhost:55433`; if anything targets `phantom-net`, ABORT.

- [ ] **Step 4: Verify schema, seed, and the one-primary guard**

```bash
docker exec mmcrm-a6-pg psql -U postgres -d mmcrm_test -c "select count(*) as reasons from app.lead_loss_reasons; select count(*) as sources from app.lead_sources;"
docker exec mmcrm-a6-pg psql -U postgres -d mmcrm_test -c "select column_name from information_schema.columns where table_schema='app' and table_name='lead_statuses' and column_name in ('is_terminal','requires_reason') order by column_name;"
# one-primary guard: two primaries for the same student must be rejected.
docker exec mmcrm-a6-pg psql -U postgres -d mmcrm_test -c "insert into app.disciplines(name) values ('T1') returning id;"
```
Expected: `reasons` = 11, `sources` = 11; both `is_terminal` and `requires_reason` listed. Then confirm the partial unique index exists: `\d app.student_disciplines` shows `student_disciplines_one_primary_idx ... WHERE is_primary AND deleted_at IS NULL`.

- [ ] **Step 5: Verify idempotency + reversibility**

```bash
cd server && MIGRATION_DATABASE_URL='postgres://postgres:test@localhost:55433/mmcrm_test' DATABASE_URL='postgres://postgres:test@localhost:55433/mmcrm_test' npm run db:migrate   # Expected: Applied migrations: none
# Re-run the seed guard check — counts unchanged (still 11 / 11).
cd server && MIGRATION_DATABASE_URL='postgres://postgres:test@localhost:55433/mmcrm_test' DATABASE_URL='postgres://postgres:test@localhost:55433/mmcrm_test' npm run db:rollback   # Expected: Reverted migration: 0026_crm_dictionaries
docker exec mmcrm-a6-pg psql -U postgres -d mmcrm_test -c "select to_regclass('app.disciplines');"   # Expected: NULL (table gone)
cd server && MIGRATION_DATABASE_URL='postgres://postgres:test@localhost:55433/mmcrm_test' DATABASE_URL='postgres://postgres:test@localhost:55433/mmcrm_test' npm run db:migrate   # Re-apply
docker stop mmcrm-a6-pg
```

- [ ] **Step 6: Commit**

```bash
git add server/db/migrations/0026_crm_dictionaries.up.sql server/db/migrations/0026_crm_dictionaries.down.sql
git commit -m "feat(db): CRM dictionaries — loss reasons, sources, disciplines (KVA-189)"
```

---

## Task 2: Read endpoints for the dictionaries

**Files:**
- Modify: `server/src/crm/crm.service.ts` (add four read methods near `listLeadStatuses`)
- Modify: `server/src/crm/crm.controller.ts` (add four GET routes)
- Modify: `server/src/crm/crm.service.spec.ts` (add tests)

**Interfaces:**
- Produces:
  - `listLossReasons(actor): Promise<{ items: Array<{ id; name; kind; sortOrder; color: string | null }> }>`
  - `listLeadSources(actor): Promise<{ items: Array<{ id; canonicalName; displayName }> }>`
  - `listDisciplines(actor): Promise<{ items: Array<{ id; name }> }>`
  - `listBranchDisciplines(actor, branchId): Promise<{ items: Array<{ id; disciplineId; name; sortOrder }> }>`
  - Routes `GET /crm/loss-reasons`, `GET /crm/lead-sources`, `GET /crm/disciplines`, `GET /crm/branches/:branchId/disciplines`.

- [ ] **Step 1: Write the failing tests**

Add to `server/src/crm/crm.service.spec.ts`:

```typescript
  it("lists active loss reasons ordered by sort_order", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      { rows: [{ id: "r1", name: "Дорого", kind: "lost", sort_order: 1, color: null }] },
    ]);
    const result = await service.listLossReasons(actor);
    expect(result.items[0]).toEqual({ id: "r1", name: "Дорого", kind: "lost", sortOrder: 1, color: null });
    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("app.lead_loss_reasons");
    expect(query.mock.calls[0][0]).toContain("is_active");
  });

  it("lists branch disciplines ordered for a branch", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      { rows: [{ id: "bd1", discipline_id: "d1", name: "Вокал", sort_order: 0 }] },
    ]);
    const result = await service.listBranchDisciplines(actor, "branch-1");
    expect(result.items[0]).toEqual({ id: "bd1", disciplineId: "d1", name: "Вокал", sortOrder: 0 });
    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("app.branch_disciplines");
    expect(query.mock.calls[0][1]).toEqual(["branch-1"]);
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `cd server && npx jest src/crm/crm.service.spec.ts -t "loss reasons"`
Expected: FAIL — `service.listLossReasons is not a function`.

- [ ] **Step 3: Implement the read methods**

Add to `CrmService` in `server/src/crm/crm.service.ts`:

```typescript
  async listLossReasons(actor: ActorContext) {
    this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<{
      id: string;
      name: string;
      kind: string;
      sort_order: number;
      color: string | null;
    }>(
      `select id, name, kind, sort_order, color
         from app.lead_loss_reasons
        where is_active and deleted_at is null
        order by sort_order asc, name asc`,
    );
    return {
      items: result.rows.map((row) => ({
        id: row.id,
        name: row.name,
        kind: row.kind,
        sortOrder: row.sort_order,
        color: row.color,
      })),
    };
  }

  async listLeadSources(actor: ActorContext) {
    this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<{
      id: string;
      canonical_name: string;
      display_name: string;
    }>(
      `select id, canonical_name, display_name
         from app.lead_sources
        where is_active and deleted_at is null
        order by display_name asc`,
    );
    return {
      items: result.rows.map((row) => ({
        id: row.id,
        canonicalName: row.canonical_name,
        displayName: row.display_name,
      })),
    };
  }

  async listDisciplines(actor: ActorContext) {
    this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<{ id: string; name: string }>(
      `select id, name
         from app.disciplines
        where is_active and deleted_at is null
        order by name asc`,
    );
    return { items: result.rows.map((row) => ({ id: row.id, name: row.name })) };
  }

  async listBranchDisciplines(actor: ActorContext, branchId: string) {
    this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<{
      id: string;
      discipline_id: string;
      name: string;
      sort_order: number;
    }>(
      `select bd.id, bd.discipline_id, d.name, bd.sort_order
         from app.branch_disciplines bd
         join app.disciplines d on d.id = bd.discipline_id and d.deleted_at is null
        where bd.branch_id = $1 and bd.deleted_at is null
        order by bd.sort_order asc, d.name asc`,
      [branchId],
    );
    return {
      items: result.rows.map((row) => ({
        id: row.id,
        disciplineId: row.discipline_id,
        name: row.name,
        sortOrder: row.sort_order,
      })),
    };
  }
```

- [ ] **Step 4: Add the controller routes**

Add to `server/src/crm/crm.controller.ts` (mirror the existing `@Get("lead-statuses")` pattern with `@CurrentActor()` / `@Param`):

```typescript
  @Get("loss-reasons")
  listLossReasons(@CurrentActor() actor: ActorContext) {
    return this.crm.listLossReasons(actor);
  }

  @Get("lead-sources")
  listLeadSources(@CurrentActor() actor: ActorContext) {
    return this.crm.listLeadSources(actor);
  }

  @Get("disciplines")
  listDisciplines(@CurrentActor() actor: ActorContext) {
    return this.crm.listDisciplines(actor);
  }

  @Get("branches/:branchId/disciplines")
  listBranchDisciplines(
    @CurrentActor() actor: ActorContext,
    @Param("branchId") branchId: string,
  ) {
    return this.crm.listBranchDisciplines(actor, branchId);
  }
```

(If `@Param` is not already imported at the top of the controller, add it — the `lead-statuses/:id` delete route already uses it.)

- [ ] **Step 5: Run tests + typecheck**

Run: `cd server && npm run typecheck && npx jest src/crm/crm.service.spec.ts`
Expected: typecheck 0; the two new tests PASS; existing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add server/src/crm/crm.service.ts server/src/crm/crm.controller.ts server/src/crm/crm.service.spec.ts
git commit -m "feat(crm): read endpoints for dictionaries (loss reasons, sources, disciplines) (KVA-189)"
```

---

## Task 3: Config (write) endpoints

**Files:**
- Create: `server/src/crm/dto/create-discipline.dto.ts`, `create-loss-reason.dto.ts`, `upsert-branch-discipline.dto.ts`, `reorder-branch-disciplines.dto.ts`
- Modify: `server/src/crm/crm.service.ts` (add four write methods)
- Modify: `server/src/crm/crm.controller.ts` (add POST/PATCH routes)
- Modify: `server/src/crm/crm.service.spec.ts` (add tests)

**Interfaces:**
- Produces:
  - `createDiscipline(actor, dto: { name }): Promise<{ id; name }>`
  - `createLossReason(actor, dto: { name; kind?; sortOrder? }): Promise<{ id; name; kind; sortOrder }>`
  - `assignBranchDiscipline(actor, branchId, dto: { disciplineId; sortOrder? }): Promise<{ id; disciplineId; sortOrder }>`
  - `reorderBranchDisciplines(actor, branchId, dto: { disciplineIds: string[] }): Promise<{ updated: number }>`
  - Routes `POST /crm/disciplines`, `POST /crm/loss-reasons`, `POST /crm/branches/:branchId/disciplines`, `PATCH /crm/branches/:branchId/disciplines/order`.

- [ ] **Step 1: Write the DTOs**

```typescript
// server/src/crm/dto/create-discipline.dto.ts
import { IsString, MaxLength } from "class-validator";

export class CreateDisciplineDto {
  @IsString()
  @MaxLength(120)
  name!: string;
}
```

```typescript
// server/src/crm/dto/create-loss-reason.dto.ts
import { IsIn, IsInt, IsOptional, IsString, MaxLength, Min } from "class-validator";

export class CreateLossReasonDto {
  @IsString()
  @MaxLength(120)
  name!: string;

  @IsOptional()
  @IsIn(["lost", "paused"])
  kind?: "lost" | "paused";

  @IsOptional()
  @IsInt()
  @Min(0)
  sortOrder?: number;
}
```

```typescript
// server/src/crm/dto/upsert-branch-discipline.dto.ts
import { IsInt, IsOptional, IsUUID, Min } from "class-validator";

export class UpsertBranchDisciplineDto {
  @IsUUID()
  disciplineId!: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  sortOrder?: number;
}
```

```typescript
// server/src/crm/dto/reorder-branch-disciplines.dto.ts
import { ArrayNotEmpty, IsArray, IsUUID } from "class-validator";

export class ReorderBranchDisciplinesDto {
  @IsArray()
  @ArrayNotEmpty()
  @IsUUID("all", { each: true })
  disciplineIds!: string[];
}
```

- [ ] **Step 2: Write the failing tests**

Add to `server/src/crm/crm.service.spec.ts`:

```typescript
  it("creates a discipline", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      { rows: [{ id: "d9", name: "Скрипка" }] },
    ]);
    const result = await service.createDiscipline(actor, { name: "Скрипка" });
    expect(result).toEqual({ id: "d9", name: "Скрипка" });
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("insert into app.disciplines");
    expect(query.mock.calls[0][1]).toEqual(["Скрипка"]);
  });

  it("reorders branch disciplines by array position", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      { rows: [{ id: "bd1" }, { id: "bd2" }] },
    ]);
    const result = await service.reorderBranchDisciplines(actor, "branch-1", {
      disciplineIds: ["d2", "d1"],
    });
    expect(result).toEqual({ updated: 2 });
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("with ordinality");
    expect(query.mock.calls[0][1]).toEqual(["branch-1", ["d2", "d1"]]);
  });
```

- [ ] **Step 3: Run to verify failure**

Run: `cd server && npx jest src/crm/crm.service.spec.ts -t "creates a discipline"`
Expected: FAIL — `service.createDiscipline is not a function`.

- [ ] **Step 4: Implement the write methods**

Add to `CrmService` in `server/src/crm/crm.service.ts`:

```typescript
  async createDiscipline(actor: ActorContext, dto: { name: string }) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<{ id: string; name: string }>(
      `insert into app.disciplines (name) values ($1) returning id, name`,
      [dto.name],
    );
    return { id: result.rows[0].id, name: result.rows[0].name };
  }

  async createLossReason(
    actor: ActorContext,
    dto: { name: string; kind?: "lost" | "paused"; sortOrder?: number },
  ) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<{
      id: string;
      name: string;
      kind: string;
      sort_order: number;
    }>(
      `insert into app.lead_loss_reasons (name, kind, sort_order)
       values ($1, $2, $3)
       returning id, name, kind, sort_order`,
      [dto.name, dto.kind ?? "lost", dto.sortOrder ?? 0],
    );
    const row = result.rows[0];
    return { id: row.id, name: row.name, kind: row.kind, sortOrder: row.sort_order };
  }

  async assignBranchDiscipline(
    actor: ActorContext,
    branchId: string,
    dto: { disciplineId: string; sortOrder?: number },
  ) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<{
      id: string;
      discipline_id: string;
      sort_order: number;
    }>(
      `insert into app.branch_disciplines (branch_id, discipline_id, sort_order)
       values (
         $1, $2,
         coalesce($3, (select coalesce(max(sort_order) + 1, 0)
                         from app.branch_disciplines
                        where branch_id = $1 and deleted_at is null))
       )
       on conflict (branch_id, discipline_id)
       do update set sort_order = excluded.sort_order, deleted_at = null
       returning id, discipline_id, sort_order`,
      [branchId, dto.disciplineId, dto.sortOrder ?? null],
    );
    const row = result.rows[0];
    return { id: row.id, disciplineId: row.discipline_id, sortOrder: row.sort_order };
  }

  async reorderBranchDisciplines(
    actor: ActorContext,
    branchId: string,
    dto: { disciplineIds: string[] },
  ) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query(
      `update app.branch_disciplines bd
          set sort_order = t.ord - 1
         from unnest($2::uuid[]) with ordinality as t(discipline_id, ord)
        where bd.branch_id = $1
          and bd.discipline_id = t.discipline_id
          and bd.deleted_at is null`,
      [branchId, dto.disciplineIds],
    );
    return { updated: result.rowCount ?? 0 };
  }
```

> Note: the reorder test mocks the query result with two `rows`; `result.rowCount` is undefined on that mock, so the test asserts on the SQL/params, not the count. In Postgres `rowCount` reflects the real updated count.

- [ ] **Step 5: Add the controller routes**

Add to `server/src/crm/crm.controller.ts` (import the four DTOs at the top alongside `UpsertLeadStatusDto`):

```typescript
  @Post("disciplines")
  createDiscipline(
    @CurrentActor() actor: ActorContext,
    @Body() dto: CreateDisciplineDto,
  ) {
    return this.crm.createDiscipline(actor, dto);
  }

  @Post("loss-reasons")
  createLossReason(
    @CurrentActor() actor: ActorContext,
    @Body() dto: CreateLossReasonDto,
  ) {
    return this.crm.createLossReason(actor, dto);
  }

  @Post("branches/:branchId/disciplines")
  assignBranchDiscipline(
    @CurrentActor() actor: ActorContext,
    @Param("branchId") branchId: string,
    @Body() dto: UpsertBranchDisciplineDto,
  ) {
    return this.crm.assignBranchDiscipline(actor, branchId, dto);
  }

  @Patch("branches/:branchId/disciplines/order")
  reorderBranchDisciplines(
    @CurrentActor() actor: ActorContext,
    @Param("branchId") branchId: string,
    @Body() dto: ReorderBranchDisciplinesDto,
  ) {
    return this.crm.reorderBranchDisciplines(actor, branchId, dto);
  }
```

(If `@Patch` / `@Body` are not already imported from `@nestjs/common` in this controller, add them — `@Post`/`@Body` are already used by `createLeadStatus`.)

- [ ] **Step 6: Run tests + typecheck**

Run: `cd server && npm run typecheck && npm test`
Expected: typecheck 0; the new tests PASS; full suite green.

- [ ] **Step 7: Commit**

```bash
git add server/src/crm/dto/create-discipline.dto.ts server/src/crm/dto/create-loss-reason.dto.ts server/src/crm/dto/upsert-branch-discipline.dto.ts server/src/crm/dto/reorder-branch-disciplines.dto.ts server/src/crm/crm.service.ts server/src/crm/crm.controller.ts server/src/crm/crm.service.spec.ts
git commit -m "feat(crm): config endpoints for disciplines, branch order, loss reasons (KVA-189)"
```

---

## Self-Review

- **Spec coverage (§4A6):** `lead_loss_reasons` + seed + `is_terminal`/`requires_reason` ✅ (Task 1); `lead_sources` + seed ✅ (Task 1); `disciplines` / `branch_disciplines` / `student_disciplines` with `is_primary` one-per-student ✅ (Task 1); read endpoints ✅ (Task 2); editable-from-UI write endpoints ✅ (Task 3). The student `is_primary` *writer* is intentionally deferred to Epic B (reimport) and Epic C (conversion) — A6 ships the table + read only.
- **Placeholder scan:** none — full SQL/TS/tests with exact commands.
- **Type consistency:** method names (`listLossReasons`, `listLeadSources`, `listDisciplines`, `listBranchDisciplines`, `createDiscipline`, `createLossReason`, `assignBranchDiscipline`, `reorderBranchDisciplines`) identical across service, controller, and tests; DTO field names (`disciplineId`, `disciplineIds`, `sortOrder`, `kind`) consistent.
- **Idempotency:** seeds guarded by `where not exists`; all DDL `if not exists`; `assignBranchDiscipline` upserts via `on conflict (branch_id, discipline_id)`.

## Dependency note

A6 unblocks **B3** (reimport writes `disciplines` + `student_disciplines.is_primary`), **B4**/student branch, **C4** (Ученики board reads `branch_disciplines`), **C8** (config UI calls these write endpoints), and **A5** (`lead_status_history.reason_id` → `lead_loss_reasons`). Migration `0026` is applied to prod later, batched with the other Epic A migrations (per the owner's decision).
