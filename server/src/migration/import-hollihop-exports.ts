// server/src/migration/import-hollihop-exports.ts
// Standalone importer for HolliHop manual XLSX/CSV exports (tasks, student notes, lead comments)
// matched by phone to existing students/leads.
//
// Usage (dry run – default):
//   HOLLIHOP_EXPORTS_DIR=/path/to/json node -r ts-node/register src/migration/import-hollihop-exports.ts
// Usage (apply writes):
//   HOLLIHOP_EXPORTS_DIR=/path/to/json HOLLIHOP_EXPORT_IMPORT_MODE=apply node -r ts-node/register src/migration/import-hollihop-exports.ts

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { Pool, PoolClient } from "pg";
import { normalizePhoneRu } from "../crm/phone.util";
import { deterministicUuid } from "./v3-import-utils";
import {
  taskFromRow,
  studentNoteFromRow,
  leadCommentFromRow,
  parseRuDate,
  taskTitle,
  cleanResponsible,
} from "./hollihop-export-mappers";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type ImportMode = "dry_run" | "apply";
type JsonRow = Record<string, unknown>;

interface SectionReport {
  total: number;
  matchedStudent: number;
  matchedLead: number;
  unmatched: number;
  written: number;
}

interface RunReport {
  mode: ImportMode;
  tasks: SectionReport;
  studentNotes: SectionReport;
  leadComments: SectionReport;
}

// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------

const MODE: ImportMode =
  (process.env.HOLLIHOP_EXPORT_IMPORT_MODE?.trim().toLowerCase() as ImportMode | undefined) === "apply"
    ? "apply"
    : "dry_run";

const EXPORTS_DIR = process.env.HOLLIHOP_EXPORTS_DIR?.trim();

const CONNECTION_STRING =
  process.env.MIGRATION_DATABASE_URL ?? process.env.DATABASE_URL;

// ---------------------------------------------------------------------------
// readArrayFile — accepts a top-level array OR {Tasks:[...]}, {Students:[...]}, etc.
// ---------------------------------------------------------------------------

function readArrayFile(dir: string, name: string, rootKey: string): JsonRow[] {
  const filePath = join(dir, name);
  if (!existsSync(filePath)) return [];
  const parsed = JSON.parse(readFileSync(filePath, "utf8")) as unknown;
  if (Array.isArray(parsed)) return parsed as JsonRow[];
  if (parsed && typeof parsed === "object") {
    const value = (parsed as JsonRow)[rootKey];
    if (Array.isArray(value)) return value as JsonRow[];
  }
  return [];
}

// ---------------------------------------------------------------------------
// Dry-run-aware upsert
// ---------------------------------------------------------------------------

const ALLOWED_TABLES = ["app.tasks", "app.entity_comments", "app.lead_comments"];

async function planUpsert(
  mode: ImportMode,
  client: PoolClient,
  table: string,
  data: JsonRow,
  conflictColumns: string[],
): Promise<boolean> {
  if (!ALLOWED_TABLES.includes(table)) {
    throw new Error(`unexpected table: ${table}`);
  }
  if (mode !== "apply") return false;
  const entries = Object.entries(data).filter(([, v]) => v !== undefined);
  const columns = entries.map(([k]) => k);
  const values = entries.map(([, v]) =>
    v !== null && typeof v === "object" && !(v instanceof Date) && !Buffer.isBuffer(v)
      ? JSON.stringify(v)
      : v,
  );
  const placeholders = values.map((_, i) => `$${i + 1}`);
  const sql = `
    insert into ${table} (${columns.join(", ")})
    values (${placeholders.join(", ")})
    on conflict (${conflictColumns.join(", ")}) do nothing
  `;
  try {
    const result = await client.query(sql, values);
    return (result.rowCount ?? 0) > 0;
  } catch (err) {
    const pg = err as { code?: string; detail?: string; message?: string };
    throw new Error(
      [
        `export-import upsert failed for ${table}`,
        pg.code ? `code=${pg.code}` : undefined,
        pg.detail ? `detail=${pg.detail}` : undefined,
        pg.message,
      ]
        .filter(Boolean)
        .join(" | "),
    );
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  if (!EXPORTS_DIR) {
    throw new Error("HOLLIHOP_EXPORTS_DIR is required.");
  }
  if (!existsSync(EXPORTS_DIR)) {
    throw new Error(`HOLLIHOP_EXPORTS_DIR does not exist: ${EXPORTS_DIR}`);
  }
  if (!CONNECTION_STRING) {
    throw new Error("MIGRATION_DATABASE_URL or DATABASE_URL is required.");
  }

  // Load source files
  const taskRows = readArrayFile(EXPORTS_DIR, "tasks.json", "Tasks");
  const studentRows = readArrayFile(EXPORTS_DIR, "students.json", "Students");
  const leadRows = readArrayFile(EXPORTS_DIR, "leads.json", "Leads");

  // Always connect to DB — dry_run needs it to compute real match counts (read-only SELECTs).
  const pool = new Pool({
    connectionString: CONNECTION_STRING,
    max: 2,
    connectionTimeoutMillis: 10_000,
    idleTimeoutMillis: 30_000,
  });

  let client: PoolClient | undefined;
  try {
    client = await pool.connect();

    // Only wrap in a transaction when writing
    if (MODE === "apply") {
      await client.query("begin");
    }

    try {
      // Build phone→id lookup caches
      // Typed Map<string, string | null> so a cached miss (null) round-trips correctly.
      // We store the real value (id or null) rather than an empty-string sentinel; the
      // getter `cache.get(key) ?? null` is then safe because null ?? null === null.
      const studentCache = new Map<string, string | null>();
      const leadCache = new Map<string, string | null>();
      const userCache = new Map<string, string | null>();

      const matchStudentId = async (canonical: string): Promise<string | null> => {
        if (studentCache.has(canonical)) return studentCache.get(canonical) ?? null;
        const r = await client!.query<{ id: string }>(
          `select s.id from app.students s
           join app.profiles p on p.id = s.profile_id and p.deleted_at is null
           where p.phone_normalized = $1 and s.deleted_at is null
           limit 1`,
          [canonical],
        );
        const id = r.rows[0]?.id ?? null;
        studentCache.set(canonical, id);
        return id;
      };

      const matchLeadId = async (canonical: string): Promise<string | null> => {
        if (leadCache.has(canonical)) return leadCache.get(canonical) ?? null;
        const r = await client!.query<{ id: string }>(
          `select l.id from app.leads l
           where l.phone_normalized = $1 and l.deleted_at is null
           limit 1`,
          [canonical],
        );
        const id = r.rows[0]?.id ?? null;
        leadCache.set(canonical, id);
        return id;
      };

      const matchUserId = async (name: string | null): Promise<string | null> => {
        if (!name) return null;
        const key = name.toLowerCase().trim();
        if (userCache.has(key)) return userCache.get(key) ?? null;
        // Try matching last+first against profiles, then full_name on users
        const r = await client!.query<{ id: string }>(
          `select u.id from app.users u
           join app.profiles p on p.user_id = u.id and p.deleted_at is null
           where u.deleted_at is null
             and (
               lower(concat_ws(' ', p.last_name, p.first_name)) = $1
               or lower(concat_ws(' ', p.first_name, p.last_name)) = $1
               or lower(u.full_name) = $1
             )
           limit 1`,
          [key],
        );
        const id = r.rows[0]?.id ?? null;
        userCache.set(key, id);
        return id;
      };

      // ---- Tasks -----------------------------------------------------------
      const tasksReport: SectionReport = {
        total: 0,
        matchedStudent: 0,
        matchedLead: 0,
        unmatched: 0,
        written: 0,
      };

      for (const row of taskRows) {
        const mapped = taskFromRow(row);
        if (!mapped) continue;
        tasksReport.total++;

        const { canonical } = normalizePhoneRu(mapped.phoneRaw);
        if (!canonical) {
          tasksReport.unmatched++;
          continue;
        }

        // student-then-lead match
        const studentId = await matchStudentId(canonical);
        const leadId = studentId ? null : await matchLeadId(canonical);

        // Treat as unmatched if id is null or (belt-and-suspenders) an empty string
        if (!studentId && !leadId) {
          tasksReport.unmatched++;
          continue;
        }

        const entityType = studentId ? "student" : "lead";
        const entityId = (studentId || leadId)!;
        if (studentId) tasksReport.matchedStudent++;
        else tasksReport.matchedLead++;

        // responsible→user (best-effort, null if unmatched)
        const cleanName = cleanResponsible(mapped.responsible);
        const assignedTo = await matchUserId(cleanName);

        // Use canonical phone so re-exports with different raw formats produce the same id
        const taskKey = `export:task:${canonical}:${mapped.dueRaw}:${mapped.description}`;
        const id = deterministicUuid("hollihop-export-task", taskKey);

        const written = await planUpsert(MODE, client, "app.tasks", {
          id,
          entity_type: entityType,
          entity_id: entityId,
          title: taskTitle(mapped.description),
          description: mapped.description || null,
          status: "open",
          due_at: parseRuDate(mapped.dueRaw),
          assigned_to: assignedTo || null,
          created_by: null,
        }, ["id"]);

        if (written) tasksReport.written++;
      }

      // ---- Student notes ---------------------------------------------------
      const studentNotesReport: SectionReport = {
        total: 0,
        matchedStudent: 0,
        matchedLead: 0,
        unmatched: 0,
        written: 0,
      };

      for (const row of studentRows) {
        const mapped = studentNoteFromRow(row);
        if (!mapped) continue;
        studentNotesReport.total++;

        const { canonical } = normalizePhoneRu(mapped.phoneRaw);
        if (!canonical) {
          studentNotesReport.unmatched++;
          continue;
        }

        const studentId = await matchStudentId(canonical);
        if (!studentId) {
          studentNotesReport.unmatched++;
          continue;
        }
        studentNotesReport.matchedStudent++;

        // Use canonical phone for stable idempotency key
        const noteKey = `export:student-note:${canonical}:${mapped.note}`;
        const id = deterministicUuid("hollihop-export-student-note", noteKey);

        const written = await planUpsert(MODE, client, "app.entity_comments", {
          id,
          entity_type: "student",
          entity_id: studentId,
          author_id: null,
          body: mapped.note,
        }, ["id"]);

        if (written) studentNotesReport.written++;
      }

      // ---- Lead comments ---------------------------------------------------
      const leadCommentsReport: SectionReport = {
        total: 0,
        matchedStudent: 0,
        matchedLead: 0,
        unmatched: 0,
        written: 0,
      };

      for (const row of leadRows) {
        const mapped = leadCommentFromRow(row);
        if (!mapped) continue;
        leadCommentsReport.total++;

        const { canonical } = normalizePhoneRu(mapped.phoneRaw);
        if (!canonical) {
          leadCommentsReport.unmatched++;
          continue;
        }

        const leadId = await matchLeadId(canonical);
        if (!leadId) {
          leadCommentsReport.unmatched++;
          continue;
        }
        leadCommentsReport.matchedLead++;

        // Use canonical phone for stable idempotency key
        const commentKey = `export:lead-comment:${canonical}:${mapped.body}`;
        const id = deterministicUuid("hollihop-export-lead-comment", commentKey);

        const written = await planUpsert(MODE, client, "app.lead_comments", {
          id,
          lead_id: leadId,
          author_id: null,
          body: mapped.body,
        }, ["id"]);

        if (written) leadCommentsReport.written++;
      }

      if (MODE === "apply") {
        await client.query("commit");
      }

      const report: RunReport = {
        mode: MODE,
        tasks: tasksReport,
        studentNotes: studentNotesReport,
        leadComments: leadCommentsReport,
      };
      process.stdout.write(JSON.stringify(report, null, 2) + "\n");
    } catch (err) {
      if (MODE === "apply") {
        await client.query("rollback");
      }
      throw err;
    }
  } finally {
    client?.release();
    await pool.end();
  }
}

main().catch((err: unknown) => {
  console.error(err instanceof Error ? err.message : err);
  process.exitCode = 1;
});
