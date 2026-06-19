# Epic A · Task A7 — Lead dedup (merge + undo, backend) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an admin merge a true-duplicate lead (matched by normalized phone + name) into a canonical one — safely (soft-delete the loser, never a hard delete, so no `ON DELETE CASCADE` ever fires and no data is lost), reversibly (an undo that restores the exact moved rows), and from a review queue.

**Architecture:** A `merge_log` table records every merge with the exact row ids moved per reference, enabling a precise undo. `mergeLeads` runs inside ONE `database.transaction`: it re-points the loser's references (real-FK `lead_id` columns + polymorphic `entity_type='lead'` rows) to the winner, marks duplicate candidates merged, then soft-deletes the loser. Because the loser is only soft-deleted (`deleted_at`), the `CASCADE` FKs (lead_comments, lead_status_history) never fire — we re-point those rows explicitly so they follow the winner. **Student merge is out of scope** (near-zero real duplicates + financial tables) — `merge_log.entity_type` already allows `'student'` for a future task. **The review-queue UI is Flutter (deferred), like A3 → C.**

**Tech Stack:** NestJS + TypeScript, PostgreSQL, `database.transaction`, class-validator DTOs, Jest.

**Linear:** KVA-190 (A7) under epic KVA-178 (A). Spec §2(4)/§4A7. Depends on `phone_normalized` (A1) and `duplicate_candidates` (0019).

## Global Constraints

- Migration id is **`0030_merge_log`**.
- `app.merge_log(id, entity_type text check in ('lead','student'), loser_id uuid, winner_id uuid, repointed jsonb default '{}', merged_by uuid fk users, merged_at default now(), undone_at, undone_by uuid fk users)` + index `(entity_type, loser_id)` + guarded grant.
- NEVER hard-delete an entity. Merge = re-point references + soft-delete the loser (`deleted_at = now()`). This is what prevents any `CASCADE` data loss.
- `mergeLeads` and `undoMerge` run entirely inside `this.database.transaction(async (client) => { ... })` (pattern: `crm.service.ts:4348`, `saveContactFromChat`). Use `client.query` for EVERY statement inside.
- `repointed` is a fixed-shape JSON map `{ "<table>.<column>": [movedRowIds...] }` capturing exactly which rows moved, so `undoMerge` reverses precisely (no broad "move everything back" that would wrongly move the winner's own rows). `undoMerge` switches on a KNOWN, hard-coded key set — never builds table names dynamically from data.
- Winner is authoritative — A7 does NOT field-merge (filling winner blanks from loser). The loser's data stays accessible via its soft-deleted record + re-pointed children.
- Lead re-point set (real FK): `students.lead_id`, `lessons.lead_id`, `lead_status_history.lead_id`, `lead_comments.lead_id`. Polymorphic (`entity_type='lead'`): `tasks.entity_id`, `entity_comments.entity_id`. Plus `duplicate_candidates` → status `'merged'`. (Rare unique-constrained polymorphic links — `family_members`, `user_crm_links`, `contacts` with entity_type='lead' — are NOT auto-repointed for a lead; the loser's soft-delete hides them, the winner keeps its own. Documented limitation.)
- Conventions: schema `app.`; `gen_random_uuid()`; idempotent DDL; guarded grant. Write methods gate `assertCanWriteCrm`; the candidate read gates `assertCanReadOperationalData`. `ParseUUIDPipe` on uuid route params.
- Run from `server/`: migrations `npm run db:migrate`/`db:rollback`; tests `npm test`; types `npm run typecheck`.
- **Prod safety:** validate the migration ONLY on an ephemeral Docker Postgres (chain 0001..0030), NEVER prod, NEVER `server/.env`/`.migration.env`.

---

## File Structure

- **Create** `server/db/migrations/0030_merge_log.up.sql` / `.down.sql`.
- **Modify** `server/src/crm/crm.service.ts` — `listMergeCandidates`, `mergeLeads`, `undoMerge`.
- **Modify** `server/src/crm/crm.controller.ts` — routes.
- **Modify** `server/src/crm/crm.service.spec.ts` — tests (with a transaction-aware mock).

---

## Task 1: Migration 0030 — merge_log

**Files:**
- Create: `server/db/migrations/0030_merge_log.up.sql`
- Create: `server/db/migrations/0030_merge_log.down.sql`

**Interfaces (DB):** table `app.merge_log`.

- [ ] **Step 1: Write the up migration**

```sql
-- server/db/migrations/0030_merge_log.up.sql
-- Audit + undo log for record merges (dedup). Records exactly which rows moved.

create table if not exists app.merge_log (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null,
  loser_id uuid not null,
  winner_id uuid not null,
  repointed jsonb not null default '{}'::jsonb,
  merged_by uuid references app.users(id),
  merged_at timestamptz not null default now(),
  undone_at timestamptz,
  undone_by uuid references app.users(id),
  constraint merge_log_entity_check check (entity_type in ('lead', 'student'))
);
create index if not exists merge_log_entity_idx on app.merge_log (entity_type, loser_id);
create index if not exists merge_log_open_idx on app.merge_log (merged_at desc) where undone_at is null;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert, update, delete on app.merge_log to magiccrm_app;
  end if;
end $$;
```

- [ ] **Step 2: Write the down migration**

```sql
-- server/db/migrations/0030_merge_log.down.sql
drop table if exists app.merge_log;
```

- [ ] **Step 3: Validate on an ephemeral Docker Postgres (NOT prod)**

```bash
docker run --rm -d --name mmcrm-a7-pg -e POSTGRES_PASSWORD=test -e POSTGRES_DB=mmcrm_test -p 55439:5432 postgres:16
# wait: docker exec mmcrm-a7-pg pg_isready -U postgres  (retry)
docker exec mmcrm-a7-pg psql -U postgres -d mmcrm_test -c "create role magiccrm_app" || true
cd server && MIGRATION_DATABASE_URL='postgres://postgres:test@localhost:55439/mmcrm_test' DATABASE_URL='postgres://postgres:test@localhost:55439/mmcrm_test' npm run db:migrate
```
Expected last line includes `0030_merge_log`. Host MUST be `localhost:55439`; abort if remote.

- [ ] **Step 4: Verify + reversibility**

```bash
docker exec mmcrm-a7-pg psql -U postgres -d mmcrm_test -c "\d app.merge_log"
cd server && MIGRATION_DATABASE_URL='postgres://postgres:test@localhost:55439/mmcrm_test' DATABASE_URL='postgres://postgres:test@localhost:55439/mmcrm_test' npm run db:migrate    # Expected: none
cd server && MIGRATION_DATABASE_URL='postgres://postgres:test@localhost:55439/mmcrm_test' DATABASE_URL='postgres://postgres:test@localhost:55439/mmcrm_test' npm run db:rollback   # Reverted 0030_merge_log
docker exec mmcrm-a7-pg psql -U postgres -d mmcrm_test -c "select to_regclass('app.merge_log');"  # NULL
cd server && MIGRATION_DATABASE_URL='postgres://postgres:test@localhost:55439/mmcrm_test' DATABASE_URL='postgres://postgres:test@localhost:55439/mmcrm_test' npm run db:migrate    # Re-apply
docker stop mmcrm-a7-pg
```

- [ ] **Step 5: Commit**

```bash
git add server/db/migrations/0030_merge_log.up.sql server/db/migrations/0030_merge_log.down.sql
git commit -m "feat(db): merge_log for dedup undo/audit (KVA-190)"
```

---

## Task 2: Candidates + mergeLeads + undoMerge

**Files:**
- Modify: `server/src/crm/crm.service.ts`, `server/src/crm/crm.controller.ts`, `server/src/crm/crm.service.spec.ts`

**Interfaces:**
- Produces:
  - `listMergeCandidates(actor, limit?): Promise<{ items: Array<{ loserId; winnerId; phone; name }> }>`
  - `mergeLeads(actor, loserId, winnerId): Promise<{ mergeLogId; winnerId }>`
  - `undoMerge(actor, mergeLogId): Promise<{ success: true }>`
  - Routes: `GET /crm/merge-candidates`, `POST /crm/leads/:winnerId/merge/:loserId`, `POST /crm/merges/:mergeLogId/undo`.

- [ ] **Step 1: Write the failing tests**

Add to `server/src/crm/crm.service.spec.ts`. NOTE the transaction-aware service construction — the merge methods run inside `database.transaction`, so the mock must invoke the callback with the query mock:

```typescript
  const createMergeService = (results: { rows: Record<string, unknown>[] }[]) => {
    const query = jest.fn();
    for (const r of results) query.mockResolvedValueOnce(r);
    const transaction = jest.fn(
      async (work: (client: { query: jest.Mock }) => Promise<unknown>) => work({ query }),
    );
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const notifications = { sendEmail: jest.fn().mockResolvedValue({ queued: true }) };
    const policy = {
      assertCanReadOperationalData: jest.fn(),
      assertCanWriteCrm: jest.fn(),
      assertCanListStudents: jest.fn(),
      assertCanReadStudent: jest.fn(),
    };
    const hollihop = {
      listDisciplines: jest.fn().mockResolvedValue({ configured: false, items: [] }),
      listLevels: jest.fn().mockResolvedValue({ configured: false, items: [] }),
      listCategories: jest.fn().mockResolvedValue({ configured: false, items: [] }),
      listLeadStatuses: jest.fn().mockResolvedValue({ configured: false, items: [] }),
    };
    const service = new CrmService(
      { query, transaction } as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      hollihop as unknown as HolliHopMetadataService,
      notifications as unknown as NotificationsService,
    );
    return { service, query, transaction, policy };
  };

  it("lists lead merge candidates by phone + name", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      { rows: [{ loser_id: "l-lo", winner_id: "l-wi", phone: "+79091234567", name: "Иван Иванов" }] },
    ]);
    const result = await service.listMergeCandidates(actor);
    expect(result.items[0]).toEqual({ loserId: "l-lo", winnerId: "l-wi", phone: "+79091234567", name: "Иван Иванов" });
    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("phone_normalized");
  });

  it("mergeLeads re-points references, soft-deletes the loser, and logs", async () => {
    const { service, query, transaction, policy } = createMergeService([
      { rows: [{ id: "l-lo" }, { id: "l-wi" }] }, // validate both exist
      { rows: [{ id: "s1" }] },                    // students.lead_id
      { rows: [{ id: "le1" }] },                   // lessons.lead_id
      { rows: [{ id: "h1" }] },                    // lead_status_history.lead_id
      { rows: [] },                                // lead_comments.lead_id
      { rows: [{ id: "t1" }] },                    // tasks.entity_id
      { rows: [] },                                // entity_comments.entity_id
      { rows: [{ id: "dc1" }] },                   // duplicate_candidates -> merged
      { rows: [] },                                // soft-delete loser
      { rows: [{ id: "ml1" }] },                   // insert merge_log
    ]);
    const result = await service.mergeLeads(actor, "l-lo", "l-wi");
    expect(result).toEqual({ mergeLogId: "ml1", winnerId: "l-wi" });
    expect(transaction).toHaveBeenCalledTimes(1);
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    const sql = query.mock.calls.map((c) => String(c[0])).join("\n");
    expect(sql).toContain("update app.students set lead_id");
    expect(sql).toContain("update app.leads set deleted_at = now()");
    expect(sql).toContain("insert into app.merge_log");
    // merge_log insert carries the captured repointed ids
    const mlInsert = query.mock.calls.find((c) => String(c[0]).includes("insert into app.merge_log"));
    expect(JSON.stringify(mlInsert?.[1])).toContain("students.lead_id");
  });

  it("mergeLeads rejects merging a lead into itself", async () => {
    const { service } = createMergeService([]);
    await expect(service.mergeLeads(actor, "same", "same")).rejects.toThrow(BadRequestException);
  });
```

(`BadRequestException` is imported in the spec already, or add it from `@nestjs/common`.)

- [ ] **Step 2: Run to verify failure**

Run: `cd server && npx jest src/crm/crm.service.spec.ts -t "merge"`
Expected: FAIL — `service.listMergeCandidates is not a function`.

- [ ] **Step 3: Implement `listMergeCandidates`**

Add to `CrmService`:

```typescript
  async listMergeCandidates(actor: ActorContext, limit = 50) {
    this.policy.assertCanReadOperationalData(actor);
    const capped = Math.min(Math.max(limit, 1), 200);
    const result = await this.database.query<{
      loser_id: string;
      winner_id: string;
      phone: string | null;
      name: string;
    }>(
      `select l1.id as loser_id, l2.id as winner_id, l2.phone_normalized as phone,
              btrim(concat_ws(' ', l2.first_name, l2.last_name)) as name
         from app.leads l1
         join app.leads l2
           on l1.phone_normalized = l2.phone_normalized
          and lower(btrim(coalesce(l1.first_name, ''))) = lower(btrim(coalesce(l2.first_name, '')))
          and lower(btrim(coalesce(l1.last_name, '')))  = lower(btrim(coalesce(l2.last_name, '')))
          and l1.id < l2.id
        where l1.deleted_at is null and l2.deleted_at is null
          and l1.phone_normalized is not null
        order by l2.phone_normalized
        limit $1`,
      [capped],
    );
    return {
      items: result.rows.map((row) => ({
        loserId: row.loser_id,
        winnerId: row.winner_id,
        phone: row.phone,
        name: row.name,
      })),
    };
  }
```

- [ ] **Step 4: Implement `mergeLeads`**

Add to `CrmService` (mirror the `database.transaction(async (client) => {...})` pattern from `saveContactFromChat`):

```typescript
  async mergeLeads(actor: ActorContext, loserId: string, winnerId: string) {
    this.policy.assertCanWriteCrm(actor);
    if (loserId === winnerId) {
      throw new BadRequestException("Нельзя объединить лид сам с собой.");
    }
    return this.database.transaction(async (client) => {
      const existing = await client.query<{ id: string }>(
        `select id from app.leads where id in ($1, $2) and deleted_at is null`,
        [loserId, winnerId],
      );
      if (existing.rows.length !== 2) {
        throw new NotFoundException("Один из лидов не найден.");
      }

      const repointed: Record<string, string[]> = {};
      const ids = (rows: { id: string }[]) => rows.map((r) => r.id);

      // Real-FK lead references.
      repointed["students.lead_id"] = ids(
        (await client.query<{ id: string }>(
          `update app.students set lead_id = $2, updated_at = now() where lead_id = $1 and deleted_at is null returning id`,
          [loserId, winnerId],
        )).rows,
      );
      repointed["lessons.lead_id"] = ids(
        (await client.query<{ id: string }>(
          `update app.lessons set lead_id = $2 where lead_id = $1 returning id`,
          [loserId, winnerId],
        )).rows,
      );
      repointed["lead_status_history.lead_id"] = ids(
        (await client.query<{ id: string }>(
          `update app.lead_status_history set lead_id = $2 where lead_id = $1 returning id`,
          [loserId, winnerId],
        )).rows,
      );
      repointed["lead_comments.lead_id"] = ids(
        (await client.query<{ id: string }>(
          `update app.lead_comments set lead_id = $2 where lead_id = $1 returning id`,
          [loserId, winnerId],
        )).rows,
      );
      // Polymorphic (no unique constraint).
      repointed["tasks.entity_id"] = ids(
        (await client.query<{ id: string }>(
          `update app.tasks set entity_id = $2 where entity_type = 'lead' and entity_id = $1 returning id`,
          [loserId, winnerId],
        )).rows,
      );
      repointed["entity_comments.entity_id"] = ids(
        (await client.query<{ id: string }>(
          `update app.entity_comments set entity_id = $2 where entity_type = 'lead' and entity_id = $1 returning id`,
          [loserId, winnerId],
        )).rows,
      );
      // Mark duplicate candidates merged (capture for undo).
      repointed["duplicate_candidates.status"] = ids(
        (await client.query<{ id: string }>(
          `update app.duplicate_candidates set status = 'merged', updated_at = now()
            where status = 'pending'
              and ((entity_type_a = 'lead' and entity_id_a = $1) or (entity_type_b = 'lead' and entity_id_b = $1))
            returning id`,
          [loserId],
        )).rows,
      );

      // Soft-delete the loser (CASCADE never fires — no hard delete).
      await client.query(
        `update app.leads set deleted_at = now(), updated_at = now() where id = $1`,
        [loserId],
      );

      const log = await client.query<{ id: string }>(
        `insert into app.merge_log (entity_type, loser_id, winner_id, repointed, merged_by)
         values ('lead', $1, $2, $3::jsonb, $4) returning id`,
        [loserId, winnerId, JSON.stringify(repointed), actor.userId],
      );
      return { mergeLogId: log.rows[0].id, winnerId };
    });
  }
```

- [ ] **Step 5: Implement `undoMerge`**

Add to `CrmService`:

```typescript
  // Reverse-op for each known repointed key. Hard-coded — never derives a table
  // name from stored data.
  private static readonly UNDO_REPOINT: Record<string, string> = {
    "students.lead_id": "update app.students set lead_id = $1, updated_at = now() where id = any($2::uuid[])",
    "lessons.lead_id": "update app.lessons set lead_id = $1 where id = any($2::uuid[])",
    "lead_status_history.lead_id": "update app.lead_status_history set lead_id = $1 where id = any($2::uuid[])",
    "lead_comments.lead_id": "update app.lead_comments set lead_id = $1 where id = any($2::uuid[])",
    "tasks.entity_id": "update app.tasks set entity_id = $1 where id = any($2::uuid[])",
    "entity_comments.entity_id": "update app.entity_comments set entity_id = $1 where id = any($2::uuid[])",
    "duplicate_candidates.status": "update app.duplicate_candidates set status = 'pending', updated_at = now() where id = any($2::uuid[])",
  };

  async undoMerge(actor: ActorContext, mergeLogId: string) {
    this.policy.assertCanWriteCrm(actor);
    return this.database.transaction(async (client) => {
      const logRes = await client.query<{
        loser_id: string;
        repointed: Record<string, string[]>;
      }>(
        `select loser_id, repointed from app.merge_log where id = $1 and undone_at is null`,
        [mergeLogId],
      );
      const log = logRes.rows[0];
      if (!log) {
        throw new NotFoundException("Слияние не найдено или уже отменено.");
      }
      for (const [key, sql] of Object.entries(CrmService.UNDO_REPOINT)) {
        const movedIds = log.repointed[key];
        if (!movedIds || movedIds.length === 0) continue;
        const isDupCandidate = key === "duplicate_candidates.status";
        await client.query(sql, isDupCandidate ? [null, movedIds] : [log.loser_id, movedIds]);
      }
      // The duplicate_candidates reverse SQL ignores $1; pass null there.
      await client.query(
        `update app.leads set deleted_at = null, updated_at = now() where id = $1`,
        [log.loser_id],
      );
      await client.query(
        `update app.merge_log set undone_at = now(), undone_by = $2 where id = $1`,
        [mergeLogId, actor.userId],
      );
      return { success: true as const };
    });
  }
```

> Note: the `duplicate_candidates.status` reverse SQL has only `$2` for ids and a literal `'pending'`, so passing `[null, movedIds]` binds `$1=null` (unused) and `$2=ids`. All other reverse SQLs use `$1=loser_id, $2=ids`. This keeps the call uniform.

- [ ] **Step 6: Add the controller routes**

Add to `server/src/crm/crm.controller.ts`:

```typescript
  @Get("merge-candidates")
  listMergeCandidates(
    @CurrentActor() actor: ActorContext,
    @Query("limit") limit?: string,
  ) {
    return this.crm.listMergeCandidates(actor, limit ? Number(limit) : undefined);
  }

  @Post("leads/:winnerId/merge/:loserId")
  mergeLeads(
    @CurrentActor() actor: ActorContext,
    @Param("winnerId", ParseUUIDPipe) winnerId: string,
    @Param("loserId", ParseUUIDPipe) loserId: string,
  ) {
    return this.crm.mergeLeads(actor, loserId, winnerId);
  }

  @Post("merges/:mergeLogId/undo")
  undoMerge(
    @CurrentActor() actor: ActorContext,
    @Param("mergeLogId", ParseUUIDPipe) mergeLogId: string,
  ) {
    return this.crm.undoMerge(actor, mergeLogId);
  }
```

- [ ] **Step 7: Run tests + typecheck**

Run: `cd server && npm run typecheck && npm test`
Expected: typecheck 0; the merge tests pass; full suite green.

- [ ] **Step 8: Commit**

```bash
git add server/src/crm/crm.service.ts server/src/crm/crm.controller.ts server/src/crm/crm.service.spec.ts
git commit -m "feat(crm): lead merge candidates + transactional mergeLeads + undoMerge (KVA-190)"
```

---

## Self-Review

- **Spec coverage (§4A7):** merge-candidate queue by phone+name ✅; transactional `mergeLeads` (soft-delete, no cascade) ✅; precise `undoMerge` via captured row ids ✅; `duplicate_candidates` lifecycle ✅. Student merge deferred (`merge_log` supports it). Review-queue UI deferred to Flutter.
- **Placeholder scan:** none — full SQL/TS/tests with exact commands.
- **Safety:** no hard delete anywhere → CASCADE FKs never fire → no payment/history/comment loss; the entire merge and undo are each one transaction; undo moves back ONLY the captured rows (winner's own rows untouched).
- **Type consistency:** `repointed` keys produced in `mergeLeads` exactly match the hard-coded `UNDO_REPOINT` keys consumed in `undoMerge`; method names match across service/controller/tests.
- **Documented limitation:** `family_members`/`user_crm_links`/`contacts` (entity_type='lead') are not auto-repointed (rare for leads; loser soft-delete hides them).

## Dependency note

A7 unblocks the Flutter merge-review UI (queue + confirm-merge + Undo toast) — a follow-up Flutter task. `mergeStudents` is a future task (financial re-point + balance recompute) on the same `merge_log`. Migration `0030` is applied to prod later, batched with the other Epic A migrations.
