import { BadRequestException, ForbiddenException } from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { Pool, PoolClient } from "pg";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { MigrationRunner } from "../db/migration-runner";
import { CrmPolicy } from "./crm.policy";
import { LeadWriteRepository } from "./lead-write.repository";
import { PhoneReviewService } from "./phone-review.service";
import { StudentMutationExecutor } from "./students/student-mutation.executor";

const databaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ??
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(
    new URL(databaseUrl).hostname,
  )
) {
  throw new Error("Phone review tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("Phone review lifecycle (PostgreSQL)", () => {
  let pool: Pool;
  let client: PoolClient;
  let service: PhoneReviewService;
  let leadWrites: LeadWriteRepository;
  let studentWrites: StudentMutationExecutor;
  let actor: ActorContext;
  let leadId: string;
  let profileId: string;
  let studentId: string;
  let leadQueueId: string;
  let profileQueueId: string;

  beforeAll(async () => {
    pool = new Pool({ connectionString: databaseUrl });
    await new MigrationRunner(pool).up();
    client = await pool.connect();
    await client.query("begin");

    actor = { userId: randomUUID(), role: "manager" };
    const profileUserId = randomUUID();
    leadId = randomUUID();
    profileId = randomUUID();
    studentId = randomUUID();
    leadQueueId = randomUUID();
    profileQueueId = randomUUID();
    const suffix = randomUUID();
    await client.query(
      `
        insert into app.users (id, email, role, profile_completed)
        values
          ($1, $2, 'manager', true),
          ($3, $4, 'client', true)
      `,
      [
        actor.userId,
        `uat115-phone-manager-${suffix}@test.local`,
        profileUserId,
        `uat115-phone-client-${suffix}@test.local`,
      ],
    );
    await client.query(
      `insert into app.leads (id, first_name, phone, custom_data)
       values ($1, 'Очередь', '123', '{"keep":"lead","remove":"old"}'::jsonb)`,
      [leadId],
    );
    await client.query(
      `insert into app.profiles (id, user_id, first_name, phone)
       values ($1, $2, 'Иностранный', '+1 212 555 0100')`,
      [profileId, profileUserId],
    );
    await client.query(
      `insert into app.students (id, profile_id, status, custom_data)
       values ($1, $2, 'active', '{"keep":"student","remove":"old"}'::jsonb)`,
      [studentId, profileId],
    );
    await client.query(
      `
        insert into app.phone_review_queue (
          id, entity_type, entity_id, raw_phone, reason
        ) values
          ($1, 'lead', $2, '123', 'too_short'),
          ($3, 'profile', $4, '+1 212 555 0100', 'non_ru')
      `,
      [leadQueueId, leadId, profileQueueId, profileId],
    );

    const database = {
      query: (text: string, params?: unknown[]) => client.query(text, params),
      transaction: <T>(work: (transactionClient: PoolClient) => Promise<T>) =>
        work(client),
    } as unknown as DatabaseService;
    service = new PhoneReviewService(
      database,
      new CrmPolicy(),
      new AuditService(database),
    );
    leadWrites = new LeadWriteRepository(database, {
      assertLeadTransition: jest.fn(),
    } as never);
    studentWrites = new StudentMutationExecutor(database, {
      assertCreateStatus: jest.fn(),
      assertTransition: jest.fn(),
    } as never);
  });

  afterAll(async () => {
    await client.query("rollback");
    client.release();
    await pool.end();
  });

  it("corrects or explicitly accepts source values with accountable outcomes", async () => {
    await expect(service.countPhoneReviewQueue(actor)).resolves.toEqual({
      count: expect.any(Number),
    });
    await expect(
      service.resolvePhoneReview(actor, leadQueueId, {
        action: "corrected",
        phone: "8 (999) 123-45-67",
        resolutionNote: "Подтверждено по карточке клиента",
      }),
    ).resolves.toMatchObject({
      action: "corrected",
      resolvedPhone: "+79991234567",
    });
    await expect(
      service.resolvePhoneReview(actor, profileQueueId, {
        action: "accepted_as_is",
        resolutionNote: "Подтверждён иностранный номер",
      }),
    ).resolves.toMatchObject({
      action: "accepted_as_is",
      resolvedPhone: null,
    });

    const facts = await client.query<{
      lead_phone: string;
      lead_normalized: string;
      lead_version: string;
      profile_phone: string;
      profile_normalized: string | null;
      student_version: string;
      corrected_action: string;
      corrected_note: string;
      corrected_phone: string;
      accepted_action: string;
      accepted_note: string;
      accepted_phone: string | null;
      unresolved: string;
      audits: string;
    }>(
      `
        select
          l.phone as lead_phone,
          l.phone_normalized as lead_normalized,
          l.version::text as lead_version,
          p.phone as profile_phone,
          p.phone_normalized as profile_normalized,
          s.version::text as student_version,
          lead_q.resolution_action as corrected_action,
          lead_q.resolution_note as corrected_note,
          lead_q.resolved_phone as corrected_phone,
          profile_q.resolution_action as accepted_action,
          profile_q.resolution_note as accepted_note,
          profile_q.resolved_phone as accepted_phone,
          (select count(*)::text from app.phone_review_queue
            where id in ($1, $2) and resolved_at is null) as unresolved,
          (select count(*)::text from app.audit_events
            where action = 'crm.phone_review_resolved'
              and entity_id in ($1::text, $2::text)) as audits
        from app.leads l
        join app.profiles p on p.id = $3
        join app.students s on s.id = $5
        join app.phone_review_queue lead_q on lead_q.id = $1
        join app.phone_review_queue profile_q on profile_q.id = $2
        where l.id = $4
      `,
      [leadQueueId, profileQueueId, profileId, leadId, studentId],
    );
    expect(facts.rows[0]).toEqual({
      lead_phone: "+79991234567",
      lead_normalized: "+79991234567",
      lead_version: "2",
      profile_phone: "+1 212 555 0100",
      profile_normalized: null,
      student_version: "1",
      corrected_action: "corrected",
      corrected_note: "Подтверждено по карточке клиента",
      corrected_phone: "+79991234567",
      accepted_action: "accepted_as_is",
      accepted_note: "Подтверждён иностранный номер",
      accepted_phone: null,
      unresolved: "0",
      audits: "2",
    });

    await expect(
      leadWrites.update(actor, leadId, {
        expectedVersion: 1,
        firstName: "Устаревшая запись",
      }),
    ).rejects.toMatchObject({
      response: expect.objectContaining({ code: "CLIENT_VERSION_CONFLICT" }),
    });
  });

  it("invalidates stale Student writes and applies JSON-null tombstones", async () => {
    await client.query(
      `update app.phone_review_queue
          set raw_phone = '123', reason = 'too_short', resolved_at = null,
              resolved_by = null, resolution_action = null,
              resolution_note = null, resolved_phone = null
        where id = $1`,
      [profileQueueId],
    );

    await service.resolvePhoneReview(actor, profileQueueId, {
      action: "corrected",
      phone: "+7 999 555-44-33",
      resolutionNote: "Исправлено по карточке ученика",
    });
    await expect(
      studentWrites.update({
        studentId,
        expectedVersion: 1,
        firstName: "Устаревшая запись",
        lastName: null,
        phone: null,
        email: null,
        status: null,
        customDataPatch: {},
        requestedResponsibleId: undefined,
        branchId: null,
        clearResponsible: false,
        sourceId: null,
      }),
    ).rejects.toMatchObject({
      response: expect.objectContaining({ code: "CLIENT_VERSION_CONFLICT" }),
    });

    const leadVersion = await client.query<{ version: number }>(
      "select version from app.leads where id = $1",
      [leadId],
    );
    await leadWrites.update(actor, leadId, {
      expectedVersion: Number(leadVersion.rows[0]!.version),
      customDataPatch: { remove: null, added: "lead" },
    });
    const studentVersion = await client.query<{ version: number }>(
      "select version from app.students where id = $1",
      [studentId],
    );
    await studentWrites.update({
      studentId,
      expectedVersion: Number(studentVersion.rows[0]!.version),
      firstName: null,
      lastName: null,
      phone: null,
      email: null,
      status: null,
      customDataPatch: { remove: null, added: "student" },
      requestedResponsibleId: undefined,
      branchId: null,
      clearResponsible: false,
      sourceId: null,
    });

    const facts = await client.query<{
      lead_custom_data: Record<string, unknown>;
      student_custom_data: Record<string, unknown>;
    }>(
      `select l.custom_data as lead_custom_data,
              s.custom_data as student_custom_data
         from app.leads l
         join app.students s on s.id = $2
        where l.id = $1`,
      [leadId, studentId],
    );
    expect(facts.rows[0]).toEqual({
      lead_custom_data: { keep: "lead", added: "lead" },
      student_custom_data: { keep: "student", added: "student" },
    });
  });

  it("rejects invalid corrected phones and non-staff writers", async () => {
    await expect(
      service.resolvePhoneReview(actor, randomUUID(), {
        action: "corrected",
        phone: "123",
        resolutionNote: "Некорректная попытка",
      }),
    ).rejects.toThrow(BadRequestException);
    await expect(
      service.resolvePhoneReview(
        { userId: randomUUID(), role: "teacher" },
        randomUUID(),
        {
          action: "accepted_as_is",
          resolutionNote: "Нет права решения",
        },
      ),
    ).rejects.toThrow(ForbiddenException);
  });
});
