import { ForbiddenException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import { AuditService } from "../../audit/audit.service";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { PlatformIntegrityRepository } from "../../platform/platform-integrity.repository";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { CrmPolicy } from "../crm.policy";
import { ClientArchiveService } from "./client-archive.service";
import { ClientConfigRepository } from "./client-config.repository";
import { ClientConversionService } from "./client-conversion.service";
import { ClientInternalContextService } from "./client-internal-context.service";
import { ClientReferenceService } from "./client-reference.service";
import { ClientWriteValidator } from "./client-write.validator";

const defaultTestDatabaseUrl =
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
const testDatabaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ?? defaultTestDatabaseUrl;
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(
    new URL(testDatabaseUrl).hostname,
  )
) {
  throw new Error("Conversion tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("Lead to Student conversion (PostgreSQL)", () => {
  let database: DatabaseService;
  let service: ClientConversionService;
  let archives: ClientArchiveService;
  let internalContext: ClientInternalContextService;
  let branchId: string;
  let leadId: string;
  let linkedUserId: string;
  let managerId: string;
  let adminId: string;
  let directorId: string;
  let leadDefinitionId: string;
  let studentDefinitionId: string;
  let sourceId: string;
  let studentId: string;
  let noteId: string;
  let historyCommentId: string;
  let historyTaskId: string;
  const operationalStaffIds: string[] = [];
  const operationalProfileIds: string[] = [];

  beforeAll(async () => {
    const pool = new Pool({ connectionString: testDatabaseUrl });
    try {
      await new MigrationRunner(pool).up();
    } finally {
      await pool.end();
    }
    database = new DatabaseService({
      getOrThrow: () => testDatabaseUrl,
    } as unknown as ConfigService);
    const repository = new ClientConfigRepository(database);
    service = new ClientConversionService(
      database,
      repository,
      new ClientWriteValidator(repository),
      new CrmPolicy(),
      {
        record: jest.fn().mockResolvedValue(undefined),
      } as unknown as AuditService,
      { emitCrmChanged: jest.fn() } as unknown as RealtimeBus,
    );
    archives = new ClientArchiveService(
      database,
      new PlatformIntegrityService(database, new PlatformIntegrityRepository()),
      new CrmPolicy(),
      { emitCrmChanged: jest.fn() } as unknown as RealtimeBus,
    );
    internalContext = new ClientInternalContextService(
      database,
      new ClientReferenceService(database),
      new PlatformIntegrityRepository(),
      { emitCrmChanged: jest.fn() } as unknown as RealtimeBus,
    );

    const branch = await database.query<{ id: string }>(
      "insert into app.branches (name) values ($1) returning id",
      [`Conversion ${randomUUID()}`],
    );
    branchId = branch.rows[0]!.id;
    const users = await database.query<{ id: string; role: string }>(
      `
        insert into app.users (email, role, full_name, email_verified_at)
        values
          ($1, 'manager', 'Мария Управляющая', now()),
          ($2, 'director', 'Диана Директор', now()),
          ($3, 'client', 'Клиент', now()),
          ($4, 'admin', 'Анна Администратор', now())
        returning id, role::text as role
      `,
      [
        `conversion-manager-${randomUUID()}@example.test`,
        `conversion-director-${randomUUID()}@example.test`,
        `conversion-client-${randomUUID()}@example.test`,
        `conversion-admin-${randomUUID()}@example.test`,
      ],
    );
    managerId = users.rows.find((row) => row.role === "manager")!.id;
    directorId = users.rows.find((row) => row.role === "director")!.id;
    linkedUserId = users.rows.find((row) => row.role === "client")!.id;
    adminId = users.rows.find((row) => row.role === "admin")!.id;
    for (const [userId, role] of [
      [managerId, "manager"],
      [adminId, "admin"],
    ] as const) {
      const profile = await database.query<{ id: string }>(
        `insert into app.profiles (user_id, first_name, last_name)
         values ($1, $2, $3) returning id`,
        [
          userId,
          role === "admin" ? "Анна" : "Мария",
          role === "admin" ? "Администратор" : "Управляющая",
        ],
      );
      operationalProfileIds.push(profile.rows[0]!.id);
      const staff = await database.query<{ id: string }>(
        `insert into app.staff_members (profile_id, role)
         values ($1, $2) returning id`,
        [profile.rows[0]!.id, role],
      );
      operationalStaffIds.push(staff.rows[0]!.id);
      await database.query(
        `insert into app.user_crm_links (
           user_id, entity_type, entity_id, link_source, confirmed_at
         ) values ($1, 'staff', $2, 'manual_email', now())`,
        [userId, staff.rows[0]!.id],
      );
      await database.query(
        `insert into app.staff_branch_assignments (staff_member_id, branch_id)
         values ($1, $2)`,
        [staff.rows[0]!.id, branchId],
      );
    }
    const source = await database.query<{ id: string }>(
      `
        insert into app.lead_sources (canonical_name, display_name, is_active)
        values ($1, $2, true)
        returning id
      `,
      [`conversion_${randomUUID().replace(/-/g, "")}`, "Conversion source"],
    );
    sourceId = source.rows[0]!.id;
    const lead = await database.query<{ id: string }>(
      `
        insert into app.leads (
          first_name, last_name, phone, custom_data, branch_id, source_id,
          created_by
        )
        values (
          'Старое', 'Имя', '+79990000000',
          '{"legacy":"preserved"}'::jsonb, $1, $2, $3
        )
        returning id
      `,
      [branchId, sourceId, managerId],
    );
    leadId = lead.rows[0]!.id;
    const note = await database.query<{ id: string }>(
      `insert into app.client_internal_notes (lead_id, body, updated_by)
       values ($1, 'Важная заметка лида', $2)
       returning id`,
      [leadId, managerId],
    );
    noteId = note.rows[0]!.id;
    await database.query(
      `
        insert into app.user_crm_links (
          user_id, entity_type, entity_id, link_source, created_by, confirmed_at
        )
        values ($1, 'lead', $2, 'manual_phone', $3, now())
      `,
      [linkedUserId, leadId, managerId],
    );
    const definitions = await database.query<{ id: string }>(
      `
        insert into app.client_custom_field_definitions (
          field_key, label, value_type, visible_on_lead, visible_on_student
        )
        values ($1, 'Общее поле', 'text', true, true)
        returning id
      `,
      [`shared_${randomUUID().replace(/-/g, "")}`],
    );
    leadDefinitionId = definitions.rows[0]!.id;
    studentDefinitionId = leadDefinitionId;
    await database.query(
      `
        insert into app.client_custom_field_values (
          definition_id, entity_type, entity_id, value_text
        )
        values ($1, 'lead', $2, 'перенесено')
      `,
      [leadDefinitionId, leadId],
    );
  });

  afterAll(async () => {
    await database.query(
      `delete from app.audit_events
       where entity_type = any($1::text[])
         and entity_id = any($2::text[])`,
      [["lead", "student"], [leadId, studentId].filter(Boolean)],
    );
    await database.query(
      "delete from app.audit_events where action = 'crm.client_internal_note_changed' and entity_id = $1",
      [noteId],
    );
    if (historyCommentId) {
      await database.query(
        "delete from app.audit_events where entity_type = 'crm:comment' and entity_id = $1",
        [historyCommentId],
      );
      await database.query("delete from app.entity_comments where id = $1", [
        historyCommentId,
      ]);
    }
    if (historyTaskId) {
      await database.query(
        "delete from app.audit_events where entity_type = 'shared_task' and entity_id = $1",
        [historyTaskId],
      );
      await database.query("delete from app.shared_tasks where id = $1", [
        historyTaskId,
      ]);
    }
    await database.query(
      "delete from app.client_internal_notes where id = $1",
      [noteId],
    );
    await database.query(
      `
        delete from app.idempotency_records
        where operation = 'crm.client.archive'
          and result_ref->>'entityId' = $1
      `,
      [leadId],
    );
    await database.query(
      `
        delete from app.platform_outbox_events
        where aggregate_type = 'crm:lead' and aggregate_id = $1
      `,
      [leadId],
    );
    await database.query(
      `
        delete from app.audit_events
        where entity_type = 'crm:lead' and entity_id = $1
      `,
      [leadId],
    );
    await database.query(
      `
        delete from app.aggregate_versions
        where aggregate_type = 'crm:lead' and aggregate_id = $1
      `,
      [leadId],
    );
    await database.query(
      "delete from app.client_custom_field_values where entity_id = any($1::uuid[])",
      [[leadId, studentId].filter(Boolean)],
    );
    await database.query(
      "delete from app.client_conversion_links where lead_id = $1",
      [leadId],
    );
    if (studentId) {
      const identity = await database.query<{
        profile_id: string;
        user_id: string;
      }>(
        `
          select student.profile_id, profile.user_id
          from app.students student
          join app.profiles profile on profile.id = student.profile_id
          where student.id = $1
        `,
        [studentId],
      );
      await database.query(
        "delete from app.user_crm_links where entity_id = any($1::uuid[])",
        [[leadId, studentId]],
      );
      await database.query("delete from app.students where id = $1", [
        studentId,
      ]);
      if (identity.rows[0]) {
        await database.query("delete from app.profiles where id = $1", [
          identity.rows[0].profile_id,
        ]);
        await database.query("delete from app.users where id = $1", [
          identity.rows[0].user_id,
        ]);
      }
    }
    await database.query("delete from app.leads where id = $1", [leadId]);
    await database.query("delete from app.lead_sources where id = $1", [
      sourceId,
    ]);
    await database.query(
      "delete from app.client_custom_field_definitions where id = any($1::uuid[])",
      [[leadDefinitionId, studentDefinitionId]],
    );
    await database.query(
      "delete from app.user_crm_links where entity_type = 'staff' and entity_id = any($1::uuid[])",
      [operationalStaffIds],
    );
    await database.query(
      "delete from app.staff_branch_assignments where staff_member_id = any($1::uuid[])",
      [operationalStaffIds],
    );
    await database.query(
      "delete from app.staff_members where id = any($1::uuid[])",
      [operationalStaffIds],
    );
    await database.query(
      "delete from app.profiles where id = any($1::uuid[])",
      [operationalProfileIds],
    );
    await database.query("delete from app.branches where id = $1", [branchId]);
    await database.query("delete from app.users where id = any($1::uuid[])", [
      [managerId, directorId, linkedUserId, adminId],
    ]);
    await database.onModuleDestroy();
  });

  it("creates one Student/link concurrently, preserves data, and archives only the Lead", async () => {
    const dto = {
      firstName: "Новый",
      lastName: "Ученик",
      phone: "8 (999) 000-00-00",
      branchId,
      status: "active",
    };
    const [left, right] = await Promise.all([
      service.convert({ userId: managerId, role: "manager" }, leadId, dto),
      service.convert({ userId: managerId, role: "manager" }, leadId, dto),
    ]);
    studentId = left.studentId;
    expect(left.studentId).toBe(right.studentId);
    expect(studentId).toBe(leadId);
    expect([left.replayed, right.replayed].sort()).toEqual([false, true]);

    const facts = await database.query<{
      students: string;
      links: string;
      crm_links: string;
      copied_value: string;
      legacy_value: string;
      source_id: string;
      client_count: string;
      lifecycle_state: string;
      value_count: string;
    }>(
      `
        select
          (select count(*)::text from app.students
            where lead_id = $1 and deleted_at is null) as students,
          (select count(*)::text from app.client_conversion_links
            where lead_id = $1 and student_id = $2) as links,
          (select count(*)::text from app.user_crm_links
            where entity_type = 'student' and entity_id = $2
              and user_id = $3 and deleted_at is null) as crm_links,
          (select value_text from app.client_custom_field_values
            where definition_id = $4 and entity_type = 'student'
              and entity_id = $2) as copied_value,
          (select custom_data->>'legacy' from app.students
            where id = $2) as legacy_value,
          (select source_id::text from app.students
            where id = $2) as source_id,
          (select count(*)::text from app.clients
            where id = $1) as client_count,
          (select lifecycle_state from app.clients
            where id = $1) as lifecycle_state,
          (select count(*)::text from app.client_custom_field_values
            where definition_id = $4 and client_id = $1) as value_count,
          (select version::text from app.leads where id = $1) as lead_version
      `,
      [leadId, studentId, linkedUserId, studentDefinitionId],
    );
    expect(facts.rows[0]).toEqual({
      students: "1",
      links: "1",
      crm_links: "1",
      copied_value: "перенесено",
      legacy_value: "preserved",
      source_id: sourceId,
      client_count: "1",
      lifecycle_state: "student",
      value_count: "1",
      lead_version: "2",
    });

    await database.query(
      `update app.profiles
       set first_name = 'Обновлённое', updated_at = now()
       where id = (select profile_id from app.students where id = $1)`,
      [studentId],
    );
    await expect(
      database.query<{ first_name: string; lifecycle_state: string }>(
        `select first_name, lifecycle_state from app.clients where id = $1`,
        [leadId],
      ),
    ).resolves.toMatchObject({
      rows: [
        { first_name: "Обновлённое", lifecycle_state: "student" },
      ],
    });

    const leadNote = await internalContext.getNote(
      { userId: managerId, role: "manager" },
      { type: "lead", id: leadId },
    );
    const studentNote = await internalContext.getNote(
      { userId: directorId, role: "director" },
      { type: "student", id: studentId },
    );
    expect(studentNote).toMatchObject({
      id: leadNote.id,
      body: "Важная заметка лида",
      version: 1,
    });

    const concurrent = await Promise.allSettled([
      internalContext.updateNote(
        { userId: adminId, role: "admin" },
        { type: "student", id: studentId },
        { expectedVersion: 1, body: "Администратор обновил контекст" },
      ),
      internalContext.updateNote(
        { userId: managerId, role: "manager" },
        { type: "lead", id: leadId },
        { expectedVersion: 1, body: "Конкурирующая правка" },
      ),
    ]);
    expect(
      concurrent.filter((item) => item.status === "fulfilled"),
    ).toHaveLength(1);
    expect(
      concurrent.filter((item) => item.status === "rejected"),
    ).toHaveLength(1);
    await expect(
      internalContext.getNote(
        { userId: linkedUserId, role: "client" },
        { type: "student", id: studentId },
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);

    const finalNote = await internalContext.getNote(
      { userId: directorId, role: "director" },
      { type: "student", id: studentId },
    );
    expect(finalNote).toMatchObject({ id: noteId, version: 2 });
    await internalContext.updateNote(
      { userId: adminId, role: "admin" },
      { type: "student", id: studentId },
      { expectedVersion: 2, body: "Администратор зафиксировал общий контекст" },
    );
    await new AuditService(database).record({
      actor: { userId: adminId, role: "admin" },
      action: "crm.client_blacklisted",
      entityType: "lead",
      entityId: leadId,
      metadata: { reason: "Повторяющийся спам" },
    });
    await new AuditService(database).record({
      actor: { userId: adminId, role: "admin" },
      action: "crm.client_unblacklisted",
      entityType: "lead",
      entityId: leadId,
      metadata: { reason: null },
    });
    const historyComment = await database.query<{ id: string }>(
      `insert into app.entity_comments (
         entity_type, entity_id, author_id, body, kind, shared_with_teacher
       ) values ('student', $1, $2, 'PRIVATE-HISTORY-COMMENT', 'teacher_note', true)
       returning id`,
      [studentId, adminId],
    );
    historyCommentId = historyComment.rows[0]!.id;
    await new AuditService(database).record({
      actor: { userId: adminId, role: "admin" },
      action: "crm.comment_created",
      entityType: "student",
      entityId: studentId,
      metadata: { commentId: historyCommentId },
    });
    await database.query(
      `insert into app.audit_events (
         actor_user_id, action, entity_type, entity_id, reason,
         before_ref, after_ref
       ) values (
         $1, 'crm.comment_teacher_sharing_changed', 'crm:comment', $2,
         'crm.comment.teacher-sharing',
         '{"sharedWithTeacher":false,"version":1}'::jsonb,
         '{"sharedWithTeacher":true,"version":2}'::jsonb
       )`,
      [adminId, historyCommentId],
    );
    const historyTask = await database.query<{ id: string }>(
      `insert into app.shared_tasks (
         title, body, all_day, start_at, linked_entity_type,
         linked_entity_id, created_by
       ) values (
         'Проверить карточку', null, true, now(), 'student', $1, $2
       ) returning id`,
      [studentId, adminId],
    );
    historyTaskId = historyTask.rows[0]!.id;
    await new AuditService(database).record({
      actor: { userId: adminId, role: "admin" },
      action: "workflow.shared_task_created",
      entityType: "shared_task",
      entityId: historyTaskId,
    });
    await new AuditService(database).record({
      actor: { userId: adminId, role: "admin" },
      action: "crm.lead_converted",
      entityType: "lead",
      entityId: leadId,
      metadata: { studentId },
    });
    const history = await internalContext.listOperationalHistory(
      { userId: directorId, role: "director" },
      { type: "student", id: studentId },
      { limit: 30 },
    );
    const exactEvents = [
      {
          actionKey: "crm.client_internal_note_changed",
          title: "Общая заметка изменена",
          actor: { id: adminId, name: "Анна Администратор", role: "admin" },
          target: {
            type: "client_internal_note",
            id: noteId,
            label: "Общая заметка клиента",
            displayName: null,
            routeType: null,
          },
          changes: [],
          summary: "Общая заметка обновлена",
          reason: null,
      },
      {
          actionKey: "crm.client_blacklisted",
          title: "Клиент добавлен в чёрный список",
          actor: { id: adminId, name: "Анна Администратор", role: "admin" },
          target: {
            type: "lead",
            id: leadId,
            label: "Лид",
            displayName: "Старое Имя",
            routeType: "lead",
          },
          changes: [],
          summary: "Повторяющийся спам",
          reason: null,
      },
      {
          actionKey: "crm.client_unblacklisted",
          title: "Клиент убран из чёрного списка",
          actor: { id: adminId, name: "Анна Администратор", role: "admin" },
          target: {
            type: "lead",
            id: leadId,
            label: "Лид",
            displayName: "Старое Имя",
            routeType: "lead",
          },
          changes: [],
          summary: null,
          reason: null,
      },
      {
          actionKey: "crm.lead_converted",
          title: "Лид конвертирован в ученика",
          actor: { id: adminId, name: "Анна Администратор", role: "admin" },
          target: {
            type: "lead",
            id: leadId,
            label: "Лид",
            displayName: "Старое Имя",
            routeType: "lead",
          },
          changes: [],
          summary: null,
          reason: null,
      },
      {
          actionKey: "crm.comment_created",
          title: "Комментарий добавлен",
          actor: { id: adminId, name: "Анна Администратор", role: "admin" },
          target: {
            type: "student",
            id: studentId,
            label: "Ученик",
            displayName: "Обновлённое Ученик",
            routeType: "student",
          },
          changes: [],
          summary: null,
          reason: null,
      },
      {
          actionKey: "crm.comment_teacher_sharing_changed",
          title: "Видимость комментария изменена",
          actor: { id: adminId, name: "Анна Администратор", role: "admin" },
          target: {
            type: "comment",
            id: historyCommentId,
            label: "Комментарий",
            displayName: null,
            routeType: "comment",
          },
          changes: [
            {
              key: "sharedWithTeacher",
              label: "Доступ преподавателя",
              before: "Нет",
              after: "Да",
            },
          ],
          reason: "Комментарий опубликован преподавателю",
          summary: "Опубликован преподавателю",
      },
      {
          actionKey: "workflow.shared_task_created",
          title: "Задача создана",
          actor: { id: adminId, name: "Анна Администратор", role: "admin" },
          target: {
            type: "task",
            id: historyTaskId,
            label: "Задача",
            displayName: null,
            routeType: "task",
          },
          changes: [],
          summary: null,
          reason: null,
      },
    ];
    for (const expected of exactEvents) {
      const event = history.items.find((item) => item.actionKey === expected.actionKey);
      expect(event).toBeDefined();
      const { id, occurredAt } = event!;
      expect(id).toEqual(expect.any(String));
      expect(id.trim()).not.toBe("");
      expect(occurredAt instanceof Date || typeof occurredAt === "string").toBe(true);
      expect(new Date(occurredAt).toString()).not.toBe("Invalid Date");
      expect(event).toEqual({ id, ...expected, occurredAt });
      expect(event).not.toHaveProperty("action");
      expect(event).not.toHaveProperty("actorName");
      expect(event).not.toHaveProperty("actorRole");
      expect(event).not.toHaveProperty("entityType");
      expect(event).not.toHaveProperty("entityId");
      expect(event).not.toHaveProperty("targetType");
      expect(event).not.toHaveProperty("targetId");
      expect(event).not.toHaveProperty("targetLabel");
      expect(event).not.toHaveProperty("targetDisplayName");
      expect(event).not.toHaveProperty("routeType");
      expect(event).not.toHaveProperty("metadata");
      expect(event).not.toHaveProperty("beforeRef");
      expect(event).not.toHaveProperty("afterRef");
      expect(event).not.toHaveProperty("reasonText");
      expect(event).not.toHaveProperty("createdAt");
      expect(event).not.toHaveProperty("version");
    }
    expect(JSON.stringify(history)).not.toContain("PRIVATE-HISTORY-COMMENT");

    await expect(
      archives.archiveConvertedLead(
        { userId: managerId, role: "manager" },
        leadId,
        {
          expectedVersion: 2,
          confirm: true,
          reason: "conversion.complete",
        },
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);
    await expect(
      archives.archiveConvertedLead(
        { userId: directorId, role: "director" },
        leadId,
        {
          expectedVersion: 2,
          confirm: true,
          reason: "conversion.complete",
        },
      ),
    ).resolves.toMatchObject({ studentId, archived: true });
    const preserved = await database.query<{
      lead_archived: boolean;
      student_active: boolean;
    }>(
      `
        select
          (select deleted_at is not null from app.leads where id = $1)
            as lead_archived,
          (select deleted_at is null from app.students where id = $2)
            as student_active
      `,
      [leadId, studentId],
    );
    expect(preserved.rows[0]).toEqual({
      lead_archived: true,
      student_active: true,
    });
  });
});
