# Epic A · Task A1 — Phone Normalization Foundation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish one canonical Russian phone-normalization function, add an indexed `phone_normalized` column to leads & profiles, backfill it, and route un-normalizable numbers into a visible review queue — the linking/dedup/family key the rest of Epic A depends on.

**Architecture:** A single pure util (`phone.util.ts`) is the only source of truth for phone normalization, in both TypeScript (row writes) and SQL (bulk backfill + joins). A numbered SQL migration adds the column + `phone_review_queue` table and backfills using the identical SQL expression. The three pre-existing divergent normalizers delegate to the new util. A read-only endpoint exposes the queue count for a UI badge.

**Tech Stack:** NestJS + TypeScript, PostgreSQL (numbered up/down SQL migrations via `MigrationRunner`), Jest (`jest --runInBand`).

**Linear:** KVA-184 (A1) under epic KVA-178 (A). Spec: `docs/superpowers/specs/2026-06-19-clients-window-and-management-analytics-design.md` (§2, §4A1).

## Global Constraints

- Canonical phone format stored in DB: `+7XXXXXXXXXX` (literal `+7` + exactly 10 digits). Display formatting `+7 (XXX) XXX XX XX` is a client concern (Task A2, not here).
- Never guess un-normalizable numbers — route them to `app.phone_review_queue` with a reason.
- Phone is a **family** key, not a person key — A1 only normalizes/queues; it must NOT merge or link records (that is A3/A7).
- Migrations: numbered `NNNN_name.up.sql` / `.down.sql` in `server/db/migrations/`, plain idempotent SQL (`if not exists`), `id uuid primary key default gen_random_uuid()`, schema prefix `app.`. **Every new table MUST end with a `grant select, insert, update, delete ... to magiccrm_app` block guarded by `if exists (select 1 from pg_roles where rolname = 'magiccrm_app')`.**
- Run from `server/`: migrations `npm run db:migrate` / `npm run db:rollback`; tests `npm test`; types `npm run typecheck`.
- This task's migration id is **`0025_phone_normalization`** (next free number after `0024_branch_timezone`).

---

## File Structure

- **Create** `server/src/crm/phone.util.ts` — pure functions `normalizePhoneRu()` + `normalizedPhoneExpr()`. Single source of truth.
- **Create** `server/src/crm/phone.util.spec.ts` — unit tests for the util.
- **Create** `server/db/migrations/0025_phone_normalization.up.sql` — columns, indexes, `phone_review_queue` table + grant, backfill.
- **Create** `server/db/migrations/0025_phone_normalization.down.sql` — reverse.
- **Modify** `server/src/profile/profile.service.ts:1326-1344` — `normalizePhone` / `normalizedPhoneSql` delegate to the util.
- **Modify** `server/src/crm/crm.service.ts:4046-4050` — `normalizeContactPhone` delegates to the util; add `countPhoneReviewQueue()` + `listPhoneReviewQueue()`.
- **Modify** `server/src/crm/crm.controller.ts` — add `GET /crm/phone-review-queue` + `GET /crm/phone-review-queue/count`.
- **Modify** `server/src/migration/hollihop-import.ts:2479-2487` — local `normalizePhone` delegates to the util.
- **Modify** `server/src/crm/crm.service.spec.ts` — add tests for the two new service methods.

---

## Task 1: Canonical phone util

**Files:**
- Create: `server/src/crm/phone.util.ts`
- Test: `server/src/crm/phone.util.spec.ts`

**Interfaces:**
- Produces:
  - `type PhoneNormalizationReason = 'ok' | 'empty' | 'too_short' | 'non_ru'`
  - `interface NormalizedPhone { canonical: string | null; reason: PhoneNormalizationReason }`
  - `function normalizePhoneRu(raw: string | null | undefined): NormalizedPhone`
  - `function normalizedPhoneExpr(column: string): string` — SQL snippet returning the same canonical value (`+7XXXXXXXXXX` or `null`) for a phone column.

- [ ] **Step 1: Write the failing test**

```typescript
// server/src/crm/phone.util.spec.ts
import { normalizePhoneRu, normalizedPhoneExpr } from "./phone.util";

describe("normalizePhoneRu", () => {
  it("canonicalizes valid RU numbers to +7XXXXXXXXXX", () => {
    expect(normalizePhoneRu("+7 (909) 123-45-67").canonical).toBe("+79091234567");
    expect(normalizePhoneRu("89091234567").canonical).toBe("+79091234567");
    expect(normalizePhoneRu("9091234567").canonical).toBe("+79091234567");
    expect(normalizePhoneRu("+7 909 123 45 67").reason).toBe("ok");
  });

  it("routes empty / short / non-RU to null with a reason", () => {
    expect(normalizePhoneRu("")).toEqual({ canonical: null, reason: "empty" });
    expect(normalizePhoneRu(null)).toEqual({ canonical: null, reason: "empty" });
    expect(normalizePhoneRu("12345")).toEqual({ canonical: null, reason: "too_short" });
    // +1 202 555 0143 -> 11 digits starting with 1 -> not a RU number
    expect(normalizePhoneRu("+1 202 555 0143")).toEqual({ canonical: null, reason: "non_ru" });
  });

  it("emits a SQL expression that references the column", () => {
    const sql = normalizedPhoneExpr("l.phone");
    expect(sql).toContain("l.phone");
    expect(sql).toContain("'+7'");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && npx jest src/crm/phone.util.spec.ts`
Expected: FAIL — `Cannot find module './phone.util'`.

- [ ] **Step 3: Write minimal implementation**

```typescript
// server/src/crm/phone.util.ts
export type PhoneNormalizationReason = "ok" | "empty" | "too_short" | "non_ru";

export interface NormalizedPhone {
  canonical: string | null; // '+7XXXXXXXXXX' for valid RU numbers, else null
  reason: PhoneNormalizationReason;
}

// Single source of truth for Russian phone normalization (replaces the three
// historical variants in profile/crm/import). Returns the canonical +7 form or
// null + a reason so callers can route un-normalizable values to review.
export function normalizePhoneRu(raw: string | null | undefined): NormalizedPhone {
  const digits = (raw ?? "").replace(/\D/g, "");
  if (digits.length === 0) return { canonical: null, reason: "empty" };
  if (digits.length === 11 && (digits[0] === "7" || digits[0] === "8")) {
    return { canonical: `+7${digits.slice(1)}`, reason: "ok" };
  }
  if (digits.length === 10 && digits[0] === "9") {
    return { canonical: `+7${digits}`, reason: "ok" };
  }
  return { canonical: null, reason: digits.length < 10 ? "too_short" : "non_ru" };
}

// SQL expression producing the IDENTICAL canonical value for a phone column,
// for use in bulk backfill and join-on-phone queries. Keep in lockstep with
// normalizePhoneRu above.
export function normalizedPhoneExpr(column: string): string {
  const digits = `regexp_replace(coalesce(${column}, ''), '[^0-9]', '', 'g')`;
  return `
    case
      when length(${digits}) = 11 and left(${digits}, 1) in ('7', '8') then '+7' || right(${digits}, 10)
      when length(${digits}) = 10 and left(${digits}, 1) = '9' then '+7' || ${digits}
      else null
    end
  `;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd server && npx jest src/crm/phone.util.spec.ts`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add server/src/crm/phone.util.ts server/src/crm/phone.util.spec.ts
git commit -m "feat(crm): canonical RU phone normalization util (KVA-184)"
```

---

## Task 2: Migration 0025 — column, review queue, backfill

**Files:**
- Create: `server/db/migrations/0025_phone_normalization.up.sql`
- Create: `server/db/migrations/0025_phone_normalization.down.sql`

**Interfaces:**
- Produces (DB): `app.leads.phone_normalized text`, `app.profiles.phone_normalized text` (+ partial indexes); table `app.phone_review_queue(id, entity_type, entity_id, raw_phone, reason, created_at, resolved_at, resolved_by, unique(entity_type, entity_id))`.

- [ ] **Step 1: Write the up migration**

```sql
-- server/db/migrations/0025_phone_normalization.up.sql
-- Canonical phone foundation: phone_normalized column + review queue + backfill.
alter table app.leads add column if not exists phone_normalized text;
alter table app.profiles add column if not exists phone_normalized text;

create index if not exists leads_phone_normalized_idx
  on app.leads (phone_normalized) where deleted_at is null;
create index if not exists profiles_phone_normalized_idx
  on app.profiles (phone_normalized) where deleted_at is null;

create table if not exists app.phone_review_queue (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null,
  entity_id uuid not null,
  raw_phone text,
  reason text not null,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references app.users(id) on delete set null,
  constraint phone_review_queue_entity_check check (entity_type in ('lead', 'profile')),
  constraint phone_review_queue_reason_check check (reason in ('empty', 'too_short', 'non_ru')),
  constraint phone_review_queue_identity_unique unique (entity_type, entity_id)
);

create index if not exists phone_review_queue_open_idx
  on app.phone_review_queue (created_at desc) where resolved_at is null;

-- Backfill canonical phone (mirror of normalizedPhoneExpr / normalizePhoneRu).
update app.leads l
set phone_normalized = case
    when length(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g')) = 11
         and left(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g'), 1) in ('7', '8')
      then '+7' || right(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g'), 10)
    when length(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g')) = 10
         and left(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g'), 1) = '9'
      then '+7' || regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g')
    else null
  end
where l.deleted_at is null;

update app.profiles p
set phone_normalized = case
    when length(regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g')) = 11
         and left(regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g'), 1) in ('7', '8')
      then '+7' || right(regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g'), 10)
    when length(regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g')) = 10
         and left(regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g'), 1) = '9'
      then '+7' || regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g')
    else null
  end
where p.deleted_at is null;

-- Route un-normalizable rows into the review queue.
insert into app.phone_review_queue (entity_type, entity_id, raw_phone, reason)
select 'lead', l.id, l.phone,
  case
    when regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g') = '' then 'empty'
    when length(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g')) < 10 then 'too_short'
    else 'non_ru'
  end
from app.leads l
where l.deleted_at is null and l.phone_normalized is null
on conflict (entity_type, entity_id) do nothing;

insert into app.phone_review_queue (entity_type, entity_id, raw_phone, reason)
select 'profile', p.id, p.phone,
  case
    when regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g') = '' then 'empty'
    when length(regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g')) < 10 then 'too_short'
    else 'non_ru'
  end
from app.profiles p
where p.deleted_at is null and p.phone_normalized is null
on conflict (entity_type, entity_id) do nothing;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert, update, delete on app.phone_review_queue to magiccrm_app;
  end if;
end $$;
```

- [ ] **Step 2: Write the down migration**

```sql
-- server/db/migrations/0025_phone_normalization.down.sql
drop table if exists app.phone_review_queue;
alter table app.leads drop column if exists phone_normalized;
alter table app.profiles drop column if exists phone_normalized;
```

- [ ] **Step 3: Apply the migration against a database**

Run (with `DATABASE_URL` pointing at a local/staging DB):
`cd server && npm run db:migrate`
Expected output contains: `Applied migrations: 0025_phone_normalization`

- [ ] **Step 4: Verify schema + backfill**

Run (adjust connection to your DB; staging pattern shown):
```bash
psql "$DATABASE_URL" -c "select count(*) filter (where phone_normalized is not null) as normalized, count(*) filter (where phone_normalized is null) as queued from app.leads where deleted_at is null;"
psql "$DATABASE_URL" -c "select reason, count(*) from app.phone_review_queue group by reason order by reason;"
```
Expected (on prod-shaped data): leads normalized ≈ 3628, queued ≈ 55; queue reasons include `empty` and `non_ru`. Every queued lead/profile must have `phone_normalized IS NULL`; every normalized value matches `^\+7\d{10}$`.

- [ ] **Step 5: Verify rollback then re-apply**

```bash
cd server && npm run db:rollback   # Expected: Reverted migration: 0025_phone_normalization
psql "$DATABASE_URL" -c "select 1 from information_schema.columns where table_schema='app' and table_name='leads' and column_name='phone_normalized';"  # Expected: 0 rows
cd server && npm run db:migrate    # Re-apply; Expected: Applied migrations: 0025_phone_normalization
```

- [ ] **Step 6: Commit**

```bash
git add server/db/migrations/0025_phone_normalization.up.sql server/db/migrations/0025_phone_normalization.down.sql
git commit -m "feat(db): phone_normalized column + phone_review_queue + backfill (KVA-184)"
```

---

## Task 3: Delegate the three legacy normalizers to the util

**Files:**
- Modify: `server/src/profile/profile.service.ts:1326-1344`
- Modify: `server/src/crm/crm.service.ts:4046-4050`
- Modify: `server/src/migration/hollihop-import.ts:2479-2487`

**Interfaces:**
- Consumes: `normalizePhoneRu`, `normalizedPhoneExpr` from `../crm/phone.util` (Task 1).
- Note: post-refactor, both the TS write path and the SQL compare path emit `+7XXXXXXXXXX`, so they stay in lockstep. Historical `matched_phone` values keep their old format but are audit hints only (not re-compared against the new canonical).

- [ ] **Step 1: Update profile.service.ts**

Replace the body of `normalizePhone` and `normalizedPhoneSql` (lines 1326-1344):

```typescript
  private normalizePhone(phone: string | null | undefined): string | null {
    return normalizePhoneRu(phone).canonical;
  }

  private normalizedPhoneSql(column: string): string {
    return normalizedPhoneExpr(column);
  }
```

Add the import at the top of the file (next to existing imports):

```typescript
import { normalizePhoneRu, normalizedPhoneExpr } from "../crm/phone.util";
```

- [ ] **Step 2: Update crm.service.ts**

Replace `normalizeContactPhone` (lines 4046-4050):

```typescript
  private normalizeContactPhone(phone: string | null | undefined): string | null {
    return normalizePhoneRu(phone).canonical;
  }
```

Add the import near the top of `crm.service.ts` (the file already imports from local modules):

```typescript
import { normalizePhoneRu, normalizedPhoneExpr } from "./phone.util";
```

- [ ] **Step 3: Update hollihop-import.ts**

Replace the local `normalizePhone` (lines 2479-2487) body to delegate (keep the existing function name/signature so callers are unchanged):

```typescript
function normalizePhone(value: string | undefined): string | undefined {
  return normalizePhoneRu(value).canonical ?? undefined;
}
```

Add the import at the top of `hollihop-import.ts`:

```typescript
import { normalizePhoneRu } from "../crm/phone.util";
```

- [ ] **Step 4: Run the full server suite + typecheck**

Run: `cd server && npm run typecheck && npm test`
Expected: typecheck exits 0; all existing tests pass (no regression). The previously-passing dedup/import tests now run through the shared util.

- [ ] **Step 5: Commit**

```bash
git add server/src/profile/profile.service.ts server/src/crm/crm.service.ts server/src/migration/hollihop-import.ts
git commit -m "refactor(crm): route phone normalization through shared util (KVA-184)"
```

---

## Task 4: Expose the review-queue count + list

**Files:**
- Modify: `server/src/crm/crm.service.ts` (add two methods near the other read methods)
- Modify: `server/src/crm/crm.controller.ts` (add two GET routes)
- Modify: `server/src/crm/crm.service.spec.ts` (add tests)

**Interfaces:**
- Produces:
  - `CrmService.countPhoneReviewQueue(actor: ActorContext): Promise<{ count: number }>`
  - `CrmService.listPhoneReviewQueue(actor: ActorContext, limit?: number): Promise<{ items: Array<{ id: string; entityType: string; entityId: string; rawPhone: string | null; reason: string; createdAt: string }> }>`
  - `GET /crm/phone-review-queue/count` → `{ count }`
  - `GET /crm/phone-review-queue` → `{ items }`

- [ ] **Step 1: Write the failing tests**

Add to `server/src/crm/crm.service.spec.ts` (use the existing `createServiceWithQueryResults` helper):

```typescript
  it("counts open phone-review-queue rows", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      { rows: [{ count: "55" }] },
    ]);
    const result = await service.countPhoneReviewQueue(actor);
    expect(result).toEqual({ count: 55 });
    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("app.phone_review_queue");
    expect(query.mock.calls[0][0]).toContain("resolved_at is null");
  });

  it("lists open phone-review-queue rows", async () => {
    const { service, query } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "q1",
            entity_type: "lead",
            entity_id: "l1",
            raw_phone: "123",
            reason: "too_short",
            created_at: "2026-06-19T00:00:00.000Z",
          },
        ],
      },
    ]);
    const result = await service.listPhoneReviewQueue(actor, 25);
    expect(result.items[0]).toEqual({
      id: "q1",
      entityType: "lead",
      entityId: "l1",
      rawPhone: "123",
      reason: "too_short",
      createdAt: "2026-06-19T00:00:00.000Z",
    });
    expect(query.mock.calls[0][1]).toEqual([25]);
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `cd server && npx jest src/crm/crm.service.spec.ts -t "phone-review-queue"`
Expected: FAIL — `service.countPhoneReviewQueue is not a function`.

- [ ] **Step 3: Implement the service methods**

Add to `CrmService` in `server/src/crm/crm.service.ts` (near `listLeadStatuses`):

```typescript
  async countPhoneReviewQueue(actor: ActorContext): Promise<{ count: number }> {
    this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<{ count: string }>(
      `select count(*)::text as count from app.phone_review_queue where resolved_at is null`,
    );
    return { count: Number(result.rows[0]?.count ?? 0) };
  }

  async listPhoneReviewQueue(actor: ActorContext, limit = 50) {
    this.policy.assertCanReadOperationalData(actor);
    const capped = Math.min(Math.max(limit, 1), 200);
    const result = await this.database.query<{
      id: string;
      entity_type: string;
      entity_id: string;
      raw_phone: string | null;
      reason: string;
      created_at: string;
    }>(
      `select id, entity_type, entity_id, raw_phone, reason, created_at
         from app.phone_review_queue
        where resolved_at is null
        order by created_at desc
        limit $1`,
      [capped],
    );
    return {
      items: result.rows.map((row) => ({
        id: row.id,
        entityType: row.entity_type,
        entityId: row.entity_id,
        rawPhone: row.raw_phone,
        reason: row.reason,
        createdAt: row.created_at,
      })),
    };
  }
```

> Note: the test calls `listPhoneReviewQueue(actor, 25)` and expects param `[25]`; `Math.min(Math.max(25,1),200)` = 25, so the assertion holds.

- [ ] **Step 4: Add the controller routes**

Add to `server/src/crm/crm.controller.ts` (follow the existing `@Get(...)` + `@CurrentActor()` pattern used by `/crm/overview`):

```typescript
  @Get("phone-review-queue/count")
  countPhoneReviewQueue(@CurrentActor() actor: ActorContext) {
    return this.crm.countPhoneReviewQueue(actor);
  }

  @Get("phone-review-queue")
  listPhoneReviewQueue(
    @CurrentActor() actor: ActorContext,
    @Query("limit") limit?: string,
  ) {
    return this.crm.listPhoneReviewQueue(actor, limit ? Number(limit) : undefined);
  }
```

(If `@Query` / `ActorContext` / `@CurrentActor` are not already imported in this controller, add them to the existing import lines — check the top of the file; `/crm/leads` routes already use this exact pattern.)

- [ ] **Step 5: Run tests + typecheck**

Run: `cd server && npm run typecheck && npx jest src/crm/crm.service.spec.ts`
Expected: typecheck 0; the two new tests PASS; existing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add server/src/crm/crm.service.ts server/src/crm/crm.controller.ts server/src/crm/crm.service.spec.ts
git commit -m "feat(crm): expose phone-review-queue count + list endpoints (KVA-184)"
```

---

## Self-Review

- **Spec coverage (§4A1):** canonical util ✅ (Task 1); `phone_normalized` columns + indexes + backfill ✅ (Task 2); `phone_review_queue` ✅ (Task 2); three normalizers unified ✅ (Task 3); queue visible via count/list endpoint ✅ (Task 4). The Flutter input mask + badge are explicitly **out of scope** here — they belong to Task A2 (KVA-185), which consumes this foundation.
- **Placeholder scan:** none — every step carries real SQL/TS and exact commands.
- **Type consistency:** `normalizePhoneRu`/`normalizedPhoneExpr` names identical across Tasks 1/3; canonical form `+7XXXXXXXXXX` consistent between the TS function, the SQL expression, and the migration backfill (verified by the `^\+7\d{10}$` check in Task 2 Step 4); service method names match between Task 4 tests, implementation, and controller.
- **Backfill ↔ util parity:** the migration's inline `case` (Task 2) is the literal expansion of `normalizedPhoneExpr` (Task 1) — if one changes, change both.

---

## Dependency note

A1 unblocks **A2** (input mask consumes the canonical format + queue badge), **A3** (families seed from `phone_normalized` matches), **A7** (dedup keys on `phone_normalized` + name). The remaining Epic A subsystems (A4 branch_id, A5 status-history, A6 dictionaries) are independent of A1 and each gets its own plan when scheduled.
