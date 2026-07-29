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
  let branchId: string;
  let leadId: string;
  let linkedUserId: string;
  let managerId: string;
  let directorId: string;
  let leadDefinitionId: string;
  let studentDefinitionId: string;
  let studentId: string;

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
      { record: jest.fn().mockResolvedValue(undefined) } as unknown as AuditService,
      { emitCrmChanged: jest.fn() } as unknown as RealtimeBus,
    );
    archives = new ClientArchiveService(
      database,
      new PlatformIntegrityService(
        database,
        new PlatformIntegrityRepository(),
      ),
      new CrmPolicy(),
      { emitCrmChanged: jest.fn() } as unknown as RealtimeBus,
    );

    const branch = await database.query<{ id: string }>(
      "insert into app.branches (name) values ($1) returning id",
      [`Conversion ${randomUUID()}`],
    );
    branchId = branch.rows[0]!.id;
    const users = await database.query<{ id: string; role: string }>(
      `
        insert into app.users (email, role, email_verified_at)
        values
          ($1, 'manager', now()),
          ($2, 'director', now()),
          ($3, 'client', now())
        returning id, role::text as role
      `,
      [
        `conversion-manager-${randomUUID()}@example.test`,
        `conversion-director-${randomUUID()}@example.test`,
        `conversion-client-${randomUUID()}@example.test`,
      ],
    );
    managerId = users.rows.find((row) => row.role === "manager")!.id;
    directorId = users.rows.find((row) => row.role === "director")!.id;
    linkedUserId = users.rows.find((row) => row.role === "client")!.id;
    const lead = await database.query<{ id: string }>(
      `
        insert into app.leads (
          first_name, last_name, phone, custom_data, branch_id, created_by
        )
        values (
          'Старое', 'Имя', '+79990000000',
          '{"legacy":"preserved"}'::jsonb, $1, $2
        )
        returning id
      `,
      [branchId, managerId],
    );
    leadId = lead.rows[0]!.id;
    await database.query(
      `
        insert into app.user_crm_links (
          user_id, entity_type, entity_id, link_source, created_by, confirmed_at
        )
        values ($1, 'lead', $2, 'manual_phone', $3, now())
      `,
      [linkedUserId, leadId, managerId],
    );
    const definitions = await database.query<{
      id: string;
      entity_type: string;
    }>(
      `
        insert into app.client_custom_field_definitions (
          entity_type, field_key, label, value_type
        )
        values
          ('lead', $1, 'Общее поле', 'text'),
          ('student', $1, 'Общее поле', 'text')
        returning id, entity_type
      `,
      [`shared_${randomUUID().replace(/-/g, "")}`],
    );
    leadDefinitionId = definitions.rows.find(
      (row) => row.entity_type === "lead",
    )!.id;
    studentDefinitionId = definitions.rows.find(
      (row) => row.entity_type === "student",
    )!.id;
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
      await database.query("delete from app.students where id = $1", [studentId]);
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
    await database.query(
      "delete from app.client_custom_field_definitions where id = any($1::uuid[])",
      [[leadDefinitionId, studentDefinitionId]],
    );
    await database.query("delete from app.branches where id = $1", [branchId]);
    await database.query(
      "delete from app.users where id = any($1::uuid[])",
      [[managerId, directorId, linkedUserId]],
    );
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
    expect([left.replayed, right.replayed].sort()).toEqual([false, true]);

    const facts = await database.query<{
      students: string;
      links: string;
      crm_links: string;
      copied_value: string;
      legacy_value: string;
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
            where id = $2) as legacy_value
      `,
      [leadId, studentId, linkedUserId, studentDefinitionId],
    );
    expect(facts.rows[0]).toEqual({
      students: "1",
      links: "1",
      crm_links: "1",
      copied_value: "перенесено",
      legacy_value: "preserved",
    });

    await expect(
      archives.archiveConvertedLead(
        { userId: managerId, role: "manager" },
        leadId,
        {
          expectedVersion: 1,
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
          expectedVersion: 1,
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
