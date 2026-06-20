# HolliHop manual-export importer (tasks + client comments) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Import the data HolliHop's API does NOT expose — **employee tasks** (507) and **client comments/notes** (student «Описание», lead «Комментарий») — from the operator's manual XLSX/CSV exports (already converted to JSON), linking each to the right client card **by normalized phone**.

**Architecture:** A standalone script `server/src/migration/import-hollihop-exports.ts` reads three JSON files (`tasks.json`, `students.json`, `leads.json`) from `HOLLIHOP_EXPORTS_DIR`. For each row it normalizes the phone (`normalizePhoneRu`), matches it to an existing **student** (`app.students` → `app.profiles.phone_normalized`) or **lead** (`app.leads.phone_normalized`), and upserts: tasks → `app.tasks` (polymorphic `entity_type`/`entity_id`), student notes → `app.entity_comments` (`entity_type='student'`), lead comments → `app.lead_comments`. Idempotent via `deterministicUuid`. Dry-run vs apply (like the main importer). The risky parsing/matching shaping lives in a PURE, unit-tested mapper module.

**Tech Stack:** NestJS/TypeScript standalone script (pg Pool), PostgreSQL, Jest. No new dependency (JSON is pre-converted from XLSX/CSV by the operator-side python step).

**Linear:** new follow-up under Epic B / KVA-179 (manual-export ingest). Depends on migration 0025 (`phone_normalized`) + 0002/0017 (tasks/comments/entity enum) — all applied on prod.

## Global Constraints

- Input JSON rows use the EXPORT's Russian column names as keys (faithful conversion). Relevant keys:
  - **tasks.json** (507 rows): `Дата выполнения`, `Описание`, `Клиент`, `Моб. телефон`, `Телефон`, `Email`, `Конт. лица`, `Ответственный`.
  - **students.json** (1032 rows): `ИД`, `ИД клиента`, `Моб. телефон` (col 17), `Описание` (col 32 = the NOTE), `Пользовательские поля` (31), `Фамилия`/`Имя`, `Филиалы`.
  - **leads.json** (876 rows): `ID`, `Моб. телефон` (col 11), `Телефон` (12), `Комментарий` (col 22 = the COMMENT), `Пользовательские поля` (21), `ФИО`.
- Phone match canonical = `normalizePhoneRu(raw).canonical` (`+7XXXXXXXXXX`).
  - Student match: `select s.id from app.students s join app.profiles p on p.id = s.profile_id and p.deleted_at is null where p.phone_normalized = $1 and s.deleted_at is null limit 1`.
  - Lead match: `select l.id from app.leads l where l.phone_normalized = $1 and l.deleted_at is null limit 1`.
  - A task/note prefers a **student** match; if none, a **lead** match; if neither, it is UNMATCHED (counted + skipped, not invented).
- `app.tasks`: `entity_type` (enum `student`/`lead`/...), `entity_id`, `title` NOT NULL, `description`, `status` (default `'open'`), `due_at`, `assigned_to` (user uuid|null), `created_by` (user uuid|null — use null for imported). title = `taskTitle(description)` (first line, ≤120 chars; fallback `'Задача (HolliHop)'`). status = `'open'`. due_at = `parseRuDate(Дата выполнения)`.
- `app.entity_comments`: `entity_type='student'`, `entity_id`, `author_id=null`, `body` NOT NULL (the «Описание» note).
- `app.lead_comments`: `lead_id`, `author_id=null`, `body` NOT NULL (the «Комментарий»; append `Пользовательские поля` as a second line if present).
- `assigned_to`: match `Ответственный` (a `"Фамилия Имя Отчество"` string, or `"[Для всех]"`) → a user. `"[Для всех]"`/empty → null. Else `select u.id from app.users u join app.profiles p on p.user_id = u.id and p.deleted_at is null where lower(btrim(concat_ws(' ', p.last_name, p.first_name))) = lower(btrim($1)) or lower(coalesce(u.full_name,'')) = lower(btrim($1)) and u.deleted_at is null limit 1` (best-effort; unmatched → null, not an error).
- Idempotent ids: task = `deterministicUuid("hollihop-export-task", phoneCanonical + "|" + description + "|" + dueRaw)`; student note = `deterministicUuid("hollihop-export-note", "student:" + studentId + "|" + body)`; lead comment = `deterministicUuid("hollihop-export-comment", "lead:" + leadId + "|" + body)`. Upsert `on conflict (id) do nothing` (re-run safe; comments/tasks are immutable once imported).
- Mode: `HOLLIHOP_EXPORT_IMPORT_MODE` = `dry_run` (default — compute the plan + match/unmatched counts, NO writes) or `apply`. A `planUpsert`-style wrapper writes only in apply.
- Skip rows with no normalizable phone AND produce an UNMATCHED count; skip empty notes/comments (don't create blank comments).
- The script prints a JSON report: per category `{ total, matchedStudent, matchedLead, unmatched, written }`.
- Connection: `new Pool({ connectionString: process.env.MIGRATION_DATABASE_URL ?? process.env.DATABASE_URL })`. Run from `server/`; tests `npm test`; types `npm run typecheck`. Prod run is operator-gated (Docker-validate only here).

---

## File Structure

- **Create** `server/src/migration/hollihop-export-mappers.ts` — pure parse/shape/match-key helpers.
- **Create** `server/src/migration/hollihop-export-mappers.spec.ts` — unit tests.
- **Create** `server/src/migration/import-hollihop-exports.ts` — the standalone import script.

---

## Task 1: Pure export mappers + unit tests

**Files:**
- Create: `server/src/migration/hollihop-export-mappers.ts`, `hollihop-export-mappers.spec.ts`

**Interfaces (produces):**
- `parseRuDate(raw: unknown): string | null` — `"18.01.2027"` / `"19.06.2026 17:18"` → ISO; null if unparseable.
- `taskTitle(description: string): string` — first non-empty line trimmed to ≤120 chars; `'Задача (HolliHop)'` if empty.
- `taskFromRow(row): { phoneRaw, clientName, description, dueRaw, responsible } | null` — null if no description AND no client.
- `studentNoteFromRow(row): { phoneRaw, name, note } | null` — null if «Описание» empty.
- `leadCommentFromRow(row): { phoneRaw, name, body } | null` — null if «Комментарий» empty; body = comment, plus `\n` + «Пользовательские поля» when present.
- `cleanResponsible(raw): string | null` — null for `''`/`'[Для всех]'`/`'[Для всех]'`-like; else trimmed.

- [ ] **Step 1: Write the failing tests**

```typescript
// server/src/migration/hollihop-export-mappers.spec.ts
import {
  parseRuDate, taskTitle, taskFromRow, studentNoteFromRow, leadCommentFromRow, cleanResponsible,
} from "./hollihop-export-mappers";

describe("parseRuDate", () => {
  it("parses dd.mm.yyyy and dd.mm.yyyy hh:mm", () => {
    expect(parseRuDate("18.01.2027")).toBe("2027-01-18T00:00:00.000Z");
    expect(parseRuDate("19.06.2026 17:18")).toBe("2026-06-19T17:18:00.000Z");
  });
  it("returns null for junk/empty", () => {
    expect(parseRuDate("")).toBeNull();
    expect(parseRuDate("нет")).toBeNull();
    expect(parseRuDate(null)).toBeNull();
  });
});

describe("taskTitle", () => {
  it("takes the first line trimmed to 120 chars", () => {
    expect(taskTitle("Звонок\nЕсли на Спортивной есть препод")).toBe("Звонок");
    expect(taskTitle("")).toBe("Задача (HolliHop)");
    expect(taskTitle("x".repeat(200)).length).toBe(120);
  });
});

describe("taskFromRow", () => {
  it("extracts the task fields", () => {
    expect(
      taskFromRow({
        "Дата выполнения": "18.01.2027",
        "Описание": "летом 26 не готова вернуться",
        "Клиент": "Кивелиди Мария",
        "Моб. телефон": "+79161037743",
        "Ответственный": "[Для всех]",
      }),
    ).toEqual({
      phoneRaw: "+79161037743",
      clientName: "Кивелиди Мария",
      description: "летом 26 не готова вернуться",
      dueRaw: "18.01.2027",
      responsible: "[Для всех]",
    });
  });
  it("returns null when there is neither description nor client", () => {
    expect(taskFromRow({ "Моб. телефон": "+79161037743" })).toBeNull();
  });
});

describe("studentNoteFromRow", () => {
  it("extracts the note from «Описание»", () => {
    expect(
      studentNoteFromRow({ "Моб. телефон": "89991234567", "Имя": "Петя", "Описание": "интерес пропал" }),
    ).toEqual({ phoneRaw: "89991234567", name: "Петя", note: "интерес пропал" });
  });
  it("returns null when «Описание» empty", () => {
    expect(studentNoteFromRow({ "Моб. телефон": "8999", "Описание": "" })).toBeNull();
  });
});

describe("leadCommentFromRow", () => {
  it("combines «Комментарий» + «Пользовательские поля»", () => {
    expect(
      leadCommentFromRow({ "Моб. телефон": "8999", "ФИО": "Иван", "Комментарий": "перезвонить", "Пользовательские поля": "тег: VIP" }),
    ).toEqual({ phoneRaw: "8999", name: "Иван", body: "перезвонить\nтег: VIP" });
  });
  it("returns null when «Комментарий» empty", () => {
    expect(leadCommentFromRow({ "Комментарий": "" })).toBeNull();
  });
});

describe("cleanResponsible", () => {
  it("nulls placeholders, trims names", () => {
    expect(cleanResponsible("[Для всех]")).toBeNull();
    expect(cleanResponsible("")).toBeNull();
    expect(cleanResponsible("Сусарина Анна Владимировна")).toBe("Сусарина Анна Владимировна");
  });
});
```

- [ ] **Step 2: Run to verify failure** — `cd server && npx jest src/migration/hollihop-export-mappers.spec.ts` → module not found.

- [ ] **Step 3: Implement `hollihop-export-mappers.ts`**

```typescript
// server/src/migration/hollihop-export-mappers.ts
// Pure parsers/shapers for HolliHop manual XLSX/CSV exports (converted to JSON).

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : v == null ? "" : String(v).trim();
}

export function parseRuDate(raw: unknown): string | null {
  const s = str(raw);
  const m = s.match(/^(\d{2})\.(\d{2})\.(\d{4})(?:\s+(\d{2}):(\d{2}))?/);
  if (!m) return null;
  const [, dd, mm, yyyy, hh, mi] = m;
  const iso = `${yyyy}-${mm}-${dd}T${hh ?? "00"}:${mi ?? "00"}:00.000Z`;
  const t = Date.parse(iso);
  return Number.isNaN(t) ? null : new Date(t).toISOString();
}

export function taskTitle(description: string): string {
  const first = str(description).split(/\r?\n/).find((l) => l.trim().length) ?? "";
  const t = first.trim();
  if (!t) return "Задача (HolliHop)";
  return t.length > 120 ? t.slice(0, 120) : t;
}

export function cleanResponsible(raw: unknown): string | null {
  const s = str(raw);
  if (!s || /^\[.*\]$/.test(s)) return null; // "[Для всех]" and similar placeholders
  return s;
}

export function taskFromRow(row: Record<string, unknown>) {
  const description = str(row["Описание"]);
  const clientName = str(row["Клиент"]);
  if (!description && !clientName) return null;
  return {
    phoneRaw: str(row["Моб. телефон"]) || str(row["Телефон"]),
    clientName,
    description,
    dueRaw: str(row["Дата выполнения"]),
    responsible: str(row["Ответственный"]),
  };
}

export function studentNoteFromRow(row: Record<string, unknown>) {
  const note = str(row["Описание"]);
  if (!note) return null;
  return {
    phoneRaw: str(row["Моб. телефон"]) || str(row["Телефон"]),
    name: [str(row["Фамилия"]), str(row["Имя"])].filter(Boolean).join(" ") || str(row["Имя"]),
    note,
  };
}

export function leadCommentFromRow(row: Record<string, unknown>) {
  const comment = str(row["Комментарий"]);
  if (!comment) return null;
  const extra = str(row["Пользовательские поля"]);
  return {
    phoneRaw: str(row["Моб. телефон"]) || str(row["Телефон"]),
    name: str(row["ФИО"]),
    body: extra ? `${comment}\n${extra}` : comment,
  };
}
```

- [ ] **Step 4: Run to verify pass** — `cd server && npx jest src/migration/hollihop-export-mappers.spec.ts` → all green.

- [ ] **Step 5: Commit**

```bash
git add server/src/migration/hollihop-export-mappers.ts server/src/migration/hollihop-export-mappers.spec.ts
git commit -m "feat(import): pure mappers for HolliHop manual exports (tasks/notes/comments)"
```

---

## Task 2: The import script + Docker integration validation

**Files:**
- Create: `server/src/migration/import-hollihop-exports.ts`

**Interfaces:**
- Consumes: the Task-1 mappers; `normalizePhoneRu` (`../crm/phone.util`); `deterministicUuid` (find its module — `grep -rn "export function deterministicUuid" server/src`).

- [ ] **Step 1: Implement the script**

Structure (mirror `hollihop-import.ts`'s Pool + dry-run/apply + report shape):
1. Read mode `process.env.HOLLIHOP_EXPORT_IMPORT_MODE ?? 'dry_run'`; dir `process.env.HOLLIHOP_EXPORTS_DIR` (required).
2. `readArrayFile(dir, name)` → JSON array (mirror the main importer's helper; accept a top-level array OR `{Tasks:[...]}` etc.).
3. Connect Pool from `MIGRATION_DATABASE_URL ?? DATABASE_URL`. In apply mode wrap the whole run in `begin`/`commit` (rollback on throw).
4. Build small cached lookups:
   - `matchStudentId(canonicalPhone)` → `select s.id from app.students s join app.profiles p on p.id=s.profile_id and p.deleted_at is null where p.phone_normalized=$1 and s.deleted_at is null limit 1`.
   - `matchLeadId(canonicalPhone)` → `select l.id from app.leads l where l.phone_normalized=$1 and l.deleted_at is null limit 1`.
   - `matchUserId(name)` → the responsible lookup (lower last+first / full_name); cache by name; null if unmatched.
5. **Tasks:** for each `taskFromRow`: `canonical = normalizePhoneRu(phoneRaw).canonical`; entity = student-then-lead match; if none → `unmatched++`, continue. `assigned_to = responsible ? matchUserId(cleanResponsible(responsible)) : null`. Upsert `app.tasks` (id=deterministicUuid task key, entity_type, entity_id, title=taskTitle(description), description, status='open', due_at=parseRuDate(dueRaw), assigned_to, created_by=null) `on conflict (id) do nothing`.
6. **Student notes:** for each `studentNoteFromRow`: match student by phone; if none → unmatched; else upsert `app.entity_comments` (id, entity_type='student', entity_id, author_id=null, body=note) on conflict do nothing.
7. **Lead comments:** for each `leadCommentFromRow`: match lead by phone; if none → unmatched; else upsert `app.lead_comments` (id, lead_id, author_id=null, body) on conflict do nothing.
8. All writes go through a `planUpsert(mode, client, table, row, ["id"])` that only executes in `apply` (dry-run counts only).
9. Print a JSON report: `{ mode, tasks:{total,matchedStudent,matchedLead,unmatched,written}, studentNotes:{...}, leadComments:{...} }`. Exit 0.

- [ ] **Step 2: Typecheck + the existing suite** — `cd server && npm run typecheck && npm test` → 0 / green (the new script doesn't break anything; Task-1 mapper tests pass).

- [ ] **Step 3: Docker integration validation (NOT prod)**

```bash
docker run --rm -d --name mmcrm-exp-pg -e POSTGRES_PASSWORD=test -e POSTGRES_DB=mmcrm_test -p 55443:5432 postgres:16
docker exec mmcrm-exp-pg psql -U postgres -d mmcrm_test -c "create role magiccrm_app" || true
URL='postgres://postgres:test@localhost:55443/mmcrm_test'
cd server && MIGRATION_DATABASE_URL="$URL" DATABASE_URL="$URL" npm run db:migrate   # full chain incl 0025

# Seed one student (with a profile+phone_normalized) and one lead with known phones:
docker exec mmcrm-exp-pg psql -U postgres -d mmcrm_test <<'SQL'
insert into app.users (id, email, role) values ('11111111-1111-1111-1111-111111111111','u@x','client');
insert into app.profiles (id, user_id, first_name, last_name, phone_normalized)
  values ('22222222-2222-2222-2222-222222222222','11111111-1111-1111-1111-111111111111','Петя','Иванов','+79161037743');
insert into app.students (id, profile_id, status) values ('33333333-3333-3333-3333-333333333333','22222222-2222-2222-2222-222222222222','active');
insert into app.leads (id, first_name, last_name, phone_normalized) values ('44444444-4444-4444-4444-444444444444','Иван','Лидов','+79991234567');
SQL

FX="$(mktemp -d)"
cat > "$FX/tasks.json"    <<'JSON'
[{"Дата выполнения":"18.01.2027","Описание":"перезвонить летом","Клиент":"Петя Иванов","Моб. телефон":"+7 916 103-77-43","Ответственный":"[Для всех]"}]
JSON
cat > "$FX/students.json" <<'JSON'
[{"Моб. телефон":"89161037743","Имя":"Петя","Описание":"интерес есть, ждёт осени"}]
JSON
cat > "$FX/leads.json"    <<'JSON'
[{"Моб. телефон":"8 999 123 45 67","ФИО":"Иван Лидов","Комментарий":"перезвонить вечером","Пользовательские поля":"тег: VIP"}]
JSON

cd server && HOLLIHOP_EXPORTS_DIR="$FX" HOLLIHOP_EXPORT_IMPORT_MODE=apply MIGRATION_DATABASE_URL="$URL" DATABASE_URL="$URL" \
  node -r ts-node/register src/migration/import-hollihop-exports.ts
# Assertions:
docker exec mmcrm-exp-pg psql -U postgres -d mmcrm_test -c "select entity_type, title, status from app.tasks;"                 # student | перезвонить летом | open
docker exec mmcrm-exp-pg psql -U postgres -d mmcrm_test -c "select entity_type, body from app.entity_comments;"                 # student | интерес есть, ждёт осени
docker exec mmcrm-exp-pg psql -U postgres -d mmcrm_test -c "select body from app.lead_comments;"                                # перезвонить вечером\nтег: VIP
# Idempotency: re-run apply, counts unchanged.
cd server && HOLLIHOP_EXPORTS_DIR="$FX" HOLLIHOP_EXPORT_IMPORT_MODE=apply MIGRATION_DATABASE_URL="$URL" DATABASE_URL="$URL" node -r ts-node/register src/migration/import-hollihop-exports.ts
docker exec mmcrm-exp-pg psql -U postgres -d mmcrm_test -c "select (select count(*) from app.tasks), (select count(*) from app.entity_comments), (select count(*) from app.lead_comments);"  # 1 | 1 | 1
docker stop mmcrm-exp-pg; rm -rf "$FX"
```
Expected: the task links to the student (phone `+7 916 103-77-43` normalizes to `+79161037743` = the profile), the note → entity_comments(student), the lead comment → lead_comments; idempotent re-run keeps counts at 1/1/1. If the script needs `ts-node` differently, run the compiled path or `npx ts-node`.

- [ ] **Step 4: Commit**

```bash
git add server/src/migration/import-hollihop-exports.ts
git commit -m "feat(import): standalone importer for HolliHop manual exports (tasks->tasks, notes/comments->comments) matched by phone (KVA-179)"
```

---

## Self-Review

- **Coverage:** tasks → `app.tasks` (linked by phone to student/lead) ✅; student notes («Описание») → `app.entity_comments` ✅; lead comments («Комментарий»+«Польз.поля») → `app.lead_comments` ✅; responsible→user best-effort ✅; idempotent + dry-run/apply + match/unmatched report ✅.
- **Honest matching:** unmatched-by-phone rows are COUNTED and SKIPPED, never invented; the report surfaces match rates so the operator sees coverage.
- **No new dependency:** XLSX/CSV→JSON is the operator-side python step (done); the script consumes JSON.
- **Idempotency:** deterministic ids + `on conflict (id) do nothing`; validated by the Docker re-run.

## Operator run (gated, after merge)

JSON already converted to `C:\Users\potyl\Downloads\hollihop-exports\` (tasks.json 507, students.json 1032, leads.json 876). Prod run: rebuild the api image (so `dist/migration/import-hollihop-exports.js` exists) → `scp` the JSON dir to the VPS → fresh `pg_dump` → `docker compose exec -e HOLLIHOP_EXPORTS_DIR=... -e HOLLIHOP_EXPORT_IMPORT_MODE=dry_run api node dist/migration/import-hollihop-exports.js` → review match rates → `apply`. **Note:** the leads export is only «в процессе» (876/3683) — for full lead-comment coverage, re-export ALL leads and re-run (idempotent).
