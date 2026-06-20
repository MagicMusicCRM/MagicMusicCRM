# HolliHop lead status-history import → `app.lead_status_history` — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Import **real lead status-change history** from HolliHop's `GetHistoryModifyLeadStatus` API method into the already-deployed `app.lead_status_history` table (migration 0028). Each history row `{LeadId, DateTime, AfterId, AfterName}` becomes one `lead_status_history` row: `LeadId → lead_id`, `AfterId → new_status_id`, `DateTime → changed_at`. This gives the funnel/loss-reason analytics (Epic E) and the lead timeline real transition events instead of only the current `status_id` snapshot.

**Architecture:** Extend the existing standalone importer `server/src/migration/hollihop-import.ts`. The history feed is added to the `HolliHopData` shape, fetched via the same `fetchPaged` pagination (API path) and `readArrayFile`/`loadFromDirectory` (local fixture path), then upserted by a new `importLeadStatusHistory(ctx, rows, maps)` function called from `importAll`. It reuses the existing maps built earlier in `importAll`: `leadById` (HolliHop lead Id → deterministic lead uuid) and `statusById` (HolliHop status Id → reconciled `app.lead_statuses.id`). Rows are idempotent via `deterministicUuid`; they go through the existing `planUpsert` (dry-run counts only, apply writes) and `recordSource` (provenance) wrappers, exactly like `importTasks`/`importTimeline`.

**Tech Stack:** NestJS/TypeScript standalone script (pg `Pool`), PostgreSQL 16, Jest. No new dependency. Run from `server/`: tests `npm test`, types `npm run typecheck`, migrations `npm run db:migrate`. Docker-validated only (never prod).

**Backend (already deployed):** migration `0028_status_history` (`app.lead_status_history`) is applied on the VPS; the main HolliHop import (epic B) has already populated `app.leads` and `app.lead_statuses`. This change only adds a new feed to the same importer.

## Global Constraints

- **Source shape (HolliHop `GetHistoryModifyLeadStatus`):** each row is `{ LeadId, DateTime, AfterId, AfterName }`.
  - `LeadId` — HolliHop external lead id (string|number). Resolve via `leadById.get(text(row.LeadId))` (the same `deterministicUuid("hollihop-lead", externalId)` derivation built in `importAll`, see `hollihop-import.ts:726-727`). If the lead is not in scope → **skip + warn** (do NOT invent a lead; `lead_id` is `not null` with an FK to `app.leads`).
  - `AfterId` — the status id the lead moved **to**. Resolve via `statusById.get(text(row.AfterId))` (the reconciled `app.lead_statuses.id`, built at `hollihop-import.ts:336-371`). If unresolved → `new_status_id = null` (the column is nullable) and keep `AfterName` in `source_snapshot` so the reference is not lost. Do NOT skip the row for a missing status — the transition timestamp is still meaningful.
  - `DateTime` — Moscow-local datetime **without timezone** (HolliHop convention, same as `Created`/`Updated` elsewhere). Map to `changed_at` using `iso()` (`hollihop-import.ts:2164`). Because the string carries no offset, append `MOSCOW_OFFSET` (`"+03:00"`, `hollihop-import.ts:33`) before parsing so the instant is correct: `iso(appendMoscowOffset(text(row.DateTime)))`. If unparseable → skip + warn (a history row with no timestamp is useless).
  - `AfterName` — human-readable status name; stored verbatim in `source_snapshot` for traceability (and as the only signal when `AfterId` doesn't resolve).
- **Verify the response root key before coding.** `fetchPaged(method, rootKey)` reads `data[rootKey]` (`hollihop-import.ts:1959-1969`). The HolliHop convention is the method name minus the `Get` prefix (`GetStudents`→`Students`, `GetLeads`→`Leads`). For `GetHistoryModifyLeadStatus` the expected root key is **`HistoryModifyLeadStatus`** — but this MUST be confirmed against a real one-page response (Task 2, Step 0). Use `fetchOptionalPaged` (not `fetchPaged`) so a missing/forbidden endpoint degrades to `[]` + a warning instead of failing the whole import (mirrors `GetTasks`/`GetStudentLogs` at `hollihop-import.ts:1928-1932`).
- **Target table `app.lead_status_history`** (migration `server/db/migrations/0028_status_history.up.sql`): columns `id`, `lead_id` (not null, FK `app.leads`), `old_status_id` (FK `app.lead_statuses`, nullable), `new_status_id` (FK `app.lead_statuses`, nullable), `old_owner_id`, `new_owner_id`, `changed_by` (FK `app.users`, nullable), `changed_at` (timestamptz not null), `reason_id` (FK `app.lead_loss_reasons`, nullable), `comment`, `branch_id` (FK `app.branches`, nullable), `source_snapshot` (text).
  - This feed knows only the **destination** status, so `old_status_id` stays `null` (the API gives `AfterId` only; we never guess the "before"). `changed_by`, `reason_id`, `old_owner_id`, `new_owner_id`, `comment` stay `null` (not provided by this endpoint). `branch_id` is best-effort: the lead's current `branch_id` (joined in SQL is overkill — instead carry it from the already-imported lead via a `leadBranchById` map populated in the leads loop; see Task 3 Step 3). If unknown → `null`.
- **Idempotent id:** `id = deterministicUuid("hollihop-lead-status-history", `${leadExternalId}:${afterIdRaw}:${dateTimeRaw}`)`. Keying on the raw `LeadId` + raw `AfterId` + raw `DateTime` makes re-imports of the same history row collapse to the same uuid, while a genuine second transition (different timestamp) gets its own row. Upsert with `conflictColumns = ["id"]` (the existing `upsert` builds the `on conflict (id) do update set …` clause, `hollihop-import.ts:1562-1600`).
- **Dry-run vs apply:** all writes go through `planUpsert(ctx, "leadStatusHistory", "app.lead_status_history", row, ["id"])` which increments `ctx.plannedCounts.leadStatusHistory` always and writes only when `ctx.mode === "apply"` (`hollihop-import.ts:1550-1560`). Skips go through `skip(ctx, "leadStatusHistory")`; warnings through `warn(ctx, …)`.
- **Provenance:** call `recordSource(ctx, { source: "leadStatusHistory", externalId, … })` (gated by `STORE_SOURCE_RECORDS`) so each history row lands in `app.import_source_records` with `target_table = "app.lead_status_history"`, mirroring `importTimeline` (`hollihop-import.ts:1185-1207`). `externalId` = `${LeadId}:${AfterId}:${DateTime}` (unique per history event).
- **Counts/report:** add `leadStatusHistory` to the source array in `countSources` (`hollihop-import.ts:2073-2091`) and to `loadFromDirectory`/`fetchFromApi`; add a `lead_status_history` count to `readStoredCounts` (`hollihop-import.ts:1764-1790`) so the printed report shows stored rows. `checksumSources` iterates `Object.entries(data)` so it picks up the new key automatically.
- **Conflict note (concurrency):** this task edits the SINGLE file `server/src/migration/hollihop-import.ts` (plus the `HolliHopData` interface, `importAll`, `fetchFromApi`, `loadFromDirectory`, `countSources`, `readStoredCounts` in that same file). If another importer-extension stream runs concurrently it will also touch `hollihop-import.ts` → **serialize these tasks or expect a merge conflict**. The new pure mapper lives in its own file (`hollihop-history-mappers.ts`) to keep the unit-testable shaping isolated and conflict-free.
- **Run/verify:** from `server/`: `npm run typecheck` (0 errors), `npm test` (green). Docker-validate the end-to-end upsert against a throwaway Postgres 16 (Task 4). Prod run is operator-gated and out of scope here.

---

## File Structure

- **Create** `server/src/migration/hollihop-history-mappers.ts` — pure shaping (`historyEntryFromRow`, `appendMoscowOffset`). No DB / IO.
- **Create** `server/src/migration/hollihop-history-mappers.spec.ts` — unit tests for the mapper.
- **Modify** `server/src/migration/hollihop-import.ts` — add the feed to `HolliHopData`, `fetchFromApi`, `loadFromDirectory`, `countSources`, `readStoredCounts`; add `importLeadStatusHistory(...)` and call it from `importAll`; carry `leadBranchById` from the leads loop.

---

## Task 1: Pure history mapper + unit tests

**Files:**
- Create: `server/src/migration/hollihop-history-mappers.ts`, `server/src/migration/hollihop-history-mappers.spec.ts`

**Interfaces (produces):**
- `appendMoscowOffset(raw: string | undefined): string | undefined` — append `+03:00` to a timezone-naive HolliHop datetime so `iso()` parses it as Moscow time. Pass through `undefined`, and leave strings that already carry an offset (`Z` or `±hh:mm`) untouched.
- `historyEntryFromRow(row: Record<string, unknown>): { leadIdRaw: string; afterIdRaw: string | null; afterName: string | null; dateTimeRaw: string } | null` — extract the four fields; return `null` (the caller skips) when `LeadId` OR `DateTime` is missing/blank (those two are mandatory; `AfterId`/`AfterName` may be absent).

- [ ] **Step 1: Write the failing tests**

```typescript
// server/src/migration/hollihop-history-mappers.spec.ts
import { appendMoscowOffset, historyEntryFromRow } from "./hollihop-history-mappers";

describe("appendMoscowOffset", () => {
  it("appends +03:00 to a timezone-naive datetime", () => {
    expect(appendMoscowOffset("2025-03-14T11:20:00")).toBe("2025-03-14T11:20:00+03:00");
    expect(appendMoscowOffset("2025-03-14 11:20:00")).toBe("2025-03-14 11:20:00+03:00");
  });
  it("leaves an already-offset / UTC datetime untouched", () => {
    expect(appendMoscowOffset("2025-03-14T11:20:00Z")).toBe("2025-03-14T11:20:00Z");
    expect(appendMoscowOffset("2025-03-14T11:20:00+05:00")).toBe("2025-03-14T11:20:00+05:00");
  });
  it("passes through undefined", () => {
    expect(appendMoscowOffset(undefined)).toBeUndefined();
  });
});

describe("historyEntryFromRow", () => {
  it("extracts the four fields", () => {
    expect(
      historyEntryFromRow({
        LeadId: 12345,
        DateTime: "2025-03-14T11:20:00",
        AfterId: 7,
        AfterName: "Пробное назначено",
      }),
    ).toEqual({
      leadIdRaw: "12345",
      afterIdRaw: "7",
      afterName: "Пробное назначено",
      dateTimeRaw: "2025-03-14T11:20:00",
    });
  });
  it("keeps the row when AfterId/AfterName are absent (timestamp still useful)", () => {
    expect(
      historyEntryFromRow({ LeadId: "9", DateTime: "2025-01-02T00:00:00" }),
    ).toEqual({
      leadIdRaw: "9",
      afterIdRaw: null,
      afterName: null,
      dateTimeRaw: "2025-01-02T00:00:00",
    });
  });
  it("returns null when LeadId is missing", () => {
    expect(historyEntryFromRow({ DateTime: "2025-01-02T00:00:00", AfterId: 3 })).toBeNull();
  });
  it("returns null when DateTime is missing", () => {
    expect(historyEntryFromRow({ LeadId: 5, AfterId: 3 })).toBeNull();
  });
});
```

- [ ] **Step 2: Run to verify failure** — `cd server && npx jest src/migration/hollihop-history-mappers.spec.ts` → "Cannot find module './hollihop-history-mappers'".

- [ ] **Step 3: Implement `hollihop-history-mappers.ts`**

```typescript
// server/src/migration/hollihop-history-mappers.ts
// Pure HolliHop GetHistoryModifyLeadStatus → normalized-row shaping. No DB / IO. Unit-tested.

function str(value: unknown): string | null {
  if (typeof value === "string") {
    const t = value.trim();
    return t.length ? t : null;
  }
  if (typeof value === "number" && Number.isFinite(value)) return String(value);
  return null;
}

// HolliHop datetimes are Moscow-local without an offset. Append +03:00 so a
// downstream `new Date(...)` parses the correct instant. Leave values that
// already carry a zone (`Z` or `±hh:mm`) untouched. Pass through undefined.
export function appendMoscowOffset(raw: string | undefined): string | undefined {
  if (raw === undefined) return undefined;
  if (/(?:Z|[+-]\d{2}:?\d{2})$/.test(raw)) return raw;
  return `${raw}+03:00`;
}

export interface HistoryEntry {
  leadIdRaw: string;
  afterIdRaw: string | null;
  afterName: string | null;
  dateTimeRaw: string;
}

export function historyEntryFromRow(
  row: Record<string, unknown>,
): HistoryEntry | null {
  const leadIdRaw = str(row.LeadId);
  const dateTimeRaw = str(row.DateTime);
  if (!leadIdRaw || !dateTimeRaw) return null;
  return {
    leadIdRaw,
    afterIdRaw: str(row.AfterId),
    afterName: str(row.AfterName),
    dateTimeRaw,
  };
}
```

- [ ] **Step 4: Run to verify pass** — `cd server && npx jest src/migration/hollihop-history-mappers.spec.ts` → all green.

- [ ] **Step 5: Commit**

```bash
git add server/src/migration/hollihop-history-mappers.ts server/src/migration/hollihop-history-mappers.spec.ts
git commit -m "feat(import): pure mapper for HolliHop lead status-history rows"
```

---

## Task 2: Verify the API root key + wire the feed into HolliHopData/fetch/load

**Files:**
- Modify: `server/src/migration/hollihop-import.ts`

- [ ] **Step 0: VERIFY the response root key (one real page).** With a valid auth key, fetch one page and inspect the top-level keys. Do NOT assume — confirm before wiring.

```bash
cd server
node -e '
  const base = (process.env.HOLLIHOP_BASE_URL || "https://sokol.t8s.ru/Api/V2/").replace(/\/?$/, "/");
  const u = new URL("GetHistoryModifyLeadStatus", base);
  u.searchParams.set("authkey", process.env.HOLLIHOP_AUTH_KEY);
  u.searchParams.set("skip", "0"); u.searchParams.set("take", "1");
  fetch(u).then(r => r.json()).then(d => {
    console.log("root keys:", Object.keys(d));
    const arrKey = Object.keys(d).find(k => Array.isArray(d[k]));
    console.log("array key:", arrKey, "sample row:", JSON.stringify(d[arrKey]?.[0], null, 2));
  });
'
```

Record the array key (expected `HistoryModifyLeadStatus`). If it differs, use the observed key as `ROOT_KEY` below. Also confirm the sample row really has `LeadId` / `DateTime` / `AfterId` / `AfterName` (note any casing differences and adjust the mapper's `row.*` accesses if needed).

- [ ] **Step 1: Add the feed to the `HolliHopData` interface.** In `hollihop-import.ts` (interface at lines 35-51), add the field after `comments`:

```typescript
interface HolliHopData {
  // …existing fields…
  comments: JsonRow[];
  leadStatusHistory: JsonRow[];
}
```

- [ ] **Step 2: Fetch it in `fetchFromApi`** (lines 1893-1951). Add to the destructured tuple + the `Promise.all` (use `fetchOptionalPaged` so a missing/forbidden endpoint degrades gracefully) and to the returned object. Use the root key confirmed in Step 0:

```typescript
  const [
    // …existing…
    comments,
    leadStatusHistory,
  ] = await Promise.all([
    // …existing…
    fetchOptionalPaged("GetComments", "Comments"),
    fetchOptionalPaged("GetHistoryModifyLeadStatus", "HistoryModifyLeadStatus"),
  ]);
  return {
    // …existing…
    comments,
    leadStatusHistory,
  };
```

- [ ] **Step 3: Load it from a local fixture dir in `loadFromDirectory`** (lines 1793-1831). Add after `comments`:

```typescript
    comments: readArrayFile(dir, ["comments.json"], "Comments"),
    leadStatusHistory: readArrayFile(
      dir,
      ["lead_status_history.json", "leadstatushistory.json"],
      "HistoryModifyLeadStatus",
    ),
```

- [ ] **Step 4: Count it in `countSources`** (lines 2073-2091). Add:

```typescript
    comments: data.comments.length,
    leadStatusHistory: data.leadStatusHistory.length,
```

`checksumSources` (lines 2093-2100) iterates `Object.entries(data)` so the new key is picked up automatically — no change needed there.

- [ ] **Step 5: Typecheck** — `cd server && npm run typecheck`. This will currently FAIL with "Property 'leadStatusHistory' is missing" at the `buildValidateOnlyReport` data-merge and any `HolliHopData` literal. Fix every `HolliHopData` construction site the compiler flags (the merge at `importAll` line 256-259 spreads `...sourceData` so it carries through; `buildValidateOnlyReport` line 1840-1843 likewise spreads `...value.data`). Confirm `npm run typecheck` → 0 errors. (No new feature behavior yet — just the plumbing compiles. Stored writes come in Task 3.)

- [ ] **Step 6: Commit**

```bash
git add server/src/migration/hollihop-import.ts
git commit -m "feat(import): fetch+load HolliHop GetHistoryModifyLeadStatus feed (plumbing)"
```

---

## Task 3: `importLeadStatusHistory` — upsert into `app.lead_status_history`

**Files:**
- Modify: `server/src/migration/hollihop-import.ts`

**Interfaces (consumes):** the Task-1 mapper (`historyEntryFromRow`, `appendMoscowOffset`); existing `planUpsert`, `recordSource`, `skip`, `warn`, `iso`, `deterministicUuid`, and the maps `leadById` + `statusById` built earlier in `importAll`.

- [ ] **Step 1: Import the mapper** at the top of `hollihop-import.ts` (next to the existing mapper import at line 11):

```typescript
import { appendMoscowOffset, historyEntryFromRow } from "./hollihop-history-mappers";
```

- [ ] **Step 2: Carry the lead's branch for `branch_id`.** In `importAll`, declare a map near the other maps (after `leadById` at line 268):

```typescript
  const leadBranchById = new Map<string, string>();
```

In the leads loop, after the lead's `branch_id` is computed for the `app.leads` upsert (line 782 already calls `primaryBranchId(branchIdsFromRow(lead, branchByOffice))`), capture it keyed by the **HolliHop external id** so the history importer can reuse it:

```typescript
    const leadBranchId = primaryBranchId(branchIdsFromRow(lead, branchByOffice));
    if (leadBranchId) leadBranchById.set(externalId, leadBranchId);
```

Then pass `leadBranchId` into the existing `app.leads` upsert `branch_id:` field instead of recomputing it (replace the inline `primaryBranchId(branchIdsFromRow(lead, branchByOffice))` on line 782 with `leadBranchId`). This is a pure refactor — same value, computed once.

- [ ] **Step 3: Call the new importer** from `importAll`, right after the `importTimeline(… "comments" …)` call (line 1054-1057):

```typescript
  await importLeadStatusHistory(ctx, data.leadStatusHistory, {
    leadById,
    statusById,
    leadBranchById,
  });
```

- [ ] **Step 4: Add an empty-source warning** alongside the existing source-missing warnings in `importAll` (near lines 283-303), so the operator sees when the endpoint returned nothing:

```typescript
  if (data.leadStatusHistory.length === 0) {
    warn(ctx, {
      code: "lead_status_history_source_missing",
      message:
        "No HolliHop GetHistoryModifyLeadStatus rows were available. Lead status-transition history was not imported.",
      source: "leadStatusHistory",
    });
  }
```

- [ ] **Step 5: Implement `importLeadStatusHistory`** — add the function next to `importTimeline` (after line 1253). Mirror `importTimeline`'s structure (loop, resolve, `recordSource`, `planUpsert`, `skip`/`warn`):

```typescript
async function importLeadStatusHistory(
  ctx: ImportContext,
  rows: JsonRow[],
  maps: {
    leadById: Map<string, string>;
    statusById: Map<string, string>;
    leadBranchById: Map<string, string>;
  },
) {
  for (const row of rows) {
    const entry = historyEntryFromRow(row);
    if (!entry) {
      skip(ctx, "leadStatusHistory");
      continue;
    }
    const leadId = maps.leadById.get(entry.leadIdRaw);
    if (!leadId) {
      // lead_id is NOT NULL with an FK — never invent it.
      skip(ctx, "leadStatusHistory");
      warn(ctx, {
        code: "lead_status_history_lead_unresolved",
        message:
          "HolliHop status-history row references a lead that is not in the imported set.",
        source: "leadStatusHistory",
        rowId: `${entry.leadIdRaw}:${entry.dateTimeRaw}`,
      });
      continue;
    }
    const changedAt = iso(appendMoscowOffset(entry.dateTimeRaw));
    if (!changedAt) {
      skip(ctx, "leadStatusHistory");
      warn(ctx, {
        code: "lead_status_history_datetime_invalid",
        message: "HolliHop status-history row had an unparseable DateTime.",
        source: "leadStatusHistory",
        rowId: `${entry.leadIdRaw}:${entry.dateTimeRaw}`,
      });
      continue;
    }
    const newStatusId = entry.afterIdRaw
      ? maps.statusById.get(entry.afterIdRaw) ?? null
      : null;
    if (entry.afterIdRaw && !newStatusId) {
      // Keep the row (the transition time is real) but flag the lost mapping.
      warn(ctx, {
        code: "lead_status_history_status_unresolved",
        message:
          "HolliHop status-history AfterId did not match an imported lead status; new_status_id left null (AfterName kept in source_snapshot).",
        source: "leadStatusHistory",
        rowId: `${entry.leadIdRaw}:${entry.afterIdRaw ?? ""}`,
      });
    }
    const externalId = `${entry.leadIdRaw}:${entry.afterIdRaw ?? ""}:${entry.dateTimeRaw}`;
    const id = deterministicUuid("hollihop-lead-status-history", externalId);
    await recordSource(ctx, {
      source: "leadStatusHistory",
      externalId,
      row,
      targetTable: "app.lead_status_history",
      targetId: id,
      mappedKeys: ["LeadId", "DateTime", "AfterId", "AfterName"],
    });
    await planUpsert(
      ctx,
      "leadStatusHistory",
      "app.lead_status_history",
      {
        id,
        lead_id: leadId,
        old_status_id: null,
        new_status_id: newStatusId,
        old_owner_id: null,
        new_owner_id: null,
        changed_by: null,
        changed_at: changedAt,
        reason_id: null,
        comment: null,
        branch_id: maps.leadBranchById.get(entry.leadIdRaw) ?? null,
        source_snapshot: entry.afterName,
      },
      ["id"],
    );
  }
}
```

- [ ] **Step 6: Add `lead_status_history` to `readStoredCounts`** (lines 1764-1790), so the report's `storedCounts` includes it:

```typescript
      (select count(*)::text from app.lead_comments where deleted_at is null) as lead_comments,
      (select count(*)::text from app.lead_status_history) as lead_status_history,
```

(`app.lead_status_history` has no `deleted_at` column — a plain `count(*)` is correct.)

- [ ] **Step 7: Typecheck + run the suite** — `cd server && npm run typecheck && npm test` → 0 errors / green. The new mapper spec passes; nothing else regresses (the importer's existing tests are mapper-level and untouched).

- [ ] **Step 8: Commit**

```bash
git add server/src/migration/hollihop-import.ts
git commit -m "feat(import): upsert HolliHop lead status-history into app.lead_status_history (idempotent, dry-run/apply)"
```

---

## Task 4: Docker integration validation (fixture → DB, idempotent)

**Files:** none changed — runtime validation only (NOT prod).

- [ ] **Step 1: Spin up a throwaway Postgres 16 + run the full migration chain.**

```bash
docker run --rm -d --name mmcrm-hist-pg -e POSTGRES_PASSWORD=test -e POSTGRES_DB=mmcrm_test -p 55444:5432 postgres:16
# wait for readiness
until docker exec mmcrm-hist-pg pg_isready -U postgres -d mmcrm_test >/dev/null 2>&1; do :; done
docker exec mmcrm-hist-pg psql -U postgres -d mmcrm_test -c "create role magiccrm_app" || true
URL='postgres://postgres:test@localhost:55444/mmcrm_test'
cd server && MIGRATION_DATABASE_URL="$URL" DATABASE_URL="$URL" npm run db:migrate   # applies the full chain incl. 0028
```

- [ ] **Step 2: Build a minimal local fixture dir** that exercises (a) a resolvable lead+status, (b) an unresolvable `AfterId` (kept, status null), (c) an unresolvable `LeadId` (skipped). The importer's local-mode (`HOLLIHOP_IMPORT_SOURCE_DIR`) reads `leads.json`, `leadstatuses.json`, and the new `lead_status_history.json`; everything else can be empty.

```bash
FX="$(mktemp -d)"
cat > "$FX/offices.json"      <<'JSON'
[{"Id":"100","Name":"Сокол","Address":"ул. Тестовая 1"}]
JSON
cat > "$FX/leadstatuses.json" <<'JSON'
[{"Id":"7","Name":"Пробное назначено","Type":"trial"},
 {"Id":"9","Name":"Успешно завершён","Type":"success"}]
JSON
cat > "$FX/leads.json"        <<'JSON'
[{"Id":"12345","FirstName":"Иван","LastName":"Лидов","StatusId":"9",
  "OfficesAndCompanies":[{"Id":"100"}]}]
JSON
cat > "$FX/lead_status_history.json" <<'JSON'
[
  {"LeadId":12345,"DateTime":"2025-03-14T11:20:00","AfterId":7,"AfterName":"Пробное назначено"},
  {"LeadId":12345,"DateTime":"2025-04-01T09:00:00","AfterId":9,"AfterName":"Успешно завершён"},
  {"LeadId":12345,"DateTime":"2025-05-01T09:00:00","AfterId":777,"AfterName":"Несуществующий статус"},
  {"LeadId":99999,"DateTime":"2025-05-02T09:00:00","AfterId":7,"AfterName":"Пробное назначено"}
]
JSON
```

- [ ] **Step 3: Run the importer in apply mode (local source).**

```bash
cd server && \
  HOLLIHOP_IMPORT_SOURCE_DIR="$FX" HOLLIHOP_IMPORT_MODE=apply \
  MIGRATION_DATABASE_URL="$URL" DATABASE_URL="$URL" \
  npm run hollihop:import -- --apply
```

- [ ] **Step 4: Assert the rows.** Expected: lead `12345` resolves to `deterministicUuid("hollihop-lead","12345")`; statuses `7`/`9` resolve (name-reconciled); `AfterId 777` keeps the row with `new_status_id IS NULL` + `source_snapshot='Несуществующий статус'`; `LeadId 99999` is **skipped** (no FK lead). So **3** history rows total.

```bash
docker exec mmcrm-hist-pg psql -U postgres -d mmcrm_test -c \
  "select h.changed_at, s.name as new_status, h.new_status_id is null as status_null, h.source_snapshot
     from app.lead_status_history h
     left join app.lead_statuses s on s.id = h.new_status_id
    order by h.changed_at;"
# -> 2025-03-14 ... | Пробное назначено      | f | Пробное назначено
#    2025-04-01 ... | Успешно завершён       | f | Успешно завершён
#    2025-05-01 ... | (null)                 | t | Несуществующий статус

docker exec mmcrm-hist-pg psql -U postgres -d mmcrm_test -c "select count(*) from app.lead_status_history;"  # 3
# changed_at must reflect Moscow time: 11:20 MSK == 08:20 UTC.
docker exec mmcrm-hist-pg psql -U postgres -d mmcrm_test -c \
  "select changed_at at time zone 'UTC' from app.lead_status_history order by changed_at limit 1;"  # 2025-03-14 08:20:00
# branch_id carried from the lead's office:
docker exec mmcrm-hist-pg psql -U postgres -d mmcrm_test -c \
  "select count(*) from app.lead_status_history where branch_id is not null;"  # 3
```

- [ ] **Step 5: Idempotency — re-run apply, counts unchanged.**

```bash
cd server && HOLLIHOP_IMPORT_SOURCE_DIR="$FX" HOLLIHOP_IMPORT_MODE=apply \
  MIGRATION_DATABASE_URL="$URL" DATABASE_URL="$URL" npm run hollihop:import -- --apply
docker exec mmcrm-hist-pg psql -U postgres -d mmcrm_test -c "select count(*) from app.lead_status_history;"  # still 3
```

- [ ] **Step 6: Tear down.**

```bash
docker stop mmcrm-hist-pg; rm -rf "$FX"
```

Expected overall: 4 source rows → 3 stored (1 skipped: unresolved lead), 1 warning for the unresolved `AfterId 777` (status kept null), idempotent re-run holds at 3. If the importer prints `storedCounts.lead_status_history`, it should read `3`.

- [ ] **Step 7: Commit (if any fixture/doc artifact is kept; otherwise nothing to commit).** No source change in this task.

---

## Self-Review

- **Real data, faithful mapping:** `LeadId → lead_id`, `AfterId → new_status_id` (via the same reconciled `statusById` map the leads use), `DateTime → changed_at` (Moscow offset applied), `AfterName → source_snapshot`. `old_status_id`/owners/`reason_id`/`changed_by` stay `null` because the endpoint does not provide them — nothing is invented. ✅
- **Reuses the importer's spine:** `fetchOptionalPaged` (graceful degradation), `readArrayFile`/`loadFromDirectory`, `planUpsert` (dry-run/apply), `recordSource` (provenance), `deterministicUuid`, `iso`, `skip`/`warn` — same patterns as `importTimeline`/`importTasks`. ✅
- **Idempotent:** id keyed on raw `LeadId:AfterId:DateTime`; `on conflict (id)` upsert; validated by the Docker re-run holding counts at 3. ✅
- **Honest skips:** unresolved `lead_id` (FK-protected) is counted + warned, never invented; unparseable `DateTime` is skipped; unresolved `AfterId` keeps the row with `new_status_id = null` and the name in `source_snapshot` so analytics still see the transition timestamp. ✅
- **Root key verified, not assumed:** Task 2 Step 0 confirms the `GetHistoryModifyLeadStatus` array key against a real page before wiring (expected `HistoryModifyLeadStatus`). ✅
- **Single-file risk noted:** all importer changes are in `hollihop-import.ts`; the pure shaping is isolated in `hollihop-history-mappers.ts`. Concurrent importer streams on `hollihop-import.ts` must be serialized. ✅
- **Scope discipline:** no migration changes (0028 already deployed), no new dependency, no Flutter changes, no prod run. ✅

## Operator run (gated, after merge)

After merge + image rebuild on the VPS: fresh `pg_dump`, then `docker compose exec -e HOLLIHOP_AUTH_KEY=… api node dist/migration/hollihop-import.js` in `dry_run` first (review `plannedCounts.leadStatusHistory` + the warnings for unresolved leads/statuses), then re-run with `--apply`. The import is idempotent, so a later full re-pull (e.g. after the leads backfill completes) safely refreshes the history without duplicating rows.
