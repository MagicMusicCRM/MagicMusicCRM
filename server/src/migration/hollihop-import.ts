import {
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { join, resolve } from "node:path";
import { Pool, PoolClient } from "pg";
import { normalizePhoneRu } from "../crm/phone.util";
import { deterministicUuid, sha256Hex } from "./v3-import-utils";
import { disciplineEntries, contactEntries, primaryBranchId } from "./hollihop-mappers";
import { appendMoscowOffset, historyEntryFromRow } from "./hollihop-history-mappers";

type JsonRow = Record<string, unknown>;
type ImportMode = "dry_run" | "apply";
type CrmEntityType = "student" | "lead" | "teacher" | "staff" | "group" | "lesson";
type UserRole = "client" | "teacher" | "manager" | "admin" | "system_admin";

const BASE_URL =
  process.env.HOLLIHOP_BASE_URL?.trim() || "https://sokol.t8s.ru/Api/V2/";
const AUTH_KEY = process.env.HOLLIHOP_AUTH_KEY?.trim();
const CONNECTION_STRING =
  process.env.MIGRATION_DATABASE_URL ?? process.env.DATABASE_URL;
const SOURCE_DIR = process.env.HOLLIHOP_IMPORT_SOURCE_DIR?.trim();
const TAKE = Number(process.env.HOLLIHOP_IMPORT_TAKE ?? "500");
// Lesson generation window. This was the real cause of "too little data": the
// importer pulls ALL EdUnits (GetEdUnits returns every unit), but only expands
// their ScheduleItems into lessons within this window — previously a narrow
// 2025-2026. Widened to HolliHop's full available range (data spans ~2024 → 2027)
// so past and future schedule (by classroom/teacher) is imported, not just ~2y.
const LESSON_FROM = process.env.HOLLIHOP_LESSON_FROM ?? "2024-01-01";
const LESSON_TO = process.env.HOLLIHOP_LESSON_TO ?? "2028-01-01";
// Reference "today" for splitting past (attended/missed) vs future (scheduled)
// lessons when materializing attendance from the HolliHop Days array.
const TODAY_ISO = new Date().toISOString().slice(0, 10);
const STORE_SOURCE_RECORDS =
  (process.env.HOLLIHOP_IMPORT_STORE_SOURCE_RECORDS ?? "true").toLowerCase() !==
  "false";
const VALIDATE_ONLY =
  (process.env.HOLLIHOP_IMPORT_VALIDATE_ONLY ?? "false").toLowerCase() ===
  "true";
const MOSCOW_OFFSET = "+03:00";

interface HolliHopData {
  locations: JsonRow[];
  offices: JsonRow[];
  leadStatuses: JsonRow[];
  teachers: JsonRow[];
  staff: JsonRow[];
  edUnits: JsonRow[];
  students: JsonRow[];
  leads: JsonRow[];
  edUnitStudents: JsonRow[];
  payments: JsonRow[];
  tasks: JsonRow[];
  studentLogs: JsonRow[];
  leadLogs: JsonRow[];
  systemLogs: JsonRow[];
  comments: JsonRow[];
  leadStatusHistory: JsonRow[];
}

interface WarningEntry {
  code: string;
  message: string;
  source?: string;
  rowId?: string;
}

interface ImportContext {
  client: PoolClient;
  batchId: string;
  mode: ImportMode;
  sourceName: string;
  plannedCounts: Record<string, number>;
  skippedCounts: Record<string, number>;
  warnings: WarningEntry[];
  sourceRecordBuffer: SourceRecordRow[];
}

interface ImportResult {
  sourceCounts: Record<string, number>;
  plannedCounts: Record<string, number>;
  skippedCounts: Record<string, number>;
  checksums: Record<string, string>;
  warnings: WarningEntry[];
  monthlyRevenue: Record<string, number>;
  duplicateSummary: Record<string, number>;
}

interface UserProfileValue {
  userId: string;
  profileId: string;
  email: string;
  role: UserRole;
  firstName?: string;
  lastName?: string;
  phone?: string;
  customData: JsonRow;
}

interface TeacherResolveSource {
  unit?: JsonRow;
  schedule?: JsonRow;
}

interface EntityRef {
  entityType: "student" | "lead";
  entityId: string;
}

interface DuplicateSeed {
  entityType: "student" | "lead";
  entityId: string;
  phone?: string;
  email?: string;
  fullName?: string;
}

interface SourceRecordRow {
  id: string;
  import_batch_id: string;
  source: string;
  external_id: string;
  target_table: string | null;
  target_id: string | null;
  source_checksum: string;
  raw: JsonRow;
  field_loss: string[];
}

async function main() {
  if (!CONNECTION_STRING && !VALIDATE_ONLY) {
    throw new Error("MIGRATION_DATABASE_URL or DATABASE_URL is required.");
  }

  const mode = resolveMode();
  const startedAt = new Date();
  const sourceDir = SOURCE_DIR ? resolveInputPath(SOURCE_DIR) : undefined;
  const sourceName = sourceDir
    ? `local:${sourceDir}`
    : `api:${BASE_URL.replace(/[?#].*$/, "")}`;
  const batchId = deterministicUuid(
    "hollihop-import-batch",
    `${sourceName}:${startedAt.toISOString()}:${mode}`,
  );

  const data = sourceDir
    ? loadFromDirectory(sourceDir)
    : await fetchFromApi();

  if (VALIDATE_ONLY) {
    const report = buildValidateOnlyReport({
      batchId,
      mode,
      sourceName,
      startedAt,
      data,
    });
    const reportPath = writeReport(report, startedAt);
    console.log(
      JSON.stringify(
        {
          ok: true,
          validateOnly: true,
          mode,
          batchId,
          reportPath,
          sourceCounts: report.sourceCounts,
          warnings: Array.isArray(report.warnings)
            ? report.warnings.length
            : undefined,
        },
        null,
        2,
      ),
    );
    return;
  }

  const pool = new Pool({
    connectionString: CONNECTION_STRING!,
    max: 2,
    connectionTimeoutMillis: 10_000,
    idleTimeoutMillis: 30_000,
  });

  const client = await pool.connect();
  try {
    await createImportBatch(client, {
      batchId,
      sourceName,
      mode,
      startedAt,
    });

    const ctx: ImportContext = {
      client,
      batchId,
      mode,
      sourceName,
      plannedCounts: {},
      skippedCounts: {},
      warnings: [],
      sourceRecordBuffer: [],
    };

    try {
      if (mode === "apply") await client.query("begin");
      const result = await importAll(ctx, data);
      if (mode === "apply") await client.query("commit");

      const storedCounts = await readStoredCounts(client);
      const report = {
        ok: true,
        batchId,
        mode,
        source: sourceName,
        startedAt: startedAt.toISOString(),
        finishedAt: new Date().toISOString(),
        ...result,
        storedCounts,
      };

      await finishImportBatch(client, {
        batchId,
        status: "completed",
        result,
        storedCounts,
        report,
      });
      const reportPath = writeReport(report, startedAt);
      console.log(
        JSON.stringify(
          {
            ok: true,
            mode,
            batchId,
            reportPath,
            sourceCounts: result.sourceCounts,
            plannedCounts: result.plannedCounts,
            skippedCounts: result.skippedCounts,
            storedCounts,
            warnings: result.warnings.length,
          },
          null,
          2,
        ),
      );
    } catch (error) {
      if (mode === "apply") await client.query("rollback");
      const message = error instanceof Error ? error.message : String(error);
      await failImportBatch(client, batchId, message);
      throw error;
    }
  } finally {
    client.release();
    await pool.end();
  }
}

async function importAll(
  ctx: ImportContext,
  sourceData: HolliHopData,
): Promise<ImportResult> {
  const data = {
    ...sourceData,
    staff: mergeStaffRows(sourceData.staff, sourceData.students, sourceData.leads),
  };
  const sourceCounts = countSources(data);
  const checksums = checksumSources(data);
  const branchByOffice = new Map<string, string>();
  const statusById = new Map<string, string>();
  const teacherById = new Map<string, string>();
  const staffById = new Map<string, string>();
  const staffUserById = new Map<string, string>();
  const studentByClientId = new Map<string, string>();
  const leadById = new Map<string, string>();
  const leadBranchById = new Map<string, string>();
  const groupById = new Map<string, string>();
  const groupMembers = new Map<string, string[]>();
  const roomByKey = new Map<string, string>();
  // Clients/leads skipped because they have no usable RU phone — they can't be
  // linked to an app user, so per the owner we don't import them (no clutter).
  // Their dependent records (lessons/payments/memberships) are skipped too.
  const skippedClientIds = new Set<string>();
  const duplicateSeeds: DuplicateSeed[] = [];
  const monthlyRevenue: Record<string, number> = {};

  if (data.staff.length === 0) {
    warn(ctx, {
      code: "staff_source_missing",
      message:
        "No explicit HolliHop employees/staff source was available. Staff import used only assignees found in students/leads.",
      source: "staff",
    });
  }
  if (data.tasks.length === 0) {
    warn(ctx, {
      code: "tasks_source_missing",
      message:
        "No HolliHop tasks source was available. Configure live endpoint inventory or provide tasks.json before importing tasks.",
      source: "tasks",
    });
  }
  if (
    data.studentLogs.length === 0 &&
    data.leadLogs.length === 0 &&
    data.systemLogs.length === 0 &&
    data.comments.length === 0
  ) {
    warn(ctx, {
      code: "timeline_sources_missing",
      message:
        "No HolliHop history/comment/action-log sources were available. Unified timeline import is limited to tasks/payments/lessons.",
      source: "timeline",
    });
  }
  if (data.leadStatusHistory.length === 0) {
    warn(ctx, {
      code: "lead_status_history_source_missing",
      message:
        "No HolliHop GetHistoryModifyLeadStatus rows were available. Lead status-transition history was not imported.",
      source: "leadStatusHistory",
    });
  }

  for (const office of data.offices) {
    const externalId = text(office.Id);
    const name = text(office.Name);
    if (!externalId || !name) {
      skip(ctx, "offices");
      continue;
    }
    const id = deterministicUuid("hollihop-office", externalId);
    branchByOffice.set(externalId, id);
    await recordSource(ctx, {
      source: "offices",
      externalId,
      row: office,
      targetTable: "app.branches",
      targetId: id,
      mappedKeys: ["Id", "Name", "Address"],
    });
    await planUpsert(
      ctx,
      "branches",
      "app.branches",
      {
        id,
        name,
        address: text(office.Address),
        updated_at: new Date().toISOString(),
      },
      ["id"],
    );
  }

  for (const status of data.leadStatuses) {
    const externalId = text(status.Id);
    const name = text(status.Name);
    if (!externalId || !name) {
      skip(ctx, "leadStatuses");
      continue;
    }
    const existingStatus = await ctx.client.query<{ id: string }>(
      "select id from app.lead_statuses where lower(name) = lower($1) limit 1",
      [name],
    );
    const id =
      existingStatus.rows[0]?.id ??
      deterministicUuid("hollihop-lead-status", externalId);
    statusById.set(externalId, id);
    await recordSource(ctx, {
      source: "leadStatuses",
      externalId,
      row: status,
      targetTable: "app.lead_statuses",
      targetId: id,
      mappedKeys: ["Id", "Name", "Type"],
    });
    await planUpsert(
      ctx,
      "leadStatuses",
      "app.lead_statuses",
      {
        id,
        name,
        color: colorForStatus(text(status.Type) ?? name),
        sort_order: Number(status.SortOrder ?? ctx.plannedCounts.leadStatuses ?? 0),
      },
      ["id"],
    );
  }

  for (const staff of data.staff) {
    const externalId = text(staff.Id);
    if (!externalId) {
      skip(ctx, "staff");
      continue;
    }
    const namespace = text(staff.SourceNamespace) ?? "employee";
    const externalKey = `${namespace}:${externalId}`;
    const userId = deterministicUuid("hollihop-staff-user", externalKey);
    const profileId = deterministicUuid("hollihop-staff-profile", externalKey);
    const staffId = deterministicUuid("hollihop-staff", externalKey);
    staffById.set(externalKey, staffId);
    staffUserById.set(externalKey, userId);
    const nameParts = splitPersonName(staff);
    const email =
      text(staff.EMail)?.toLowerCase() ??
      text(staff.Email)?.toLowerCase() ??
      `hollihop-staff-${safeExternalId(externalKey)}@migration.invalid`;
    const phone = text(staff.Mobile) ?? text(staff.Phone);
    const staffProfile = await upsertUserProfile(ctx, {
      userId,
      profileId,
      email,
      role: normalizeStaffUserRole(staff),
      firstName: nameParts.firstName,
      lastName: nameParts.lastName,
      phone,
      customData: {
        hollihopId: externalId,
        sourceNamespace: namespace,
        middleName: text(staff.MiddleName),
        birthday: text(staff.Birthday),
        role: text(staff.Role),
        position: text(staff.Position),
        offices: staff.Offices,
        sourceAssignee: staff.SourceAssignee,
      },
    });
    await recordSource(ctx, {
      source: "staff",
      externalId: externalKey,
      row: staff,
      targetTable: "app.staff_members",
      targetId: staffId,
      mappedKeys: [
        "Id",
        "SourceNamespace",
        "FirstName",
        "LastName",
        "MiddleName",
        "FullName",
        "Mobile",
        "Phone",
        "EMail",
        "Email",
        "Birthday",
        "Role",
        "Position",
        "Status",
        "Offices",
        "SourceAssignee",
      ],
    });
    await planUpsert(
      ctx,
      "staff",
      "app.staff_members",
      {
        id: staffId,
        profile_id: staffProfile.profileId,
        role: normalizeStaffRoleLabel(staff),
        position: text(staff.Position) ?? text(staff.Role),
        status: normalizeStaffStatus(staff),
        custom_data: {
          hollihopId: externalId,
          sourceNamespace: namespace,
          birthday: text(staff.Birthday),
          offices: staff.Offices,
          rawRole: text(staff.Role),
          rawStatus: text(staff.Status),
        },
        updated_at: new Date().toISOString(),
      },
      ["id"],
    );
    for (const branchId of branchIdsFromRow(staff, branchByOffice)) {
      await planUpsert(
        ctx,
        "staffBranchAssignments",
        "app.staff_branch_assignments",
        {
          staff_member_id: staffId,
          branch_id: branchId,
          deleted_at: null,
        },
        ["staff_member_id", "branch_id"],
      );
    }
  }

  for (const teacher of data.teachers) {
    const externalId = text(teacher.Id);
    if (!externalId) {
      skip(ctx, "teachers");
      continue;
    }
    const userId = deterministicUuid("hollihop-teacher-user", externalId);
    const profileId = deterministicUuid("hollihop-teacher-profile", externalId);
    const teacherId = deterministicUuid("hollihop-teacher", externalId);
    teacherById.set(externalId, teacherId);
    const email =
      text(teacher.EMail)?.toLowerCase() ??
      `hollihop-teacher-${externalId}@migration.invalid`;
    const phone = text(teacher.Mobile) ?? text(teacher.Phone);
    const teacherProfile = await upsertUserProfile(ctx, {
      userId,
      profileId,
      email,
      role: "teacher",
      firstName: text(teacher.FirstName),
      lastName: text(teacher.LastName),
      phone,
      customData: {
        hollihopId: externalId,
        middleName: text(teacher.MiddleName),
        birthday: text(teacher.Birthday),
        disciplines: teacher.Disciplines,
        levels: teacher.Levels,
        maturities: teacher.Maturities,
        offices: teacher.Offices,
        useMobileBySystem: teacher.UseMobileBySystem,
        useEmailBySystem: teacher.UseEMailBySystem,
      },
    });
    await recordSource(ctx, {
      source: "teachers",
      externalId,
      row: teacher,
      targetTable: "app.teachers",
      targetId: teacherId,
      mappedKeys: [
        "Id",
        "FirstName",
        "LastName",
        "MiddleName",
        "Birthday",
        "Mobile",
        "Phone",
        "EMail",
        "Fired",
        "Disciplines",
        "Levels",
        "Maturities",
        "Offices",
        "UseMobileBySystem",
        "UseEMailBySystem",
      ],
    });
    await planUpsert(
      ctx,
      "teachers",
      "app.teachers",
      {
        id: teacherId,
        profile_id: teacherProfile.profileId,
        status: teacher.Fired === true ? "inactive" : "active",
        specialization: arrayLabel(teacher.Disciplines),
        custom_data: {
          hollihopId: externalId,
          birthday: text(teacher.Birthday),
          disciplines: teacher.Disciplines,
          levels: teacher.Levels,
          maturities: teacher.Maturities,
          categories: teacher.Maturities,
          offices: teacher.Offices,
          rating: numberValue(teacher.Rating) ?? 0,
          description: text(teacher.Description),
        },
        updated_at: new Date().toISOString(),
      },
      ["id"],
    );
  }

  for (const student of data.students) {
    const externalId = text(student.Id);
    const clientId = text(student.ClientId) ?? externalId;
    if (!externalId || !clientId) {
      skip(ctx, "students");
      continue;
    }
    // Canonical phone from Mobile (the linkage key); Phone is a rare secondary.
    const mobile = text(student.Mobile);
    const secondaryPhone = text(student.Phone);
    const canonicalPhone = normalizePhoneRu(mobile ?? secondaryPhone).canonical;
    if (!canonicalPhone) {
      // No usable RU phone → can't link to an app user; skip (owner directive).
      skippedClientIds.add(clientId);
      skip(ctx, "students");
      continue;
    }
    const studentId = deterministicUuid("hollihop-student", externalId);
    const userId = deterministicUuid("hollihop-student-user", clientId);
    const profileId = deterministicUuid("hollihop-student-profile", clientId);
    studentByClientId.set(clientId, studentId);
    const phone = canonicalPhone;
    const studentProfile = await upsertUserProfile(ctx, {
      userId,
      profileId,
      email:
        text(student.EMail)?.toLowerCase() ??
        `hollihop-client-${clientId}@migration.invalid`,
      role: "client",
      firstName: text(student.FirstName),
      lastName: text(student.LastName),
      phone,
      customData: {
        hollihopId: externalId,
        hollihopClientId: clientId,
        middleName: text(student.MiddleName),
        gender: text(student.Gender),
        birthday: text(student.Birthday),
        maturity: text(student.Maturity),
        disciplines: student.Disciplines,
        learningTypes: student.LearningTypes,
        officesAndCompanies: student.OfficesAndCompanies,
        contactPersons: student.Agents,
        secondaryPhone: secondaryPhone ?? null,
        useMobileBySystem: student.UseMobileBySystem,
        useEmailBySystem: student.UseEMailBySystem,
      },
    });
    await recordSource(ctx, {
      source: "students",
      externalId,
      row: student,
      targetTable: "app.students",
      targetId: studentId,
      mappedKeys: [
        "Id",
        "ClientId",
        "Created",
        "Updated",
        "FirstName",
        "LastName",
        "MiddleName",
        "Birthday",
        "Gender",
        "Mobile",
        "Phone",
        "EMail",
        "Status",
        "StatusId",
        "AddressDate",
        "VisitDateTime",
        "Maturity",
        "LearningTypes",
        "Disciplines",
        "OfficesAndCompanies",
        "Assignees",
        "Agents",
        "UseMobileBySystem",
        "UseEMailBySystem",
      ],
    });
    const branchIds = branchIdsFromRow(student, branchByOffice);
    const studentBranchId = primaryBranchId(branchIds);
    await planUpsert(
      ctx,
      "students",
      "app.students",
      {
        id: studentId,
        profile_id: studentProfile.profileId,
        status: normalizeStudentStatus(text(student.Status)),
        branch_id: studentBranchId,
        custom_data: {
          hollihopId: externalId,
          hollihopClientId: clientId,
          statusId: text(student.StatusId),
          statusName: text(student.Status),
          addressDate: text(student.AddressDate),
          visitDateTime: text(student.VisitDateTime),
          assignees: student.Assignees,
          responsibleUserIds: assigneeUserIds(student, staffUserById),
          agents: student.Agents,
          adSource: text(student.AdSource),
          position: text(student.Position),
          branchIds: branchIds,
          hasPersonalCabinet: booleanValue(student.HasPersonalCabinet),
          hasPayments: booleanValue(student.HasPayments),
          blacklist: booleanValue(student.Blacklist) ?? false,
        },
        created_at: iso(text(student.Created)) ?? new Date().toISOString(),
        updated_at: iso(text(student.Updated)) ?? new Date().toISOString(),
      },
      ["id"],
    );

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

    duplicateSeeds.push({
      entityType: "student",
      entityId: studentId,
      phone,
      email: text(student.EMail),
      fullName: fullName(student),
    });
  }

  for (const lead of data.leads) {
    const externalId = text(lead.Id);
    if (!externalId) {
      skip(ctx, "leads");
      continue;
    }
    // No usable RU phone → can't link to an app user; skip (owner directive).
    const canonicalLeadPhone = normalizePhoneRu(
      text(lead.Mobile) ?? text(lead.Phone),
    ).canonical;
    if (!canonicalLeadPhone) {
      skip(ctx, "leads");
      continue;
    }
    const leadId = deterministicUuid("hollihop-lead", externalId);
    leadById.set(externalId, leadId);
    const leadBranchId = primaryBranchId(branchIdsFromRow(lead, branchByOffice));
    if (leadBranchId) leadBranchById.set(externalId, leadBranchId);
    const phone = canonicalLeadPhone;
    await recordSource(ctx, {
      source: "leads",
      externalId,
      row: lead,
      targetTable: "app.leads",
      targetId: leadId,
      mappedKeys: [
        "Id",
        "Created",
        "Updated",
        "FirstName",
        "LastName",
        "MiddleName",
        "Birthday",
        "Mobile",
        "Phone",
        "EMail",
        "Status",
        "StatusId",
        "AddressDate",
        "VisitDateTime",
        "Discipline",
        "Level",
        "LearningType",
        "Maturity",
        "AdSource",
        "Source",
        "Category",
        "Goal",
        "RequestType",
        "StudentClientId",
        "OfficesAndCompanies",
        "Assignees",
        "Agents",
        "PreferredSchedule",
        "UseMobileBySystem",
        "UseEMailBySystem",
      ],
    });
    await planUpsert(
      ctx,
      "leads",
      "app.leads",
      {
        id: leadId,
        status_id: statusById.get(text(lead.StatusId) ?? "") ?? null,
        first_name: text(lead.FirstName),
        last_name: text(lead.LastName),
        phone,
        email: text(lead.EMail),
        source: text(lead.AdSource) ?? text(lead.Source),
        notes: text(lead.Description) ?? text(lead.Comment),
        assigned_to: firstAssigneeUserId(lead, staffUserById),
        branch_id: leadBranchId,
        custom_data: {
          hollihopId: externalId,
          middleName: text(lead.MiddleName),
          birthday: text(lead.Birthday),
          statusId: text(lead.StatusId),
          statusName: text(lead.Status),
          discipline: text(lead.Discipline),
          level: text(lead.Level),
          learningType: text(lead.LearningType),
          category: text(lead.Category) ?? text(lead.Maturity),
          goal: text(lead.Goal) ?? text(lead.LearningGoal),
          requestType: text(lead.RequestType) ?? text(lead.Type),
          maturity: text(lead.Maturity),
          addressDate: text(lead.AddressDate),
          visitDateTime: text(lead.VisitDateTime),
          studentClientId: text(lead.StudentClientId),
          officesAndCompanies: lead.OfficesAndCompanies,
          branchIds: branchIdsFromRow(lead, branchByOffice),
          agents: lead.Agents,
          assignees: lead.Assignees,
          responsibleUserIds: assigneeUserIds(lead, staffUserById),
          preferredSchedule: lead.PreferredSchedule,
          useMobileBySystem: lead.UseMobileBySystem,
          useEmailBySystem: lead.UseEMailBySystem,
        },
        created_at: iso(text(lead.Created)) ?? new Date().toISOString(),
        updated_at: iso(text(lead.Updated)) ?? new Date().toISOString(),
      },
      ["id"],
    );

    // Contacts (parents/agents) → app.contacts.
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

    duplicateSeeds.push({
      entityType: "lead",
      entityId: leadId,
      phone,
      email: text(lead.EMail),
      fullName: fullName(lead),
    });
  }

  for (const unit of data.edUnits) {
    const externalId = text(unit.Id);
    const name = text(unit.Name);
    if (!externalId || !name) {
      skip(ctx, "groups");
      continue;
    }
    const groupId = deterministicUuid("hollihop-edunit", externalId);
    groupById.set(externalId, groupId);
    const branchId = branchByOffice.get(text(unit.OfficeOrCompanyId) ?? "");
    const teacherId = resolveTeacherId(teacherById, { unit });
    await recordSource(ctx, {
      source: "edUnits",
      externalId,
      row: unit,
      targetTable: "app.groups",
      targetId: groupId,
      mappedKeys: [
        "Id",
        "Name",
        "Type",
        "Corporative",
        "OfficeOrCompanyId",
        "OfficeOrCompanyName",
        "Discipline",
        "Level",
        "LearningType",
        "StudentsCount",
        "StudyUnitsInRange",
        "Vacancies",
        "Description",
        "ScheduleItems",
        "Assignee",
        "TeacherId",
        "TeacherIds",
        "Teachers",
      ],
    });
    await planUpsert(
      ctx,
      "groups",
      "app.groups",
      {
        id: groupId,
        teacher_id: teacherId,
        branch_id: branchId ?? null,
        room_id: null,
        name,
        price_per_lesson: null,
        updated_at: new Date().toISOString(),
      },
      ["id"],
    );
  }

  for (const membership of data.edUnitStudents) {
    const groupExternalId = text(membership.EdUnitId);
    const clientId = text(membership.StudentClientId);
    if (!groupExternalId || !clientId) {
      skip(ctx, "groupStudents");
      continue;
    }
    const groupId = groupById.get(groupExternalId);
    const studentId = studentByClientId.get(clientId);
    if (!groupId || !studentId) {
      skip(ctx, "groupStudents");
      continue;
    }
    const members = groupMembers.get(groupId) ?? [];
    if (!members.includes(studentId)) {
      members.push(studentId);
      groupMembers.set(groupId, members);
    }
    await recordSource(ctx, {
      source: "edUnitStudents",
      externalId: `${groupExternalId}:${clientId}`,
      row: membership,
      targetTable: "app.group_students",
      targetId: null,
      mappedKeys: [
        "EdUnitId",
        "StudentClientId",
        "BeginDate",
        "EndDate",
        "BeginTime",
        "EndTime",
        "Weekdays",
        "Status",
        "StudyMinutes",
        "StudyUnits",
      ],
    });
    await planUpsert(
      ctx,
      "groupStudents",
      "app.group_students",
      {
        group_id: groupId,
        student_id: studentId,
        joined_at:
          isoDate(text(membership.BeginDate)) ?? new Date().toISOString(),
        left_at: isoDate(text(membership.EndDate)) ?? null,
      },
      ["group_id", "student_id"],
    );
  }

  for (const unit of data.edUnits) {
    const groupId = groupById.get(text(unit.Id) ?? "");
    if (!groupId) continue;
    const branchId = branchByOffice.get(text(unit.OfficeOrCompanyId) ?? "");
    const members = groupMembers.get(groupId) ?? [];
    // HolliHop EdUnits are overwhelmingly single-student (Individual/TrialLesson):
    // such a unit's lessons belong to ONE student, not a "group". When exactly one
    // student is a member, assign student_id directly on the lesson (and leave
    // group_id null) so it shows in that client's card. Real groups (>1 member)
    // stay group lessons with per-member participation.
    const soloStudentId = members.length === 1 ? members[0] : null;
    // An Individual unit with no resolvable student means its client was skipped
    // (no usable phone) — don't generate student-less lesson clutter for it.
    if (text(unit.Type) === "Individual" && !soloStudentId) {
      skip(ctx, "lessons");
      continue;
    }
    // HolliHop's Days array carries actual occurrence attendance (Pass) and the
    // administrator's per-lesson note (Description), keyed by date.
    const daysByDate = new Map<string, JsonRow>();
    for (const d of array(unit.Days)) {
      const dt = text(d.Date)?.slice(0, 10);
      if (dt) daysByDate.set(dt, d);
    }
    for (const schedule of mergeContiguousScheduleItems(
      array(unit.ScheduleItems),
    )) {
      const roomId = await upsertRoom(ctx, schedule, branchId, roomByKey);
      const generated = await upsertLessons(ctx, {
        unit,
        schedule,
        groupId,
        branchId,
        roomId,
        teacherId: resolveTeacherId(teacherById, { unit, schedule }),
        memberStudentIds: members,
        soloStudentId,
        daysByDate,
      });
      if (generated === 0) skip(ctx, "lessons");
    }
  }

  for (const payment of data.payments) {
    const externalId = text(payment.Id);
    const clientId = text(payment.ClientId);
    const state = text(payment.State);
    const rawAmount =
      amountValue(payment.ValueQuantity) ?? amountValue(payment.Value);
    if (!externalId || !clientId || rawAmount === null) {
      skip(ctx, "payments");
      continue;
    }
    const studentId = studentByClientId.get(clientId);
    if (!studentId || state?.toLowerCase() !== "paid") {
      skip(ctx, "payments");
      continue;
    }
    const signedAmount = signedPaymentAmount(rawAmount, text(payment.Type));
    const paymentDate =
      iso(text(payment.PaidDate)) ??
      iso(text(payment.Date)) ??
      iso(text(payment.Created)) ??
      new Date().toISOString();
    addRevenue(monthlyRevenue, paymentDate, signedAmount);
    await recordSource(ctx, {
      source: "payments",
      externalId,
      row: payment,
      targetTable: "app.payments",
      targetId: deterministicUuid("hollihop-payment", externalId),
      mappedKeys: [
        "Id",
        "ClientId",
        "ClientName",
        "Created",
        "Date",
        "PaidDate",
        "RequiredPaidDate",
        "State",
        "Type",
        "Value",
        "ValueQuantity",
        "ValueCurrency",
        "PaymentMethodId",
        "PaymentMethodName",
        "OfficeOrCompanyId",
        "OfficeOrCompanyName",
        "Description",
      ],
    });
    await planUpsert(
      ctx,
      "payments",
      "app.payments",
      {
        id: deterministicUuid("hollihop-payment", externalId),
        student_id: studentId,
        amount: signedAmount,
        currency: normalizeCurrency(text(payment.ValueCurrency)),
        payment_date: paymentDate,
        method: text(payment.PaymentMethodName) ?? text(payment.Type),
        external_id: `hollihop:${externalId}`,
        notes: [
          text(payment.Type),
          state,
          text(payment.Description),
          text(payment.OfficeOrCompanyName),
        ]
          .filter(Boolean)
          .join(" | "),
        created_at: iso(text(payment.Created)) ?? new Date().toISOString(),
      },
      ["id"],
    );
  }

  await importTasks(ctx, data.tasks, {
    studentByClientId,
    leadById,
    staffUserById,
  });
  await importTimeline(ctx, "studentLogs", data.studentLogs, {
    studentByClientId,
    leadById,
  });
  await importTimeline(ctx, "leadLogs", data.leadLogs, {
    studentByClientId,
    leadById,
  });
  await importTimeline(ctx, "comments", data.comments, {
    studentByClientId,
    leadById,
  });
  await importLeadStatusHistory(ctx, data.leadStatusHistory, {
    leadById,
    statusById,
    leadBranchById,
  });

  const duplicateSummary = await importDuplicateCandidates(ctx, duplicateSeeds);
  await flushSourceRecords(ctx);

  return {
    sourceCounts,
    plannedCounts: { ...ctx.plannedCounts },
    skippedCounts: { ...ctx.skippedCounts },
    checksums,
    warnings: ctx.warnings,
    monthlyRevenue,
    duplicateSummary,
  };
}

async function importTasks(
  ctx: ImportContext,
  tasks: JsonRow[],
  maps: {
    studentByClientId: Map<string, string>;
    leadById: Map<string, string>;
    staffUserById: Map<string, string>;
  },
) {
  for (const task of tasks) {
    const externalId = text(task.Id) ?? text(task.TaskId);
    if (!externalId) {
      skip(ctx, "tasks");
      continue;
    }
    const entity = resolveTaskEntity(task, maps);
    if (!entity) {
      skip(ctx, "tasks");
      warn(ctx, {
        code: "task_entity_unresolved",
        message: "HolliHop task could not be attached to a lead or student.",
        source: "tasks",
        rowId: externalId,
      });
      continue;
    }
    await recordSource(ctx, {
      source: "tasks",
      externalId,
      row: task,
      targetTable: "app.tasks",
      targetId: deterministicUuid("hollihop-task", externalId),
      mappedKeys: [
        "Id",
        "TaskId",
        "StudentClientId",
        "ClientId",
        "LeadId",
        "Description",
        "Comment",
        "Text",
        "Title",
        "DueDate",
        "DueTime",
        "Status",
        "ResponsibleId",
        "AssigneeId",
        "CreatedById",
        "Priority",
        "Type",
        "CommunicationType",
      ],
    });
    await planUpsert(
      ctx,
      "tasks",
      "app.tasks",
      {
        id: deterministicUuid("hollihop-task", externalId),
        entity_type: entity.entityType,
        entity_id: entity.entityId,
        title:
          text(task.Title) ??
          text(task.Type) ??
          text(task.CommunicationType) ??
          "Задача HolliHop",
        description:
          text(task.Description) ?? text(task.Comment) ?? text(task.Text),
        status: normalizeTaskStatus(text(task.Status)),
        due_at: combineDateTime(text(task.DueDate), text(task.DueTime)),
        assigned_to: resolveStaffUserId(
          text(task.ResponsibleId) ?? text(task.AssigneeId),
          maps.staffUserById,
        ),
        created_by: resolveStaffUserId(text(task.CreatedById), maps.staffUserById),
        created_at: iso(text(task.Created)) ?? new Date().toISOString(),
        updated_at: iso(text(task.Updated)) ?? new Date().toISOString(),
      },
      ["id"],
    );
  }
}

async function importTimeline(
  ctx: ImportContext,
  sourceName: "studentLogs" | "leadLogs" | "comments",
  rows: JsonRow[],
  maps: {
    studentByClientId: Map<string, string>;
    leadById: Map<string, string>;
  },
) {
  for (const row of rows) {
    const externalId =
      text(row.Id) ??
      text(row.LogId) ??
      text(row.HistoryId) ??
      sha256Hex(stableStringify(row)).slice(0, 32);
    const body =
      text(row.Description) ??
      text(row.Comment) ??
      text(row.Text) ??
      text(row.Message) ??
      text(row.Action);
    if (!body) {
      skip(ctx, sourceName);
      continue;
    }
    const leadId = maps.leadById.get(text(row.LeadId) ?? text(row.EntityId) ?? "");
    const studentId = maps.studentByClientId.get(
      text(row.StudentClientId) ?? text(row.ClientId) ?? text(row.StudentId) ?? "",
    );
    await recordSource(ctx, {
      source: sourceName,
      externalId,
      row,
      targetTable: leadId ? "app.lead_comments" : "app.entity_comments",
      targetId: deterministicUuid(`hollihop-${sourceName}`, externalId),
      mappedKeys: [
        "Id",
        "LogId",
        "HistoryId",
        "LeadId",
        "StudentClientId",
        "ClientId",
        "StudentId",
        "Description",
        "Comment",
        "Text",
        "Message",
        "Action",
        "Created",
        "Date",
      ],
    });
    if (leadId) {
      await planUpsert(
        ctx,
        sourceName,
        "app.lead_comments",
        {
          id: deterministicUuid(`hollihop-${sourceName}`, externalId),
          lead_id: leadId,
          author_id: null,
          body,
          created_at:
            iso(text(row.Created)) ??
            iso(text(row.Date)) ??
            new Date().toISOString(),
        },
        ["id"],
      );
    } else if (studentId) {
      await planUpsert(
        ctx,
        sourceName,
        "app.entity_comments",
        {
          id: deterministicUuid(`hollihop-${sourceName}`, externalId),
          entity_type: "student",
          entity_id: studentId,
          author_id: null,
          body,
          created_at:
            iso(text(row.Created)) ??
            iso(text(row.Date)) ??
            new Date().toISOString(),
        },
        ["id"],
      );
    } else {
      skip(ctx, sourceName);
      warn(ctx, {
        code: "timeline_entity_unresolved",
        message: "HolliHop timeline row could not be attached to a lead or student.",
        source: sourceName,
        rowId: externalId,
      });
    }
  }
}

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

async function importDuplicateCandidates(
  ctx: ImportContext,
  seeds: DuplicateSeed[],
): Promise<Record<string, number>> {
  const summary: Record<string, number> = {};
  const byPhone = groupSeeds(seeds, (seed) => normalizePhone(seed.phone));
  const byEmail = groupSeeds(seeds, (seed) => normalizeEmail(seed.email));
  const byName = groupSeeds(seeds, (seed) => normalizeName(seed.fullName));

  await importDuplicateGroups(ctx, byPhone, "phone", 1, summary);
  await importDuplicateGroups(ctx, byEmail, "email", 0.95, summary);
  await importDuplicateGroups(ctx, byName, "full_name", 0.7, summary);
  return summary;
}

async function importDuplicateGroups(
  ctx: ImportContext,
  groups: Map<string, DuplicateSeed[]>,
  matchType: "phone" | "email" | "full_name",
  confidence: number,
  summary: Record<string, number>,
) {
  for (const [matchValue, seeds] of groups) {
    if (seeds.length < 2) continue;
    for (let i = 0; i < seeds.length - 1; i += 1) {
      for (let j = i + 1; j < seeds.length; j += 1) {
        const [left, right] = orderDuplicateSeeds(seeds[i], seeds[j]);
        const storedMatchType =
          matchType === "phone" &&
          left.entityType !== right.entityType
            ? "lead_student_phone"
            : matchType === "email" && left.entityType !== right.entityType
              ? "lead_student_email"
              : matchType;
        const id = deterministicUuid(
          "hollihop-duplicate-candidate",
          `${left.entityType}:${left.entityId}:${right.entityType}:${right.entityId}:${storedMatchType}:${matchValue}`,
        );
        await planUpsert(
          ctx,
          "duplicateCandidates",
          "app.duplicate_candidates",
          {
            id,
            import_batch_id: ctx.batchId,
            entity_type_a: left.entityType,
            entity_id_a: left.entityId,
            entity_type_b: right.entityType,
            entity_id_b: right.entityId,
            match_type: storedMatchType,
            match_value: matchValue,
            confidence,
            source: "hollihop_import",
            status: "pending",
            updated_at: new Date().toISOString(),
            deleted_at: null,
          },
          ["id"],
        );
        increment(summary, storedMatchType);
      }
    }
  }
}

async function upsertUserProfile(
  ctx: ImportContext,
  value: UserProfileValue,
): Promise<{ userId: string; profileId: string }> {
  const existingUser = await ctx.client.query<{
    id: string;
    role: UserRole;
    is_app_account: boolean;
  }>(
    "select id, role, is_app_account from app.users where lower(email) = lower($1) and deleted_at is null limit 1",
    [value.email],
  );
  const userId = existingUser.rows[0]?.id ?? value.userId;
  const isAppAccount = existingUser.rows[0]?.is_app_account ?? false;
  const effectiveRole = isPrivilegedRole(existingUser.rows[0]?.role)
    ? existingUser.rows[0].role
    : value.role;
  const existingProfile = await ctx.client.query<{ id: string }>(
    "select id from app.profiles where user_id = $1 and deleted_at is null limit 1",
    [userId],
  );
  const profileId = existingProfile.rows[0]?.id ?? value.profileId;
  const fullName = [value.firstName, value.lastName].filter(Boolean).join(" ");
  await planUpsert(
    ctx,
    "users",
    "app.users",
    {
      id: userId,
      email: value.email,
      full_name: fullName || null,
      phone: value.phone ?? null,
      role: effectiveRole,
      profile_completed: isAppAccount
        ? Boolean(value.firstName && value.lastName && value.phone)
        : false,
      is_app_account: isAppAccount,
      updated_at: new Date().toISOString(),
    },
    ["id"],
  );
  await planUpsert(
    ctx,
    "profiles",
    "app.profiles",
    {
      id: profileId,
      user_id: userId,
      first_name: value.firstName ?? null,
      last_name: value.lastName ?? null,
      phone: value.phone ?? null,
      custom_data: value.customData,
      updated_at: new Date().toISOString(),
    },
    ["id"],
  );
  return { userId, profileId };
}

async function upsertRoom(
  ctx: ImportContext,
  schedule: JsonRow,
  branchId: string | undefined,
  cache: Map<string, string>,
): Promise<string | null> {
  const name = text(schedule.ClassroomName);
  if (!name) return null;
  const externalId = text(schedule.ClassroomId);
  const key = externalId ?? `${branchId ?? "global"}:${name.toLowerCase()}`;
  const cached = cache.get(key);
  if (cached) return cached;
  // Reconcile against an existing active room by its natural (branch, name)
  // key before minting a deterministic id. HolliHop's ClassroomId is not
  // stable across pulls, so keying the id on it alone created duplicate rooms
  // for the same physical room. Reusing the existing row keeps re-imports
  // idempotent. (Same find-or-create pattern as lead statuses above.)
  const existing = await ctx.client.query<{ id: string }>(
    `select id from app.rooms
     where deleted_at is null
       and lower(name) = lower($1)
       and branch_id is not distinct from $2::uuid
     order by created_at asc
     limit 1`,
    [name, branchId ?? null],
  );
  const id =
    existing.rows[0]?.id ??
    deterministicUuid("hollihop-classroom", `${branchId ?? "global"}:${key}`);
  cache.set(key, id);
  await recordSource(ctx, {
    source: "rooms",
    externalId: key,
    row: schedule,
    targetTable: "app.rooms",
    targetId: id,
    mappedKeys: ["ClassroomId", "ClassroomName"],
  });
  await planUpsert(
    ctx,
    "rooms",
    "app.rooms",
    {
      id,
      branch_id: branchId ?? null,
      name,
      capacity: null,
      updated_at: new Date().toISOString(),
    },
    ["id"],
  );
  return id;
}

// HolliHop sometimes splits one class into back-to-back ScheduleItems (e.g. a
// 2-hour lesson stored as 15:00-16:00 + 16:00-17:00 in the same room/weekday).
// The importer would turn each into a separate 1-hour lesson. Merge contiguous
// runs (one item's EndTime == the next's BeginTime, same room/weekday/date range/
// teacher) into a single item spanning the full duration before generating.
function mergeContiguousScheduleItems(items: JsonRow[]): JsonRow[] {
  const groups = new Map<string, JsonRow[]>();
  for (const it of items) {
    const key = [
      text(it.ClassroomId) ?? "",
      String(it.Weekdays ?? 0),
      text(it.BeginDate) ?? "",
      text(it.EndDate) ?? "",
      text(it.TeacherId) ?? "",
    ].join("|");
    const list = groups.get(key);
    if (list) list.push(it);
    else groups.set(key, [it]);
  }
  const out: JsonRow[] = [];
  for (const group of groups.values()) {
    const sorted = group
      .slice()
      .sort((a, b) =>
        String(a.BeginTime ?? "").localeCompare(String(b.BeginTime ?? "")),
      );
    let cur: JsonRow | null = null;
    for (const it of sorted) {
      if (
        cur &&
        normalizeTime(text(cur.EndTime)) === normalizeTime(text(it.BeginTime))
      ) {
        cur.EndTime = it.EndTime; // extend the merged run to this item's end
      } else {
        if (cur) out.push(cur);
        cur = { ...it } as JsonRow;
      }
    }
    if (cur) out.push(cur);
  }
  return out;
}

async function upsertLessons(
  ctx: ImportContext,
  value: {
    unit: JsonRow;
    schedule: JsonRow;
    groupId: string;
    branchId?: string;
    roomId: string | null;
    teacherId: string | null;
    memberStudentIds: string[];
    // The single student for an individual/trial unit; null for real groups.
    soloStudentId?: string | null;
    // Per-date occurrence info (Pass attendance + Description note) from Days.
    daysByDate?: Map<string, JsonRow>;
  },
) {
  const unitId = text(value.unit.Id);
  const scheduleId = text(value.schedule.Id);
  const begin = parseDate(text(value.schedule.BeginDate));
  const end = parseDate(text(value.schedule.EndDate)) ?? parseDate(LESSON_TO);
  const beginTime = normalizeTime(text(value.schedule.BeginTime));
  const endTime = normalizeTime(text(value.schedule.EndTime));
  const weekdays = Number(value.schedule.Weekdays ?? 0);
  if (!unitId || !scheduleId || !begin || !end || !beginTime) return 0;

  await recordSource(ctx, {
    source: "scheduleItems",
    externalId: `${unitId}:${scheduleId}`,
    row: value.schedule,
    targetTable: null,
    targetId: null,
    mappedKeys: [
      "Id",
      "BeginDate",
      "EndDate",
      "Weekdays",
      "BeginTime",
      "EndTime",
      "ClassroomId",
      "ClassroomName",
      "Teacher",
      "TeacherId",
      "TeacherIds",
      "Teachers",
    ],
  });

  if (!value.teacherId && hasTeacherSource(value.unit, value.schedule)) {
    warn(ctx, {
      code: "schedule_teacher_unresolved",
      message:
        "Schedule item references a teacher, but the teacher id was not found in imported teachers.",
      source: "scheduleItems",
      rowId: `${unitId}:${scheduleId}`,
    });
  }

  const min = parseDate(LESSON_FROM)!;
  const max = parseDate(LESSON_TO)!;
  const start = begin > min ? begin : min;
  const finish = end < max ? end : max;
  if (finish < start) return 0;

  let count = 0;
  for (const day of eachDate(start, finish)) {
    if (
      !matchesWeekday(day, weekdays) &&
      !(weekdays === 0 && sameDate(day, start))
    ) {
      continue;
    }
    const dayKey = formatDate(day);
    const scheduledAt = `${dayKey}T${beginTime}:00${MOSCOW_OFFSET}`;
    const duration = durationMinutes(beginTime, endTime) ?? 60;
    const lessonId = deterministicUuid(
      "hollihop-lesson",
      `${unitId}:${scheduleId}:${dayKey}`,
    );
    // Attendance from the Days occurrence: Pass=true → attended; a past date
    // with no pass → missed; future → still scheduled.
    const dayInfo = value.daysByDate?.get(dayKey);
    const attended = dayInfo?.Pass === true;
    const isPast = dayKey < TODAY_ISO;
    const lessonStatus = attended || isPast ? "completed" : "scheduled";
    const participationStatus = attended
      ? "present"
      : isPast
        ? "absent"
        : "scheduled";
    await planUpsert(
      ctx,
      "lessons",
      "app.lessons",
      {
        id: lessonId,
        // Individual/trial lesson → assign the student directly (group_id null).
        // Real group → group_id, student_id null (members via participation).
        group_id: value.soloStudentId ? null : value.groupId,
        student_id: value.soloStudentId ?? null,
        teacher_id: value.teacherId,
        branch_id: value.branchId ?? null,
        room_id: value.roomId,
        scheduled_at: scheduledAt,
        duration_minutes: duration,
        status: lessonStatus,
        is_trial: isTrialUnit(value.unit),
        notes: [
          `HolliHop: ${text(value.unit.Name) ?? ""}`.trim(),
          text(value.unit.Type),
          text(value.unit.Discipline),
          text(value.unit.Level),
        ]
          .filter(Boolean)
          .join(" | "),
        updated_at: new Date().toISOString(),
      },
      ["id"],
    );
    for (const studentId of value.memberStudentIds) {
      await planUpsert(
        ctx,
        "lessonParticipation",
        "app.lesson_participation",
        {
          lesson_id: lessonId,
          student_id: studentId,
          status: participationStatus,
          // KVA-237: absent из HolliHop — неоплачиваемый пропуск (час сохранён).
          attendance_kind:
            participationStatus === "absent" ? "unpaid_miss" : "attended",
        },
        ["lesson_id", "student_id"],
      );
    }
    // The administrator's per-lesson note → a chronological admin comment on the
    // (individual) student's card, dated to the lesson day. Idempotent by id.
    const note = text(dayInfo?.Description);
    if (note && value.soloStudentId) {
      await planUpsert(
        ctx,
        "comments",
        "app.entity_comments",
        {
          id: deterministicUuid(
            "hollihop-day-comment",
            `${unitId}:${dayKey}:${value.soloStudentId}`,
          ),
          entity_type: "student",
          entity_id: value.soloStudentId,
          author_id: null,
          body: note,
          kind: "admin_comment",
          created_at: `${dayKey}T12:00:00${MOSCOW_OFFSET}`,
        },
        ["id"],
      );
    }
    count += 1;
  }
  return count;
}

async function planUpsert(
  ctx: ImportContext,
  counterKey: string,
  table: string,
  data: JsonRow,
  conflictColumns: string[],
) {
  increment(ctx.plannedCounts, counterKey);
  if (ctx.mode !== "apply") return;
  await upsert(ctx.client, table, data, conflictColumns);
}

async function upsert(
  client: PoolClient,
  table: string,
  data: JsonRow,
  conflictColumns: string[],
) {
  const entries = Object.entries(data).filter(([, value]) => value !== undefined);
  const columns = entries.map(([key]) => key);
  const values = entries.map(([, value]) => toPgValue(value));
  const placeholders = values.map((_, index) => `$${index + 1}`);
  const updates = columns
    .filter((column) => !conflictColumns.includes(column))
    .map((column) => `${column} = excluded.${column}`);
  const updateClause = updates.length
    ? `do update set ${updates.join(", ")}`
    : "do nothing";
  const sql = `
    insert into ${table} (${columns.join(", ")})
    values (${placeholders.join(", ")})
    on conflict (${conflictColumns.join(", ")})
    ${updateClause}
  `;
  try {
    await client.query(sql, values);
  } catch (error) {
    const pgError = error as { code?: string; detail?: string; message?: string };
    throw new Error(
      [
        `HolliHop upsert failed for ${table}`,
        `columns=${columns.join(",")}`,
        pgError.code ? `code=${pgError.code}` : undefined,
        pgError.detail ? `detail=${pgError.detail}` : undefined,
        pgError.message,
      ]
        .filter(Boolean)
        .join(" | "),
    );
  }
}

function toPgValue(value: unknown) {
  if (
    value !== null &&
    typeof value === "object" &&
    !(value instanceof Date) &&
    !Buffer.isBuffer(value)
  ) {
    return JSON.stringify(value);
  }
  return value;
}

async function recordSource(
  ctx: ImportContext,
  value: {
    source: string;
    externalId: string;
    row: JsonRow;
    targetTable: string | null;
    targetId: string | null;
    mappedKeys: string[];
  },
) {
  if (!STORE_SOURCE_RECORDS) return;
  const raw = stableStringify(value.row);
  ctx.sourceRecordBuffer.push({
    id: deterministicUuid(
      "hollihop-source-record",
      `${ctx.batchId}:${value.source}:${value.externalId}`,
    ),
    import_batch_id: ctx.batchId,
    source: value.source,
    external_id: value.externalId,
    target_table: value.targetTable,
    target_id: value.targetId,
    source_checksum: sha256Hex(raw),
    raw: value.row,
    field_loss: unmappedFields(value.row, value.mappedKeys),
  });
  increment(ctx.plannedCounts, "sourceRecords");
  if (ctx.sourceRecordBuffer.length >= 500) {
    await flushSourceRecords(ctx);
  }
}

async function flushSourceRecords(ctx: ImportContext) {
  if (ctx.sourceRecordBuffer.length === 0) return;
  const buffered = ctx.sourceRecordBuffer.splice(
    0,
    ctx.sourceRecordBuffer.length,
  );
  // Dedupe by the ON CONFLICT key so this single multi-row upsert can never
  // target the same row twice (Postgres: "ON CONFLICT DO UPDATE command cannot
  // affect row a second time"). HolliHop can reuse a ScheduleItem Id across
  // periods, so the same (source, external_id) may appear twice — last wins.
  const byKey = new Map<string, SourceRecordRow>();
  for (const r of buffered) {
    byKey.set(`${r.import_batch_id}:${r.source}:${r.external_id}`, r);
  }
  const rows = [...byKey.values()];
  await ctx.client.query(
    `
      insert into app.import_source_records (
        id,
        import_batch_id,
        source,
        external_id,
        target_table,
        target_id,
        source_checksum,
        raw,
        field_loss
      )
      select
        (item ->> 'id')::uuid,
        (item ->> 'import_batch_id')::uuid,
        item ->> 'source',
        item ->> 'external_id',
        item ->> 'target_table',
        nullif(item ->> 'target_id', '')::uuid,
        item ->> 'source_checksum',
        item -> 'raw',
        item -> 'field_loss'
      from jsonb_array_elements($1::jsonb) as item
      on conflict (import_batch_id, source, external_id)
      do update set
        target_table = excluded.target_table,
        target_id = excluded.target_id,
        source_checksum = excluded.source_checksum,
        raw = excluded.raw,
        field_loss = excluded.field_loss
    `,
    [JSON.stringify(rows)],
  );
}

async function createImportBatch(
  client: PoolClient,
  value: {
    batchId: string;
    sourceName: string;
    mode: ImportMode;
    startedAt: Date;
  },
) {
  await upsert(
    client,
    "app.import_batches",
    {
      id: value.batchId,
      source: value.sourceName,
      mode: value.mode,
      status: "running",
      started_at: value.startedAt.toISOString(),
    },
    ["id"],
  );
}

async function finishImportBatch(
  client: PoolClient,
  value: {
    batchId: string;
    status: "completed" | "failed";
    result: ImportResult;
    storedCounts: Record<string, number>;
    report: JsonRow;
  },
) {
  await client.query(
    `
      update app.import_batches
      set status = $2,
          finished_at = now(),
          source_counts = $3,
          planned_counts = $4,
          stored_counts = $5,
          skipped_counts = $6,
          checksums = $7,
          warnings = $8,
          report = $9
      where id = $1
    `,
    [
      value.batchId,
      value.status,
      toPgValue(value.result.sourceCounts),
      toPgValue(value.result.plannedCounts),
      toPgValue(value.storedCounts),
      toPgValue(value.result.skippedCounts),
      toPgValue(value.result.checksums),
      toPgValue(value.result.warnings),
      toPgValue(value.report),
    ],
  );
}

async function failImportBatch(
  client: PoolClient,
  batchId: string,
  message: string,
) {
  await client.query(
    `
      update app.import_batches
      set status = 'failed',
          finished_at = now(),
          warnings = jsonb_build_array(jsonb_build_object('code', 'import_failed', 'message', $2::text))
      where id = $1
    `,
    [batchId, message],
  );
}

async function readStoredCounts(
  client: PoolClient,
): Promise<Record<string, number>> {
  const result = await client.query<Record<string, string>>(`
    select
      (select count(*)::text from app.branches where deleted_at is null) as branches,
      (select count(*)::text from app.rooms where deleted_at is null) as rooms,
      (select count(*)::text from app.lead_statuses) as lead_statuses,
      (select count(*)::text from app.staff_members where deleted_at is null) as staff,
      (select count(*)::text from app.teachers where deleted_at is null) as teachers,
      (select count(*)::text from app.students where deleted_at is null) as students,
      (select count(*)::text from app.leads where deleted_at is null) as leads,
      (select count(*)::text from app.groups where deleted_at is null) as groups,
      (select count(*)::text from app.group_students) as group_students,
      (select count(*)::text from app.lessons where deleted_at is null) as lessons,
      (select count(*)::text from app.lesson_participation) as lesson_participation,
      (select count(*)::text from app.payments where deleted_at is null) as payments,
      (select count(*)::text from app.tasks where deleted_at is null) as tasks,
      (select count(*)::text from app.entity_comments where deleted_at is null) as entity_comments,
      (select count(*)::text from app.lead_comments where deleted_at is null) as lead_comments,
      (select count(*)::text from app.lead_status_history) as lead_status_history,
      (select count(*)::text from app.duplicate_candidates where deleted_at is null) as duplicate_candidates,
      (select count(*)::text from app.import_source_records) as import_source_records
  `);
  const row = result.rows[0] ?? {};
  return Object.fromEntries(
    Object.entries(row).map(([key, value]) => [key, Number(value ?? 0)]),
  );
}

function loadFromDirectory(dir: string): HolliHopData {
  return {
    locations: readArrayFile(dir, ["locations.json"], "Locations"),
    offices: readArrayFile(dir, ["offices.json"], "Offices"),
    leadStatuses: readArrayFile(
      dir,
      ["leadstatuses.json", "lead_statuses.json"],
      "Statuses",
    ),
    teachers: readArrayFile(dir, ["teachers.json"], "Teachers"),
    staff: [
      ...readArrayFile(dir, ["employees.json"], "Employees"),
      ...readArrayFile(dir, ["staff.json"], "Staff"),
      ...readArrayFile(dir, ["users.json"], "Users"),
    ],
    edUnits: readArrayFile(dir, ["edunits.json", "ed_units.json"], "EdUnits"),
    students: readArrayFile(dir, ["students.json"], "Students"),
    leads: readArrayFile(dir, ["leads.json"], "Leads"),
    edUnitStudents: readArrayFile(
      dir,
      ["edunitstudents.json", "ed_unit_students.json"],
      "EdUnitStudents",
    ),
    payments: readArrayFile(dir, ["payments.json"], "Payments"),
    tasks: readArrayFile(dir, ["tasks.json"], "Tasks"),
    studentLogs: readArrayFile(
      dir,
      ["student_logs.json", "studentlogs.json"],
      "StudentLogs",
    ),
    leadLogs: readArrayFile(dir, ["lead_logs.json", "leadlogs.json"], "LeadLogs"),
    systemLogs: readArrayFile(
      dir,
      ["system_logs.json", "systemlogs.json"],
      "SystemLogs",
    ),
    comments: readArrayFile(dir, ["comments.json"], "Comments"),
    leadStatusHistory: readArrayFile(
      dir,
      ["lead_status_history.json", "leadstatushistory.json"],
      "Actions",
    ),
  };
}

function buildValidateOnlyReport(value: {
  batchId: string;
  mode: ImportMode;
  sourceName: string;
  startedAt: Date;
  data: HolliHopData;
}): JsonRow {
  const mergedData = {
    ...value.data,
    staff: mergeStaffRows(value.data.staff, value.data.students, value.data.leads),
  };
  const warnings: WarningEntry[] = [];
  if (value.data.staff.length === 0) {
    warnings.push({
      code: "staff_source_missing",
      message:
        "No explicit HolliHop employees/staff source was available. Staff count is derived from assignees only.",
      source: "staff",
    });
  }
  if (value.data.tasks.length === 0) {
    warnings.push({
      code: "tasks_source_missing",
      message:
        "No HolliHop tasks source was available in this source set.",
      source: "tasks",
    });
  }
  if (
    value.data.studentLogs.length === 0 &&
    value.data.leadLogs.length === 0 &&
    value.data.systemLogs.length === 0 &&
    value.data.comments.length === 0
  ) {
    warnings.push({
      code: "timeline_sources_missing",
      message:
        "No HolliHop history/comment/action-log source was available in this source set.",
      source: "timeline",
    });
  }
  return {
    ok: true,
    validateOnly: true,
    batchId: value.batchId,
    mode: value.mode,
    source: value.sourceName,
    startedAt: value.startedAt.toISOString(),
    finishedAt: new Date().toISOString(),
    sourceCounts: countSources(mergedData),
    checksums: checksumSources(mergedData),
    monthlyRevenue: calculateSourceMonthlyRevenue(mergedData.payments),
    duplicateSummary: calculateSourceDuplicateSummary(
      mergedData.students,
      mergedData.leads,
    ),
    warnings,
  };
}

async function fetchFromApi(): Promise<HolliHopData> {
  if (!AUTH_KEY) {
    throw new Error(
      "HOLLIHOP_AUTH_KEY is required unless HOLLIHOP_IMPORT_SOURCE_DIR is set.",
    );
  }
  const [
    locations,
    offices,
    leadStatuses,
    teachers,
    edUnits,
    students,
    leads,
    edUnitStudents,
    payments,
    employees,
    staff,
    tasks,
    studentLogs,
    leadLogs,
    systemLogs,
    comments,
    leadStatusHistory,
  ] = await Promise.all([
    fetchRoot("GetLocations", "Locations"),
    fetchRoot("GetOffices", "Offices"),
    fetchRoot("GetLeadStatuses", "Statuses"),
    fetchRoot("GetTeachers", "Teachers"),
    fetchEdUnits(),
    fetchPaged("GetStudents", "Students"),
    fetchPaged("GetLeads", "Leads"),
    fetchPaged("GetEdUnitStudents", "EdUnitStudents"),
    fetchPaged("GetPayments", "Payments"),
    fetchOptionalPaged("GetEmployees", "Employees"),
    fetchOptionalPaged("GetStaff", "Staff"),
    fetchOptionalPaged("GetTasks", "Tasks"),
    fetchOptionalPaged("GetStudentLogs", "StudentLogs"),
    fetchOptionalPaged("GetLeadLogs", "LeadLogs"),
    fetchOptionalPaged("GetSystemLogs", "SystemLogs"),
    fetchOptionalPaged("GetComments", "Comments"),
    // HolliHop returns the rows under the "Actions" root key (verified against
    // a live page), not the method-name convention.
    fetchOptionalPaged("GetHistoryModifyLeadStatus", "Actions"),
  ]);
  return {
    locations,
    offices,
    leadStatuses,
    teachers,
    staff: [...employees, ...staff],
    edUnits,
    students,
    leads,
    edUnitStudents,
    payments,
    tasks,
    studentLogs,
    leadLogs,
    systemLogs,
    comments,
    leadStatusHistory,
  };
}

async function fetchRoot(method: string, rootKey: string): Promise<JsonRow[]> {
  const data = await fetchJson(method);
  const items = data[rootKey];
  return Array.isArray(items) ? (items as JsonRow[]) : [];
}

// GetEdUnits must be fetched with a date range AND queryDays=true so each unit
// carries its actual occurrences (Days) — that is where per-lesson attendance
// (Pass) and the administrator's note (Description) live. Without queryDays the
// Days array is empty, so attendance and comments never import.
async function fetchEdUnits(): Promise<JsonRow[]> {
  const data = await fetchJson("GetEdUnits", {
    dateFrom: LESSON_FROM,
    dateTo: LESSON_TO,
    queryDays: "true",
  });
  const items = data.EdUnits;
  return Array.isArray(items) ? (items as JsonRow[]) : [];
}

async function fetchPaged(method: string, rootKey: string): Promise<JsonRow[]> {
  const all: JsonRow[] = [];
  for (let skipValue = 0; ; skipValue += TAKE) {
    const data = await fetchJson(method, { skip: skipValue, take: TAKE });
    const items = data[rootKey];
    if (!Array.isArray(items)) break;
    all.push(...(items as JsonRow[]));
    if (items.length < TAKE) break;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  return all;
}

async function fetchOptionalPaged(
  method: string,
  rootKey: string,
): Promise<JsonRow[]> {
  try {
    return await fetchPaged(method, rootKey);
  } catch {
    return [];
  }
}

async function fetchJson(
  method: string,
  params: Record<string, string | number> = {},
): Promise<JsonRow> {
  const url = new URL(method, BASE_URL.endsWith("/") ? BASE_URL : `${BASE_URL}/`);
  url.searchParams.set("authkey", AUTH_KEY!);
  for (const [key, value] of Object.entries(params)) {
    url.searchParams.set(key, String(value));
  }
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`HolliHop ${method} failed with HTTP ${response.status}`);
  }
  return (await response.json()) as JsonRow;
}

function readArrayFile(dir: string, names: string[], rootKey: string): JsonRow[] {
  const file = names.map((name) => join(dir, name)).find((path) => existsSync(path));
  if (!file) return [];
  const parsed = JSON.parse(readFileSync(file, "utf8")) as unknown;
  if (Array.isArray(parsed)) return parsed as JsonRow[];
  if (parsed && typeof parsed === "object") {
    const value = (parsed as JsonRow)[rootKey];
    if (Array.isArray(value)) return value as JsonRow[];
  }
  return [];
}

function writeReport(report: JsonRow, startedAt: Date): string {
  const defaultDir = process.cwd().endsWith(`${process.platform === "win32" ? "\\" : "/"}server`)
    ? "exports"
    : "server/exports";
  const fileName = `hollihop-import-${startedAt.toISOString().replace(/[:.]/g, "-")}.json`;
  // The report is written AFTER the data is committed, so a write failure (e.g.
  // a read-only/owned exports dir in the container) must NOT fail the import.
  // Try the configured dir, then the default, then /tmp; never throw.
  const candidates = [
    process.env.HOLLIHOP_IMPORT_REPORT_DIR,
    defaultDir,
    "/tmp",
  ].filter((d): d is string => Boolean(d));
  for (const base of candidates) {
    try {
      const dir = resolveInputPath(base);
      mkdirSync(dir, { recursive: true });
      const file = join(dir, fileName);
      writeFileSync(file, JSON.stringify(report, null, 2), "utf8");
      return file;
    } catch {
      // try the next candidate
    }
  }
  return "(report not written)";
}

function resolveInputPath(value: string): string {
  const direct = resolve(value);
  if (existsSync(direct)) return direct;
  const fromRepoRoot = resolve("..", value);
  if (existsSync(fromRepoRoot)) return fromRepoRoot;
  return direct;
}

function mergeStaffRows(
  explicitRows: JsonRow[],
  students: JsonRow[],
  leads: JsonRow[],
): JsonRow[] {
  const rows = new Map<string, JsonRow>();
  for (const row of explicitRows) {
    const id = text(row.Id) ?? text(row.UserId) ?? text(row.EmployeeId);
    if (!id) continue;
    rows.set(`employee:${id}`, {
      ...row,
      Id: id,
      SourceNamespace: text(row.SourceNamespace) ?? "employee",
    });
  }
  for (const owner of [...students, ...leads]) {
    for (const assignee of array(owner.Assignees)) {
      const id = text(assignee.Id);
      if (!id) continue;
      const key = `assignee:${id}`;
      const previous = rows.get(key) ?? {};
      const offices = mergeArrays(previous.Offices, owner.OfficesAndCompanies);
      rows.set(key, {
        ...previous,
        Id: id,
        SourceNamespace: "assignee",
        FullName: text(assignee.FullName) ?? text(previous.FullName),
        Role: text(previous.Role) ?? "Ответственный",
        Position: text(previous.Position) ?? "Ответственный",
        Status: text(previous.Status) ?? "Работает",
        Offices: offices,
        SourceAssignee: true,
      });
    }
  }
  return [...rows.values()];
}

function countSources(data: HolliHopData): Record<string, number> {
  return {
    locations: data.locations.length,
    offices: data.offices.length,
    leadStatuses: data.leadStatuses.length,
    teachers: data.teachers.length,
    staff: data.staff.length,
    edUnits: data.edUnits.length,
    students: data.students.length,
    leads: data.leads.length,
    edUnitStudents: data.edUnitStudents.length,
    payments: data.payments.length,
    tasks: data.tasks.length,
    studentLogs: data.studentLogs.length,
    leadLogs: data.leadLogs.length,
    systemLogs: data.systemLogs.length,
    comments: data.comments.length,
    leadStatusHistory: data.leadStatusHistory.length,
  };
}

function checksumSources(data: HolliHopData): Record<string, string> {
  return Object.fromEntries(
    Object.entries(data).map(([key, value]) => [
      key,
      sha256Hex(stableStringify(value)),
    ]),
  );
}

function resolveMode(): ImportMode {
  const argMode = process.argv.includes("--apply")
    ? "apply"
    : process.argv.includes("--dry-run")
      ? "dry_run"
      : undefined;
  const envMode = process.env.HOLLIHOP_IMPORT_MODE?.trim().toLowerCase();
  if (argMode) return argMode;
  if (envMode === "apply") return "apply";
  return "dry_run";
}

function text(value: unknown): string | undefined {
  if (typeof value === "string" && value.trim()) return value.trim();
  if (typeof value === "number" && Number.isFinite(value)) return String(value);
  if (typeof value === "boolean") return String(value);
  return undefined;
}

function booleanValue(value: unknown): boolean | undefined {
  if (typeof value === "boolean") return value;
  if (typeof value === "string") {
    const lower = value.toLowerCase().trim();
    if (["true", "1", "yes", "да"].includes(lower)) return true;
    if (["false", "0", "no", "нет"].includes(lower)) return false;
  }
  return undefined;
}

function numberValue(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim()) {
    const parsed = Number(value.replace(",", "."));
    if (Number.isFinite(parsed)) return parsed;
  }
  return undefined;
}

function array(value: unknown): JsonRow[] {
  return Array.isArray(value) ? (value as JsonRow[]) : [];
}

function mergeArrays(left: unknown, right: unknown): JsonRow[] {
  const values = [...array(left), ...array(right)];
  const byKey = new Map<string, JsonRow>();
  for (const value of values) {
    const key = text(value.Id) ?? text(value.Name) ?? stableStringify(value);
    byKey.set(key, value);
  }
  return [...byKey.values()];
}

function arrayLabel(value: unknown): string | null {
  if (!Array.isArray(value)) return null;
  const labels = value
    .map((item) =>
      typeof item === "string" ? item : text((item as JsonRow).Name),
    )
    .filter(Boolean);
  return labels.length ? labels.join(", ") : null;
}

function iso(value: string | undefined): string | null {
  if (!value) return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

function isoDate(value: string | undefined): string | null {
  const parsed = parseDate(value);
  return parsed ? `${formatDate(parsed)}T00:00:00${MOSCOW_OFFSET}` : null;
}

function parseDate(value: string | undefined): Date | null {
  const match = value?.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (!match) return null;
  return new Date(
    Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])),
  );
}

function* eachDate(start: Date, finish: Date) {
  for (
    const day = new Date(start);
    day <= finish;
    day.setUTCDate(day.getUTCDate() + 1)
  ) {
    yield new Date(day);
  }
}

function matchesWeekday(day: Date, mask: number): boolean {
  if (!mask) return false;
  const mondayBased = (day.getUTCDay() + 6) % 7;
  return (mask & (1 << mondayBased)) !== 0;
}

function sameDate(a: Date, b: Date): boolean {
  return formatDate(a) === formatDate(b);
}

function formatDate(value: Date): string {
  return value.toISOString().slice(0, 10);
}

function normalizeTime(value: string | undefined): string | null {
  const match = value?.match(/^(\d{1,2}):(\d{2})/);
  if (!match) return null;
  return `${match[1].padStart(2, "0")}:${match[2]}`;
}

function durationMinutes(begin: string, end: string | null): number | null {
  if (!end) return null;
  const [beginHour, beginMinute] = begin.split(":").map(Number);
  const [endHour, endMinute] = end.split(":").map(Number);
  const diff =
    endHour * 60 + endMinute - (beginHour * 60 + beginMinute);
  return diff > 0 ? diff : null;
}

function amountValue(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value !== "string") return null;
  const normalized = value
    .replace(/\u00a0/g, "")
    .replace(/\s/g, "")
    .replace(/руб\.?/gi, "")
    .replace(",", ".")
    .trim();
  const parsed = Number(normalized);
  return Number.isFinite(parsed) ? parsed : null;
}

function signedPaymentAmount(amount: number, type: string | undefined): number {
  const lower = type?.toLowerCase() ?? "";
  if (lower.includes("возврат") || lower.includes("refund")) {
    return -Math.abs(amount);
  }
  return amount;
}

function normalizeCurrency(value: string | undefined): string {
  if (!value) return "RUB";
  const lower = value.toLowerCase();
  if (lower.includes("руб") || lower.includes("rub")) return "RUB";
  return value.toUpperCase();
}

function normalizeStudentStatus(value: string | undefined) {
  const lower = value?.toLowerCase();
  if (!lower) return "active";
  if (
    lower.includes("архив") ||
    lower.includes("отказ") ||
    lower.includes("закончил") ||
    lower.includes("не ")
  ) {
    return "inactive";
  }
  return "active";
}

function colorForStatus(value: string) {
  const lower = value.toLowerCase();
  if (lower.includes("отказ") || lower.includes("reject")) return "danger";
  if (lower.includes("усп") || lower.includes("success")) return "success";
  if (lower.includes("отлож") || lower.includes("pending")) return "warning";
  if (lower.includes("проб")) return "primaryPurple";
  return "info";
}

function normalizeTaskStatus(value: string | undefined): string {
  const lower = value?.toLowerCase();
  if (!lower) return "open";
  if (lower.includes("закр") || lower.includes("done") || lower.includes("closed")) {
    return "done";
  }
  if (lower.includes("отмен") || lower.includes("cancel")) return "cancelled";
  return "open";
}

function normalizeStaffUserRole(row: JsonRow): UserRole {
  const lower = [
    text(row.Role),
    text(row.Position),
    text(row.FullName),
  ]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();
  if (lower.includes("администратор системы") || lower.includes("system")) {
    return "system_admin";
  }
  if (lower.includes("директор") || lower.includes("управ")) return "manager";
  if (lower.includes("админ") || lower.includes("менедж")) return "manager";
  return "manager";
}

function normalizeStaffRoleLabel(row: JsonRow): string {
  return text(row.Role) ?? text(row.Position) ?? "Сотрудник";
}

function normalizeStaffStatus(row: JsonRow): string {
  const lower = [text(row.Status), text(row.State)]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();
  if (row.Fired === true || lower.includes("увол") || lower.includes("не работает")) {
    return "Не работает";
  }
  if (lower.includes("отпуск")) return "Отпуск";
  return "Работает";
}

function splitPersonName(row: JsonRow): { firstName?: string; lastName?: string } {
  const firstName = text(row.FirstName);
  const lastName = text(row.LastName);
  if (firstName || lastName) return { firstName, lastName };
  const full = text(row.FullName) ?? text(row.Name);
  if (!full) return {};
  const parts = full.split(/\s+/);
  return {
    firstName: parts[1] ?? parts[0],
    lastName: parts[0],
  };
}

function fullName(row: JsonRow): string | undefined {
  const direct = text(row.FullName) ?? text(row.Name);
  if (direct) return direct;
  return [text(row.LastName), text(row.FirstName), text(row.MiddleName)]
    .filter(Boolean)
    .join(" ")
    .trim() || undefined;
}

function branchIdsFromRow(
  row: JsonRow,
  branchByOffice: Map<string, string>,
): string[] {
  const ids = new Set<string>();
  for (const office of [
    ...array(row.OfficesAndCompanies),
    ...array(row.Offices),
  ]) {
    const id = branchByOffice.get(text(office.Id) ?? "");
    if (id) ids.add(id);
  }
  const direct = branchByOffice.get(
    text(row.OfficeOrCompanyId) ?? text(row.OfficeId) ?? "",
  );
  if (direct) ids.add(direct);
  return [...ids];
}

function assigneeUserIds(
  row: JsonRow,
  staffUserById: Map<string, string>,
): string[] {
  return array(row.Assignees)
    .map((assignee) => resolveStaffUserId(text(assignee.Id), staffUserById))
    .filter((id): id is string => Boolean(id));
}

function firstAssigneeUserId(
  row: JsonRow,
  staffUserById: Map<string, string>,
): string | null {
  return assigneeUserIds(row, staffUserById)[0] ?? null;
}

function resolveStaffUserId(
  externalId: string | undefined,
  staffUserById: Map<string, string>,
): string | null {
  if (!externalId) return null;
  return (
    staffUserById.get(`assignee:${externalId}`) ??
    staffUserById.get(`employee:${externalId}`) ??
    null
  );
}

function resolveTeacherId(
  teacherById: Map<string, string>,
  source: TeacherResolveSource,
): string | null {
  for (const candidate of teacherExternalIds(source.unit, source.schedule)) {
    const teacherId = teacherById.get(candidate);
    if (teacherId) return teacherId;
  }
  return null;
}

function teacherExternalIds(
  unit: JsonRow | undefined,
  schedule: JsonRow | undefined,
): string[] {
  const ids = new Set<string>();
  for (const row of [unit, schedule].filter(Boolean) as JsonRow[]) {
    for (const key of ["TeacherId", "TeacherID", "AssigneeId"]) {
      const id = text(row[key]);
      if (id) ids.add(id);
    }
    for (const key of ["TeacherIds", "TeacherIDs"]) {
      const value = row[key];
      if (Array.isArray(value)) {
        for (const nested of value) {
          const id = text(nested);
          if (id) ids.add(id);
        }
      }
    }
    for (const nested of [...array(row.Teachers), ...array(row.Assignees)]) {
      const id = text(nested.Id);
      if (id) ids.add(id);
    }
    const teacher = row.Teacher;
    if (teacher && typeof teacher === "object") {
      const id = text((teacher as JsonRow).Id);
      if (id) ids.add(id);
    }
  }
  return [...ids];
}

function hasTeacherSource(unit: JsonRow, schedule: JsonRow): boolean {
  return teacherExternalIds(unit, schedule).length > 0;
}

function isTrialUnit(unit: JsonRow): boolean {
  const lower = [text(unit.Type), text(unit.Name), text(unit.Status)]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();
  return lower.includes("проб") || lower.includes("trial");
}

function resolveTaskEntity(
  task: JsonRow,
  maps: {
    studentByClientId: Map<string, string>;
    leadById: Map<string, string>;
  },
): EntityRef | null {
  const leadId = maps.leadById.get(text(task.LeadId) ?? "");
  if (leadId) return { entityType: "lead", entityId: leadId };
  const studentId = maps.studentByClientId.get(
    text(task.StudentClientId) ?? text(task.ClientId) ?? text(task.StudentId) ?? "",
  );
  if (studentId) return { entityType: "student", entityId: studentId };
  return null;
}

function combineDateTime(
  date: string | undefined,
  timeValue: string | undefined,
): string | null {
  const parsedDate = parseDate(date);
  if (!parsedDate) return null;
  const parsedTime = normalizeTime(timeValue) ?? "00:00";
  return `${formatDate(parsedDate)}T${parsedTime}:00${MOSCOW_OFFSET}`;
}

function addRevenue(
  revenue: Record<string, number>,
  paymentDate: string,
  amount: number,
) {
  const month = paymentDate.slice(0, 7);
  revenue[month] = Number(((revenue[month] ?? 0) + amount).toFixed(2));
}

function calculateSourceMonthlyRevenue(payments: JsonRow[]): Record<string, number> {
  const revenue: Record<string, number> = {};
  for (const payment of payments) {
    const state = text(payment.State);
    const rawAmount =
      amountValue(payment.ValueQuantity) ?? amountValue(payment.Value);
    if (rawAmount === null || state?.toLowerCase() !== "paid") continue;
    const paymentDate =
      iso(text(payment.PaidDate)) ??
      iso(text(payment.Date)) ??
      iso(text(payment.Created));
    if (!paymentDate) continue;
    addRevenue(revenue, paymentDate, signedPaymentAmount(rawAmount, text(payment.Type)));
  }
  return revenue;
}

function groupSeeds(
  seeds: DuplicateSeed[],
  keyFactory: (seed: DuplicateSeed) => string | undefined,
): Map<string, DuplicateSeed[]> {
  const result = new Map<string, DuplicateSeed[]>();
  for (const seed of seeds) {
    const key = keyFactory(seed);
    if (!key) continue;
    const values = result.get(key) ?? [];
    values.push(seed);
    result.set(key, values);
  }
  return result;
}

function calculateSourceDuplicateSummary(
  students: JsonRow[],
  leads: JsonRow[],
): Record<string, number> {
  const seeds: DuplicateSeed[] = [
    ...students.map((student) => ({
      entityType: "student" as const,
      entityId:
        text(student.Id) ??
        deterministicUuid("hollihop-source-student", stableStringify(student)),
      phone: text(student.Mobile) ?? text(student.Phone),
      email: text(student.EMail),
      fullName: fullName(student),
    })),
    ...leads.map((lead) => ({
      entityType: "lead" as const,
      entityId:
        text(lead.Id) ??
        deterministicUuid("hollihop-source-lead", stableStringify(lead)),
      phone: text(lead.Mobile) ?? text(lead.Phone),
      email: text(lead.EMail),
      fullName: fullName(lead),
    })),
  ];
  const summary: Record<string, number> = {};
  for (const [matchType, groups] of [
    ["phone", groupSeeds(seeds, (seed) => normalizePhone(seed.phone))],
    ["email", groupSeeds(seeds, (seed) => normalizeEmail(seed.email))],
    ["full_name", groupSeeds(seeds, (seed) => normalizeName(seed.fullName))],
  ] as const) {
    for (const group of groups.values()) {
      if (group.length < 2) continue;
      const pairCount = (group.length * (group.length - 1)) / 2;
      increment(summary, matchType, pairCount);
    }
  }
  return summary;
}

function orderDuplicateSeeds(
  left: DuplicateSeed,
  right: DuplicateSeed,
): [DuplicateSeed, DuplicateSeed] {
  const leftKey = `${left.entityType}:${left.entityId}`;
  const rightKey = `${right.entityType}:${right.entityId}`;
  return leftKey <= rightKey ? [left, right] : [right, left];
}

function normalizePhone(value: string | undefined): string | undefined {
  return normalizePhoneRu(value).canonical ?? undefined;
}

function normalizeEmail(value: string | undefined): string | undefined {
  const normalized = value?.trim().toLowerCase();
  return normalized && normalized.includes("@") ? normalized : undefined;
}

function normalizeName(value: string | undefined): string | undefined {
  const normalized = value
    ?.trim()
    .toLowerCase()
    .replace(/ё/g, "е")
    .replace(/\s+/g, " ");
  if (!normalized || normalized.split(" ").length < 2) return undefined;
  return normalized;
}

function isPrivilegedRole(value: UserRole | undefined): boolean {
  return value === "admin" || value === "manager" || value === "system_admin";
}

function unmappedFields(row: JsonRow, mappedKeys: string[]): string[] {
  const mapped = new Set(mappedKeys);
  return Object.entries(row)
    .filter(([key, value]) => !mapped.has(key) && !isEmptyValue(value))
    .map(([key]) => key)
    .sort();
}

function isEmptyValue(value: unknown): boolean {
  if (value === null || value === undefined) return true;
  if (typeof value === "string" && value.trim() === "") return true;
  if (Array.isArray(value) && value.length === 0) return true;
  return false;
}

function stableStringify(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map((item) => stableStringify(item)).join(",")}]`;
  }
  if (value && typeof value === "object") {
    const entries = Object.entries(value as JsonRow).sort(([a], [b]) =>
      a.localeCompare(b),
    );
    return `{${entries
      .map(([key, nested]) => `${JSON.stringify(key)}:${stableStringify(nested)}`)
      .join(",")}}`;
  }
  return JSON.stringify(value);
}

function safeExternalId(value: string): string {
  return value.replace(/[^a-zA-Z0-9_-]+/g, "-").slice(0, 80);
}

function skip(ctx: ImportContext, key: string) {
  increment(ctx.skippedCounts, key);
}

function warn(ctx: ImportContext, warning: WarningEntry) {
  ctx.warnings.push(warning);
}

function increment(target: Record<string, number>, key: string, by = 1) {
  target[key] = (target[key] ?? 0) + by;
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
