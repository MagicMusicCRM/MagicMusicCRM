# Epic A · Task A3 — Families (backend foundation) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Model households as first-class data — `families`, `family_members`, and a normalized `contacts` table — so each person stays a separate card while a shared phone links a family, and the client card can navigate parent↔child in one click.

**Architecture:** Migration `0029_families` adds the three tables (`family_members` uses the same `(entity_type, entity_id)` polymorphic pattern as `user_crm_links`). Backend endpoints create/link/read families; the key read `getFamilyForEntity` returns a person's family + all members with display names resolved, which is exactly what the card's «Семья» section and 1-click navigation consume. **The Flutter «Семья» UI is intentionally built in Epic C7** (the unified client card), not here — A3 ships the data + endpoints that unblock it.

**Tech Stack:** NestJS + TypeScript, PostgreSQL (numbered migrations), class-validator DTOs, Jest.

**Linear:** KVA-186 (A3) under epic KVA-178 (A). Spec §2(9) / §4A3. Depends on `branch_id` (0027) and the canonical phone (A1) already in the chain.

## Global Constraints

- Migration id is **`0029_families`**.
- `app.families(id, name, branch_id fk branches null, primary_payer_member_id uuid null, created_at, updated_at, deleted_at)`. `primary_payer_member_id` gets a guarded FK → `family_members(id) on delete set null` added AFTER `family_members` exists (idempotent via a `pg_constraint` existence check).
- `app.family_members(id, family_id fk families on delete cascade, entity_type text, entity_id uuid, role text default 'child', is_primary_contact bool default false, created_at, deleted_at, unique(family_id, entity_type, entity_id))`. `entity_type in ('student','lead','profile')`; `role in ('parent','child','partner','sibling','guardian','payer')`. Partial indexes on `(family_id)` and `(entity_type, entity_id)` where `deleted_at is null`.
- `app.contacts(id, entity_type text, entity_id uuid, phone_normalized text, name text, role text, created_at)` — multiple contact persons per entity (fed by Epic B from HolliHop `Agents[]`). `entity_type` same check. Indexes on `(entity_type, entity_id)` and `(phone_normalized) where phone_normalized is not null`.
- The phone is a FAMILY connector, NOT a person key — A3 only models relationships; it must NOT merge records (that is A7).
- Conventions: schema `app.`; `gen_random_uuid()`; idempotent DDL; every new table ends with a guarded `grant ... to magiccrm_app`. class-validator DTOs. Write endpoints gate `assertCanWriteCrm`; reads gate `assertCanReadOperationalData`.
- **Out of scope (noted, not built here):** the Flutter «Семья» card section + parent↔child navigation → Epic C7. Family *suggestions* from shared phone / `duplicate_candidates` → follow-up (the data is in place; the suggestion query lands with A7/C7).
- Run from `server/`: migrations `npm run db:migrate`/`db:rollback`; tests `npm test`; types `npm run typecheck`.
- **Prod safety:** validate the migration ONLY against an ephemeral Docker Postgres (chain 0001..0029), NEVER prod, NEVER `server/.env`/`.migration.env`.

---

## File Structure

- **Create** `server/db/migrations/0029_families.up.sql` / `.down.sql`.
- **Create** `server/src/crm/dto/create-family.dto.ts`, `add-family-member.dto.ts`.
- **Modify** `server/src/crm/crm.service.ts` — `createFamily`, `addFamilyMember`, `getFamilyForEntity`, `removeFamilyMember`, `setPrimaryPayer`.
- **Modify** `server/src/crm/crm.controller.ts` — routes.
- **Modify** `server/src/crm/crm.service.spec.ts` — tests.

---

## Task 1: Migration 0029 — families, family_members, contacts

**Files:**
- Create: `server/db/migrations/0029_families.up.sql`
- Create: `server/db/migrations/0029_families.down.sql`

**Interfaces (DB):** tables `app.families`, `app.family_members`, `app.contacts`.

- [ ] **Step 1: Write the up migration**

```sql
-- server/db/migrations/0029_families.up.sql
-- Households: families + polymorphic family_members + normalized contacts.

create table if not exists app.families (
  id uuid primary key default gen_random_uuid(),
  name text,
  branch_id uuid references app.branches(id),
  primary_payer_member_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists app.family_members (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references app.families(id) on delete cascade,
  entity_type text not null,
  entity_id uuid not null,
  role text not null default 'child',
  is_primary_contact boolean not null default false,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint family_members_entity_check check (entity_type in ('student', 'lead', 'profile')),
  constraint family_members_role_check check (role in ('parent', 'child', 'partner', 'sibling', 'guardian', 'payer')),
  constraint family_members_unique unique (family_id, entity_type, entity_id)
);
create index if not exists family_members_family_idx
  on app.family_members (family_id) where deleted_at is null;
create index if not exists family_members_entity_idx
  on app.family_members (entity_type, entity_id) where deleted_at is null;

-- Guarded FK for the payer pointer (added after family_members exists; idempotent).
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'families_payer_member_fk') then
    alter table app.families
      add constraint families_payer_member_fk
      foreign key (primary_payer_member_id) references app.family_members(id) on delete set null;
  end if;
end $$;

create table if not exists app.contacts (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null,
  entity_id uuid not null,
  phone_normalized text,
  name text,
  role text,
  created_at timestamptz not null default now(),
  constraint contacts_entity_check check (entity_type in ('student', 'lead', 'profile'))
);
create index if not exists contacts_entity_idx on app.contacts (entity_type, entity_id);
create index if not exists contacts_phone_idx on app.contacts (phone_normalized) where phone_normalized is not null;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert, update, delete on app.families to magiccrm_app;
    grant select, insert, update, delete on app.family_members to magiccrm_app;
    grant select, insert, update, delete on app.contacts to magiccrm_app;
  end if;
end $$;
```

- [ ] **Step 2: Write the down migration**

```sql
-- server/db/migrations/0029_families.down.sql
drop table if exists app.contacts;
alter table app.families drop constraint if exists families_payer_member_fk;
drop table if exists app.family_members;
drop table if exists app.families;
```

- [ ] **Step 3: Validate on an ephemeral Docker Postgres (NOT prod)**

```bash
docker run --rm -d --name mmcrm-a3-pg -e POSTGRES_PASSWORD=test -e POSTGRES_DB=mmcrm_test -p 55436:5432 postgres:16
# wait: docker exec mmcrm-a3-pg pg_isready -U postgres  (retry)
docker exec mmcrm-a3-pg psql -U postgres -d mmcrm_test -c "create role magiccrm_app" || true
cd server && MIGRATION_DATABASE_URL='postgres://postgres:test@localhost:55436/mmcrm_test' DATABASE_URL='postgres://postgres:test@localhost:55436/mmcrm_test' npm run db:migrate
```
Expected last line includes `0029_families`. Host MUST be `localhost:55436`; abort if remote.

- [ ] **Step 4: Verify schema + the payer FK + reversibility**

```bash
docker exec mmcrm-a3-pg psql -U postgres -d mmcrm_test -c "\d app.family_members"
docker exec mmcrm-a3-pg psql -U postgres -d mmcrm_test -c "select conname from pg_constraint where conname='families_payer_member_fk';"
cd server && MIGRATION_DATABASE_URL='postgres://postgres:test@localhost:55436/mmcrm_test' DATABASE_URL='postgres://postgres:test@localhost:55436/mmcrm_test' npm run db:migrate   # Expected: none (idempotent — the DO-guarded FK does not re-add)
cd server && MIGRATION_DATABASE_URL='postgres://postgres:test@localhost:55436/mmcrm_test' DATABASE_URL='postgres://postgres:test@localhost:55436/mmcrm_test' npm run db:rollback  # Expected: Reverted 0029_families
docker exec mmcrm-a3-pg psql -U postgres -d mmcrm_test -c "select to_regclass('app.families');"  # Expected: NULL
cd server && MIGRATION_DATABASE_URL='postgres://postgres:test@localhost:55436/mmcrm_test' DATABASE_URL='postgres://postgres:test@localhost:55436/mmcrm_test' npm run db:migrate   # Re-apply
docker stop mmcrm-a3-pg
```
Expected: `family_members` shows the entity/role checks + unique; `families_payer_member_fk` present; idempotent re-run is `none`; rollback drops all three; re-apply clean.

- [ ] **Step 5: Commit**

```bash
git add server/db/migrations/0029_families.up.sql server/db/migrations/0029_families.down.sql
git commit -m "feat(db): families + family_members + contacts (KVA-186)"
```

---

## Task 2: Family endpoints

**Files:**
- Create: `server/src/crm/dto/create-family.dto.ts`, `server/src/crm/dto/add-family-member.dto.ts`
- Modify: `server/src/crm/crm.service.ts`, `server/src/crm/crm.controller.ts`, `server/src/crm/crm.service.spec.ts`

**Interfaces:**
- Produces:
  - `createFamily(actor, dto: { name?; branchId? }): Promise<{ id; name; branchId }>`
  - `addFamilyMember(actor, familyId, dto: { entityType; entityId; role; isPrimaryContact? }): Promise<{ id; familyId; entityType; entityId; role }>`
  - `getFamilyForEntity(actor, entityType, entityId): Promise<{ family: {...} | null; members: Array<{ id; entityType; entityId; role; isPrimaryContact; name: string | null }> }>`
  - `removeFamilyMember(actor, memberId): Promise<{ success: true }>`
  - `setPrimaryPayer(actor, familyId, memberId): Promise<{ success: true }>`
  - Routes: `POST /crm/families`, `POST /crm/families/:familyId/members`, `GET /crm/families/by-entity/:entityType/:entityId`, `DELETE /crm/family-members/:memberId`, `POST /crm/families/:familyId/primary-payer/:memberId`.

- [ ] **Step 1: Write the DTOs**

```typescript
// server/src/crm/dto/create-family.dto.ts
import { IsOptional, IsString, IsUUID, MaxLength } from "class-validator";

export class CreateFamilyDto {
  @IsOptional()
  @IsString()
  @MaxLength(200)
  name?: string;

  @IsOptional()
  @IsUUID()
  branchId?: string;
}
```

```typescript
// server/src/crm/dto/add-family-member.dto.ts
import { IsBoolean, IsIn, IsOptional, IsUUID } from "class-validator";

export class AddFamilyMemberDto {
  @IsIn(["student", "lead", "profile"])
  entityType!: "student" | "lead" | "profile";

  @IsUUID()
  entityId!: string;

  @IsIn(["parent", "child", "partner", "sibling", "guardian", "payer"])
  role!: "parent" | "child" | "partner" | "sibling" | "guardian" | "payer";

  @IsOptional()
  @IsBoolean()
  isPrimaryContact?: boolean;
}
```

- [ ] **Step 2: Write the failing tests**

Add to `server/src/crm/crm.service.spec.ts`:

```typescript
  it("creates a family", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      { rows: [{ id: "fam-1", name: "Ивановы", branch_id: "b1" }] },
    ]);
    const result = await service.createFamily(actor, { name: "Ивановы", branchId: "b1" });
    expect(result).toEqual({ id: "fam-1", name: "Ивановы", branchId: "b1" });
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("insert into app.families");
    expect(query.mock.calls[0][1]).toEqual(["Ивановы", "b1"]);
  });

  it("returns a family with members and resolved names for an entity", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      { rows: [{ family_id: "fam-1", name: "Ивановы", branch_id: "b1", primary_payer_member_id: null }] }, // family lookup
      {
        rows: [
          { id: "m1", entity_type: "student", entity_id: "s1", role: "child", is_primary_contact: false, member_name: "Петя Иванов" },
          { id: "m2", entity_type: "profile", entity_id: "p1", role: "parent", is_primary_contact: true, member_name: "Иван Иванов" },
        ],
      }, // members
    ]);
    const result = await service.getFamilyForEntity(actor, "student", "s1");
    expect(result.family).toEqual({ id: "fam-1", name: "Ивановы", branchId: "b1", primaryPayerMemberId: null });
    expect(result.members).toEqual([
      { id: "m1", entityType: "student", entityId: "s1", role: "child", isPrimaryContact: false, name: "Петя Иванов" },
      { id: "m2", entityType: "profile", entityId: "p1", role: "parent", isPrimaryContact: true, name: "Иван Иванов" },
    ]);
    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual(["student", "s1"]);
  });
```

- [ ] **Step 3: Run to verify failure**

Run: `cd server && npx jest src/crm/crm.service.spec.ts -t "creates a family"`
Expected: FAIL — `service.createFamily is not a function`.

- [ ] **Step 4: Implement the service methods**

Add to `CrmService` in `server/src/crm/crm.service.ts`:

```typescript
  async createFamily(actor: ActorContext, dto: { name?: string; branchId?: string }) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<{ id: string; name: string | null; branch_id: string | null }>(
      `insert into app.families (name, branch_id) values ($1, $2) returning id, name, branch_id`,
      [dto.name ?? null, dto.branchId ?? null],
    );
    const row = result.rows[0];
    return { id: row.id, name: row.name, branchId: row.branch_id };
  }

  async addFamilyMember(
    actor: ActorContext,
    familyId: string,
    dto: { entityType: string; entityId: string; role: string; isPrimaryContact?: boolean },
  ) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<{
      id: string;
      family_id: string;
      entity_type: string;
      entity_id: string;
      role: string;
    }>(
      `insert into app.family_members (family_id, entity_type, entity_id, role, is_primary_contact)
       values ($1, $2, $3, $4, $5)
       on conflict (family_id, entity_type, entity_id)
       do update set role = excluded.role, is_primary_contact = excluded.is_primary_contact, deleted_at = null
       returning id, family_id, entity_type, entity_id, role`,
      [familyId, dto.entityType, dto.entityId, dto.role, dto.isPrimaryContact ?? false],
    );
    const row = result.rows[0];
    return { id: row.id, familyId: row.family_id, entityType: row.entity_type, entityId: row.entity_id, role: row.role };
  }

  async getFamilyForEntity(actor: ActorContext, entityType: string, entityId: string) {
    this.policy.assertCanReadOperationalData(actor);
    const famRes = await this.database.query<{
      family_id: string;
      name: string | null;
      branch_id: string | null;
      primary_payer_member_id: string | null;
    }>(
      `select f.id as family_id, f.name, f.branch_id, f.primary_payer_member_id
         from app.family_members m
         join app.families f on f.id = m.family_id and f.deleted_at is null
        where m.entity_type = $1 and m.entity_id = $2 and m.deleted_at is null
        limit 1`,
      [entityType, entityId],
    );
    const fam = famRes.rows[0];
    if (!fam) return { family: null, members: [] };
    const memRes = await this.database.query<{
      id: string;
      entity_type: string;
      entity_id: string;
      role: string;
      is_primary_contact: boolean;
      member_name: string | null;
    }>(
      `select m.id, m.entity_type, m.entity_id, m.role, m.is_primary_contact,
              coalesce(
                nullif(btrim(concat_ws(' ', l.first_name, l.last_name)), ''),
                nullif(btrim(concat_ws(' ', sp.first_name, sp.last_name)), ''),
                nullif(btrim(concat_ws(' ', pr.first_name, pr.last_name)), '')
              ) as member_name
         from app.family_members m
         left join app.leads l    on m.entity_type = 'lead'    and l.id = m.entity_id
         left join app.students st on m.entity_type = 'student' and st.id = m.entity_id
         left join app.profiles sp on sp.id = st.profile_id
         left join app.profiles pr on m.entity_type = 'profile' and pr.id = m.entity_id
        where m.family_id = $1 and m.deleted_at is null
        order by m.role, member_name`,
      [fam.family_id],
    );
    return {
      family: {
        id: fam.family_id,
        name: fam.name,
        branchId: fam.branch_id,
        primaryPayerMemberId: fam.primary_payer_member_id,
      },
      members: memRes.rows.map((row) => ({
        id: row.id,
        entityType: row.entity_type,
        entityId: row.entity_id,
        role: row.role,
        isPrimaryContact: row.is_primary_contact,
        name: row.member_name,
      })),
    };
  }

  async removeFamilyMember(actor: ActorContext, memberId: string) {
    this.policy.assertCanWriteCrm(actor);
    await this.database.query(
      `update app.family_members set deleted_at = now() where id = $1 and deleted_at is null`,
      [memberId],
    );
    return { success: true as const };
  }

  async setPrimaryPayer(actor: ActorContext, familyId: string, memberId: string) {
    this.policy.assertCanWriteCrm(actor);
    await this.database.query(
      `update app.families set primary_payer_member_id = $2, updated_at = now()
        where id = $1 and deleted_at is null`,
      [familyId, memberId],
    );
    return { success: true as const };
  }
```

- [ ] **Step 5: Add the controller routes**

Add to `server/src/crm/crm.controller.ts` (import the two DTOs; use `@Param(..., ParseUUIDPipe)` for uuid params, plain `@Param` for `entityType`):

```typescript
  @Post("families")
  createFamily(@CurrentActor() actor: ActorContext, @Body() dto: CreateFamilyDto) {
    return this.crm.createFamily(actor, dto);
  }

  @Post("families/:familyId/members")
  addFamilyMember(
    @CurrentActor() actor: ActorContext,
    @Param("familyId", ParseUUIDPipe) familyId: string,
    @Body() dto: AddFamilyMemberDto,
  ) {
    return this.crm.addFamilyMember(actor, familyId, dto);
  }

  @Get("families/by-entity/:entityType/:entityId")
  getFamilyForEntity(
    @CurrentActor() actor: ActorContext,
    @Param("entityType") entityType: string,
    @Param("entityId", ParseUUIDPipe) entityId: string,
  ) {
    return this.crm.getFamilyForEntity(actor, entityType, entityId);
  }

  @Delete("family-members/:memberId")
  removeFamilyMember(
    @CurrentActor() actor: ActorContext,
    @Param("memberId", ParseUUIDPipe) memberId: string,
  ) {
    return this.crm.removeFamilyMember(actor, memberId);
  }

  @Post("families/:familyId/primary-payer/:memberId")
  setPrimaryPayer(
    @CurrentActor() actor: ActorContext,
    @Param("familyId", ParseUUIDPipe) familyId: string,
    @Param("memberId", ParseUUIDPipe) memberId: string,
  ) {
    return this.crm.setPrimaryPayer(actor, familyId, memberId);
  }
```

- [ ] **Step 6: Run tests + typecheck**

Run: `cd server && npm run typecheck && npm test`
Expected: typecheck 0; the two new tests pass; full suite green.

- [ ] **Step 7: Commit**

```bash
git add server/src/crm/dto/create-family.dto.ts server/src/crm/dto/add-family-member.dto.ts server/src/crm/crm.service.ts server/src/crm/crm.controller.ts server/src/crm/crm.service.spec.ts
git commit -m "feat(crm): family endpoints (create, link member, get-by-entity, payer) (KVA-186)"
```

---

## Self-Review

- **Spec coverage (§4A3):** `families`/`family_members`/`contacts` tables ✅ (Task 1); `(entity_type, entity_id)` polymorphic members ✅; one-payer pointer ✅; create/link/read/remove/set-payer endpoints ✅ (Task 2); `getFamilyForEntity` returns members with resolved display names — the data backing the 1-click parent↔child nav ✅. The Flutter «Семья» section + navigation are explicitly deferred to Epic C7; family *suggestions* (shared-phone seeding) deferred to A7/C7.
- **Placeholder scan:** none — full SQL/TS/tests with exact commands.
- **Idempotency:** the payer FK is added via a `pg_constraint`-guarded DO block (re-run safe); `addFamilyMember` upserts via `on conflict ... do update set deleted_at = null` (re-link resurrects a soft-deleted member — same pattern as A6 branch_disciplines, requires the non-partial `family_members_unique`).
- **Type consistency:** method + DTO names identical across service, controller, and tests; the members query's `member_name` alias maps to `name`.

## Dependency note

A3 unblocks the Epic C7 «Семья» card section + 1-click parent↔child navigation (consumes `getFamilyForEntity`), the payer→finance link, and is fed by Epic B (HolliHop `Agents[]` → `app.contacts`, shared-phone → family suggestions). Migration `0029` is applied to prod later, batched with the other Epic A migrations.
