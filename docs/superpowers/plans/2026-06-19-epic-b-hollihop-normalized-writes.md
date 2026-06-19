# Epic B · HolliHop reimport — normalized writes (disciplines, branch, contacts) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the HolliHop importer populate the normalized Epic-A tables/columns — `app.disciplines` + `app.student_disciplines` (with a primary) + `app.branch_disciplines`, `students.branch_id` / `leads.branch_id`, and `app.contacts` — so the «Ученики» board (Epic C) and branch/discipline analytics (Epic F) have real data (today 0/1955 students have a discipline or branch).

**Architecture:** The risky parsing logic is extracted into PURE, unit-tested functions in a new `hollihop-mappers.ts`; the importer (`hollihop-import.ts`) calls them in its student/lead apply paths and writes the rows via the existing `planUpsert()` wrapper (dry-run-safe) + `deterministicUuid()` (idempotent ids). Validation is an ephemeral-Docker apply against a tiny synthetic fixture + SQL assertions. The real production re-import (full archive / live API, with `pg_dump`) is a gated ops step (B7), not run here.

**Tech Stack:** NestJS/TypeScript standalone migration script, PostgreSQL, Jest.

**Linear:** KVA-179 (Epic B). Spec §4B. Depends on Epic A migrations `0026` (disciplines/branch_disciplines/student_disciplines), `0027` (branch_id), `0029` (contacts) — all in the chain.

## Global Constraints

- New file `server/src/migration/hollihop-mappers.ts` holds the PURE functions; it imports nothing from the DB. Unit-tested in `hollihop-mappers.spec.ts`.
- All DB writes go through the importer's existing `planUpsert(ctx, name, table, data, conflictColumns)` (so dry-run stays a no-op) and use `deterministicUuid(namespace, key)` for stable, idempotent ids.
- Idempotent id namespaces: discipline = `deterministicUuid("hollihop-discipline", lowerTrimName)`; student_discipline = `deterministicUuid("hollihop-student-discipline", studentId + ":" + disciplineId)`; branch_discipline = `deterministicUuid("hollihop-branch-discipline", branchId + ":" + disciplineId)`; contact = `deterministicUuid("hollihop-contact", entityType + ":" + entityId + ":" + phoneNormalized + ":" + name)`.
- `students.branch_id` / `leads.branch_id` = the FIRST element of `branchIdsFromRow(...)` (or null). Keep the existing `custom_data.branchIds` write too (dual-write — A4 reads still fall back to jsonb).
- Discipline names normalized by `lower(btrim(name))` for the dedup id; the displayed `name` keeps original casing of the first occurrence. `is_primary` = the FIRST discipline in the student's list.
- Contact phone normalized via `normalizePhoneRu(...).canonical` (already imported in the importer from A1). Contacts with no normalizable phone AND no name are skipped.
- This task does NOT run against production and does NOT hit the live HolliHop API. Validation is Docker-only with a synthetic fixture. NEVER use `server/.env`/`.migration.env` or a remote DB.
- Out of scope (follow-ups on this epic): B1 structured `activity_log` (no such table yet), B2 teacher-resolution fix (`schedule_teacher_unresolved`), B6 normalized inquiry type/date columns. The real prod re-import (B7) is gated on the owner (`pg_dump` + live key/archive).
- Run from `server/`: tests `npm test`; types `npm run typecheck`; importer `npm run hollihop:import`.

---

## File Structure

- **Create** `server/src/migration/hollihop-mappers.ts` — `disciplineEntries`, `contactEntries`, `primaryBranchId` (pure).
- **Create** `server/src/migration/hollihop-mappers.spec.ts` — unit tests.
- **Modify** `server/src/migration/hollihop-import.ts` — call the mappers in the student loop (~556-663) and lead loop (~665-764); write disciplines/student_disciplines/branch_disciplines, branch_id, contacts via `planUpsert`.

---

## Task 1: Pure mapping helpers + unit tests

**Files:**
- Create: `server/src/migration/hollihop-mappers.ts`
- Test: `server/src/migration/hollihop-mappers.spec.ts`

**Interfaces:**
- Produces:
  - `disciplineEntries(raw: unknown): { name: string; isPrimary: boolean }[]` — distinct non-empty discipline names (by lower/trim), first = primary, order preserved.
  - `contactEntries(rawAgents: unknown, normalize: (p: string | null | undefined) => string | null): { phoneNormalized: string | null; name: string | null; role: string | null }[]` — one per agent that has a normalizable phone OR a name.
  - `primaryBranchId(branchIds: string[] | null | undefined): string | null` — first or null.

- [ ] **Step 1: Write the failing tests**

```typescript
// server/src/migration/hollihop-mappers.spec.ts
import { disciplineEntries, contactEntries, primaryBranchId } from "./hollihop-mappers";

describe("disciplineEntries", () => {
  it("returns distinct names, first is primary, order preserved", () => {
    expect(
      disciplineEntries([{ Discipline: "Вокал" }, { Discipline: "Гитара" }, { Discipline: "вокал" }]),
    ).toEqual([
      { name: "Вокал", isPrimary: true },
      { name: "Гитара", isPrimary: false },
    ]);
  });
  it("accepts plain strings and skips empties", () => {
    expect(disciplineEntries(["Барабаны", "", "  "])).toEqual([{ name: "Барабаны", isPrimary: true }]);
  });
  it("returns [] for null/garbage", () => {
    expect(disciplineEntries(null)).toEqual([]);
    expect(disciplineEntries(42)).toEqual([]);
  });
});

describe("contactEntries", () => {
  const norm = (p: string | null | undefined) =>
    p && p.replace(/\D/g, "").length >= 10 ? `+7${p.replace(/\D/g, "").slice(-10)}` : null;
  it("maps agents with a normalizable phone or a name", () => {
    expect(
      contactEntries(
        [
          { Mobile: "8 909 123 45 67", FirstName: "Иван", LastName: "Иванов", Type: "parent" },
          { FirstName: "Без", LastName: "Телефона" },
          { Mobile: "junk" },
        ],
        norm,
      ),
    ).toEqual([
      { phoneNormalized: "+79091234567", name: "Иван Иванов", role: "parent" },
      { phoneNormalized: null, name: "Без Телефона", role: null },
    ]);
  });
  it("returns [] for null/garbage", () => {
    expect(contactEntries(null, norm)).toEqual([]);
  });
});

describe("primaryBranchId", () => {
  it("returns the first id or null", () => {
    expect(primaryBranchId(["b1", "b2"])).toBe("b1");
    expect(primaryBranchId([])).toBeNull();
    expect(primaryBranchId(null)).toBeNull();
  });
});
```

- [ ] **Step 2: Run to verify failure**

Run: `cd server && npx jest src/migration/hollihop-mappers.spec.ts`
Expected: FAIL — `Cannot find module './hollihop-mappers'`.

- [ ] **Step 3: Implement the mappers**

```typescript
// server/src/migration/hollihop-mappers.ts
// Pure HolliHop → normalized-row mappers. No DB / IO. Unit-tested.

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}
function str(value: unknown): string | null {
  if (typeof value === "string") {
    const t = value.trim();
    return t.length ? t : null;
  }
  return null;
}

// Distinct discipline names (dedup by lower/trim), order preserved, first = primary.
export function disciplineEntries(raw: unknown): { name: string; isPrimary: boolean }[] {
  const seen = new Set<string>();
  const out: { name: string; isPrimary: boolean }[] = [];
  for (const item of asArray(raw)) {
    const name =
      typeof item === "string"
        ? str(item)
        : str((item as Record<string, unknown>)?.["Discipline"]) ??
          str((item as Record<string, unknown>)?.["Name"]);
    if (!name) continue;
    const key = name.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({ name, isPrimary: out.length === 0 });
  }
  return out;
}

// Contact persons from HolliHop Agents[]: keep any with a normalizable phone OR a name.
export function contactEntries(
  rawAgents: unknown,
  normalize: (p: string | null | undefined) => string | null,
): { phoneNormalized: string | null; name: string | null; role: string | null }[] {
  const out: { phoneNormalized: string | null; name: string | null; role: string | null }[] = [];
  for (const agent of asArray(rawAgents)) {
    const a = (agent ?? {}) as Record<string, unknown>;
    const phone = normalize(str(a["Mobile"]) ?? str(a["Phone"]));
    const name =
      [str(a["FirstName"]), str(a["LastName"])].filter(Boolean).join(" ").trim() ||
      str(a["Name"]) ||
      null;
    if (!phone && !name) continue;
    out.push({ phoneNormalized: phone, name: name || null, role: str(a["Type"]) ?? str(a["Role"]) });
  }
  return out;
}

export function primaryBranchId(branchIds: string[] | null | undefined): string | null {
  return Array.isArray(branchIds) && branchIds.length ? branchIds[0] : null;
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd server && npx jest src/migration/hollihop-mappers.spec.ts`
Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
git add server/src/migration/hollihop-mappers.ts server/src/migration/hollihop-mappers.spec.ts
git commit -m "feat(import): pure HolliHop mappers for disciplines, contacts, primary branch (KVA-179)"
```

---

## Task 2: Wire normalized writes into the importer + validate

**Files:**
- Modify: `server/src/migration/hollihop-import.ts`

**Interfaces:**
- Consumes: `disciplineEntries`, `contactEntries`, `primaryBranchId` (Task 1); the importer's existing `planUpsert`, `deterministicUuid`, `branchIdsFromRow`, `normalizePhoneRu`.

- [ ] **Step 1: Import the mappers**

At the top of `hollihop-import.ts`, add:
```typescript
import { disciplineEntries, contactEntries, primaryBranchId } from "./hollihop-mappers";
```

- [ ] **Step 2: In the STUDENT loop (~556-663), after the `app.students` upsert, write normalized rows**

Compute once (the student loop already has `studentId`, `student`, and the `branchIds` it puts in custom_data):
```typescript
      const branchIds = branchIdsFromRow(student, branchByOffice);
      const studentBranchId = primaryBranchId(branchIds);
```
Add `branch_id: studentBranchId,` to the `app.students` `planUpsert` data object (alongside the existing `custom_data`). Then AFTER that upsert:

```typescript
      // Disciplines → app.disciplines + app.student_disciplines (is_primary).
      for (const d of disciplineEntries(student.Disciplines)) {
        const disciplineId = deterministicUuid("hollihop-discipline", d.name.toLowerCase());
        await planUpsert(ctx, "disciplines", "app.disciplines", { id: disciplineId, name: d.name }, ["id"]);
        await planUpsert(
          ctx,
          "student_disciplines",
          "app.student_disciplines",
          {
            id: deterministicUuid("hollihop-student-discipline", `${studentId}:${disciplineId}`),
            student_id: studentId,
            discipline_id: disciplineId,
            is_primary: d.isPrimary,
          },
          ["student_id", "discipline_id"],
        );
        // Make the discipline a column of the student's branch board.
        if (studentBranchId) {
          await planUpsert(
            ctx,
            "branch_disciplines",
            "app.branch_disciplines",
            {
              id: deterministicUuid("hollihop-branch-discipline", `${studentBranchId}:${disciplineId}`),
              branch_id: studentBranchId,
              discipline_id: disciplineId,
            },
            ["branch_id", "discipline_id"],
          );
        }
      }

      // Contacts (parents/agents) → app.contacts.
      for (const c of contactEntries(student.Agents, (p) => normalizePhoneRu(p).canonical)) {
        await planUpsert(
          ctx,
          "contacts",
          "app.contacts",
          {
            id: deterministicUuid("hollihop-contact", `student:${studentId}:${c.phoneNormalized ?? ""}:${c.name ?? ""}`),
            entity_type: "student",
            entity_id: studentId,
            phone_normalized: c.phoneNormalized,
            name: c.name,
            role: c.role,
          },
          ["id"],
        );
      }
```

> If `normalizePhoneRu` is not yet imported in this file, add `import { normalizePhoneRu } from "../crm/phone.util";` (A1 already added it; confirm). The `student_disciplines`/`branch_disciplines` conflict keys (`["student_id","discipline_id"]` / `["branch_id","discipline_id"]`) match the unique constraints from migration 0026.

- [ ] **Step 3: In the LEAD loop (~665-764), set `leads.branch_id` and lead contacts**

Add `branch_id: primaryBranchId(branchIdsFromRow(lead, branchByOffice)),` to the `app.leads` `planUpsert` data. Then after that upsert, write lead contacts:
```typescript
      for (const c of contactEntries(lead.Agents, (p) => normalizePhoneRu(p).canonical)) {
        await planUpsert(
          ctx,
          "contacts",
          "app.contacts",
          {
            id: deterministicUuid("hollihop-contact", `lead:${leadId}:${c.phoneNormalized ?? ""}:${c.name ?? ""}`),
            entity_type: "lead",
            entity_id: leadId,
            phone_normalized: c.phoneNormalized,
            name: c.name,
            role: c.role,
          },
          ["id"],
        );
      }
```
(Leads keep `discipline` as a single string in custom_data — no `student_disciplines` for leads. The lead's discipline normalization is not in scope here.)

- [ ] **Step 4: Typecheck + the full suite**

Run: `cd server && npm run typecheck && npm test`
Expected: typecheck 0; the mapper unit tests pass; full suite green (no existing test touches the importer, so nothing regresses).

- [ ] **Step 5: Integration-validate on an ephemeral Docker Postgres with a tiny synthetic fixture (NOT prod)**

Create a minimal fixture dir and run the importer in APPLY mode against a throwaway DB; assert the new rows appear.

```bash
docker run --rm -d --name mmcrm-b-pg -e POSTGRES_PASSWORD=test -e POSTGRES_DB=mmcrm_test -p 55440:5432 postgres:16
# wait ready; create role:
docker exec mmcrm-b-pg psql -U postgres -d mmcrm_test -c "create role magiccrm_app" || true
URL='postgres://postgres:test@localhost:55440/mmcrm_test'
cd server && MIGRATION_DATABASE_URL="$URL" DATABASE_URL="$URL" npm run db:migrate   # full chain incl 0026/0027/0029

# Minimal fixture (one office, one student with 2 disciplines + 1 agent):
FX="$(mktemp -d)"
cat > "$FX/offices.json"        <<'JSON'
{ "Offices": [ { "Id": "off-1", "Name": "Сокол", "Address": "ул. Сокол 1" } ] }
JSON
cat > "$FX/students.json"       <<'JSON'
{ "Students": [ { "Id": "stu-1", "ClientId": "cli-1", "FirstName": "Петя", "LastName": "Иванов",
  "Status": "Учится", "Disciplines": [ {"Discipline":"Вокал"}, {"Discipline":"Гитара"} ],
  "OfficesAndCompanies": [ { "Id": "off-1", "Name": "Сокол" } ],
  "Agents": [ { "FirstName":"Иван","LastName":"Иванов","Mobile":"8 909 123 45 67","Type":"parent" } ] } ] }
JSON
printf '{ "Leads": [] }'           > "$FX/leads.json"
printf '{ "EdUnits": [] }'         > "$FX/edunits.json"
printf '{ "EdUnitStudents": [] }'  > "$FX/edunitstudents.json"
printf '{ "Payments": [] }'        > "$FX/payments.json"

cd server && HOLLIHOP_IMPORT_SOURCE_DIR="$FX" HOLLIHOP_IMPORT_MODE=apply MIGRATION_DATABASE_URL="$URL" DATABASE_URL="$URL" npm run hollihop:import
# Assert the normalized rows landed:
docker exec mmcrm-b-pg psql -U postgres -d mmcrm_test -c "select name from app.disciplines order by name;"                                   # Вокал, Гитара
docker exec mmcrm-b-pg psql -U postgres -d mmcrm_test -c "select is_primary, (select name from app.disciplines d where d.id=sd.discipline_id) from app.student_disciplines sd order by is_primary desc;"  # true→Вокал, false→Гитара
docker exec mmcrm-b-pg psql -U postgres -d mmcrm_test -c "select count(*) from app.branch_disciplines;"                                       # 2
docker exec mmcrm-b-pg psql -U postgres -d mmcrm_test -c "select branch_id is not null as has_branch from app.students;"                      # t
docker exec mmcrm-b-pg psql -U postgres -d mmcrm_test -c "select phone_normalized, name, role from app.contacts;"                             # +79091234567, Иван Иванов, parent
# Idempotency: re-run apply, counts unchanged.
cd server && HOLLIHOP_IMPORT_SOURCE_DIR="$FX" HOLLIHOP_IMPORT_MODE=apply MIGRATION_DATABASE_URL="$URL" DATABASE_URL="$URL" npm run hollihop:import
docker exec mmcrm-b-pg psql -U postgres -d mmcrm_test -c "select count(*) from app.student_disciplines;"                                      # still 2
docker stop mmcrm-b-pg; rm -rf "$FX"
```
Expected: disciplines Вокал+Гитара; student_disciplines with is_primary=true on Вокал; 2 branch_disciplines; student.branch_id non-null; one contact `+79091234567 / Иван Иванов / parent`; re-run keeps counts at 2 (idempotent via deterministic ids). If the importer crashes on the minimal fixture (a required file/field missing), add the missing file/field and report it — do NOT change mapping logic to paper over a crash.

- [ ] **Step 6: Commit**

```bash
git add server/src/migration/hollihop-import.ts
git commit -m "feat(import): write disciplines/student_disciplines/branch_disciplines, branch_id, contacts (KVA-179)"
```

---

## Self-Review

- **Spec coverage (§4B):** B3 disciplines→`student_disciplines`(is_primary)+`disciplines`+`branch_disciplines` ✅; B4 `students.branch_id`/`leads.branch_id` ✅; B5 contacts→`app.contacts` ✅. B1 (activity_log), B2 (teacher resolution), B6 (inquiry columns) explicitly deferred. B7 (prod re-import) gated.
- **Placeholder scan:** none — full TS/tests/SQL with exact commands.
- **Idempotency:** deterministic ids + `planUpsert` conflict keys make re-import safe (validated by the re-run assertion).
- **Dry-run safety:** all writes go through `planUpsert` (no-op in dry-run); the parsing helpers are pure and unit-tested.
- **Type consistency:** mapper function names + shapes identical across `hollihop-mappers.ts`, its spec, and the importer call sites; conflict keys match the 0026 unique constraints.

## Dependency note

Epic B unblocks the «Ученики» board (Epic C4 — branch_disciplines columns + student primary discipline) and branch/discipline analytics (Epic F). The real production re-import (full archive or live API, `pg_dump` first) is the owner-gated B7 step — it should run AFTER the Epic A migrations (0025–0030) are applied to prod, and the importer now also fills `branch_id` (resolving the A4 follow-up). Follow-ups on this epic: B1 `activity_log`, B2 `schedule_teacher_unresolved`, B6 normalized inquiry type/date.
