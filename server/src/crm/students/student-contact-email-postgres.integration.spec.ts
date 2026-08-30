import { createHash, randomUUID } from "node:crypto";
import { Pool, PoolClient } from "pg";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { linkInvitedStudentsByVerifiedEmail } from "../../auth/student-invitation-linker";
import { LeadWriteRepository } from "../lead-write.repository";
import type { UpdateLeadDto } from "../dto/upsert-lead.dto";
import { findStudent } from "../student-read";
import type { StudentFunnelService } from "../student-funnel.service";
import { NotificationWorker } from "../../notifications/notification-worker.service";
import { StudentCommandService } from "./student-command.service";
import { StudentMutationExecutor } from "./student-mutation.executor";
import type { PreparedStudentUpdate } from "./student-mutation.types";

const databaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ??
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(
    new URL(databaseUrl).hostname,
  )
) {
  throw new Error("Student contact email tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("Student contact email (PostgreSQL)", () => {
  let pool: Pool;
  let client: PoolClient;
  let executor: StudentMutationExecutor;
  let database: DatabaseService;

  beforeAll(async () => {
    pool = new Pool({ connectionString: databaseUrl });
    await new MigrationRunner(pool).up();
    client = await pool.connect();
    await client.query("begin");
    database = {
      query: (text: string, params?: unknown[]) => client.query(text, params),
      transaction: <T>(work: (transactionClient: PoolClient) => Promise<T>) =>
        work(client),
    } as unknown as DatabaseService;
    executor = new StudentMutationExecutor(database, {
      assertCreateStatus: jest.fn(),
      assertTransition: jest.fn(),
    } as unknown as StudentFunnelService);
  });

  afterAll(async () => {
    await client.query("rollback");
    client.release();
    await pool.end();
  });

  it("stores a duplicate login email as a client contact without changing identities", async () => {
    const technicalUserId = randomUUID();
    const existingAppUserId = randomUUID();
    const changedAppUserId = randomUUID();
    const profileId = randomUUID();
    const studentId = randomUUID();
    const suffix = randomUUID();
    const technicalEmail = `student-${suffix}@local.magicmusiccrm.invalid`;
    const contactEmail = `client-${suffix}@example.test`;
    const changedContactEmail = `changed-${suffix}@example.test`;

    await client.query(
      `insert into app.users (id, email, role, is_app_account)
       values ($1, $2, 'client', false),
         ($3, $4, 'client', true),
         ($5, $6, 'client', true)`,
      [
        technicalUserId,
        technicalEmail,
        existingAppUserId,
        contactEmail,
        changedAppUserId,
        changedContactEmail,
      ],
    );
    await client.query(
      `insert into app.profiles (id, user_id, first_name, last_name)
       values ($1, $2, 'Мария', 'Тестова')`,
      [profileId, technicalUserId],
    );
    const inserted = await client.query<{ version: string | number }>(
      `insert into app.students (id, client_id, profile_id, status)
       values ($1, $1, $2, 'active')
       returning version`,
      [studentId, profileId],
    );
    const versionBefore = Number(inserted.rows[0]!.version);
    const command: PreparedStudentUpdate = {
      studentId,
      expectedVersion: versionBefore,
      firstName: null,
      lastName: null,
      phone: null,
      email: contactEmail,
      status: null,
      customDataPatch: {},
      requestedResponsibleId: undefined,
      branchId: null,
      clearResponsible: false,
      sourceId: null,
    };

    const result = await executor.update(command);

    expect(result.student?.email).toBe(contactEmail);
    const state = await client.query<{
      contact_email: string | null;
      version: string | number;
      technical_email: string;
      existing_email: string;
      link_count: string;
    }>(
      `select student.contact_email, student.version,
         technical.email as technical_email,
         existing.email as existing_email,
         (select count(*)::text from app.user_crm_links link
           where link.entity_type = 'student'
             and link.entity_id = student.id
             and link.deleted_at is null) as link_count
       from app.students student
       join app.users technical on technical.id = $2
       join app.users existing on existing.id = $3
       where student.id = $1`,
      [studentId, technicalUserId, existingAppUserId],
    );
    expect(state.rows[0]).toEqual({
      contact_email: contactEmail,
      version: String(versionBefore + 1),
      technical_email: technicalEmail,
      existing_email: contactEmail,
      link_count: "0",
    });

    await client.query(
      `insert into app.email_outbox (
         user_id, to_email_hash, template, recipient_student_id
       ) values ($1, $2, 'student_invite', $3)`,
      [
        technicalUserId,
        createHash("sha256").update(contactEmail).digest("hex"),
        studentId,
      ],
    );
    await client.query(
      "update app.students set contact_email = $2 where id = $1",
      [studentId, changedContactEmail],
    );

    await expect(
      linkInvitedStudentsByVerifiedEmail(
        database,
        changedAppUserId,
        changedContactEmail,
      ),
    ).resolves.toEqual([]);

    await client.query(
      `insert into app.email_outbox (
         user_id, to_email_hash, template, recipient_student_id
       ) values ($1, $2, 'student_invite', $3)`,
      [
        technicalUserId,
        createHash("sha256").update(changedContactEmail).digest("hex"),
        studentId,
      ],
    );

    await expect(
      linkInvitedStudentsByVerifiedEmail(
        database,
        changedAppUserId,
        changedContactEmail.toUpperCase(),
      ),
    ).resolves.toEqual([studentId]);
    const linked = await client.query<{ user_id: string; link_source: string }>(
      `select user_id, link_source
       from app.user_crm_links
       where entity_type = 'student'
         and entity_id = $1
         and deleted_at is null`,
      [studentId],
    );
    expect(linked.rows).toEqual([
      { user_id: changedAppUserId, link_source: "auto_email" },
    ]);
  });

  it("preserves omitted contact email and clears it only when explicitly requested", async () => {
    const accountUserId = randomUUID();
    const profileId = randomUUID();
    const studentId = randomUUID();
    const suffix = randomUUID();
    const loginEmail = `login-${suffix}@example.test`;
    const contactEmail = `contact-${suffix}@example.test`;

    await client.query(
      `insert into app.users (id, email, role, is_app_account)
       values ($1, $2, 'client', true)`,
      [accountUserId, loginEmail],
    );
    await client.query(
      `insert into app.profiles (id, user_id, first_name, last_name)
       values ($1, $2, 'Анна', 'Тестова')`,
      [profileId, accountUserId],
    );
    const inserted = await client.query<{ version: string | number }>(
      `insert into app.students (
         id, client_id, profile_id, status, contact_email
       ) values ($1, $1, $2, 'active', $3)
       returning version`,
      [studentId, profileId, contactEmail],
    );
    const versionBefore = Number(inserted.rows[0]!.version);
    const baseCommand = {
      studentId,
      firstName: null,
      lastName: null,
      phone: null,
      email: null,
      status: null,
      customDataPatch: {},
      requestedResponsibleId: undefined,
      branchId: null,
      clearResponsible: false,
      sourceId: null,
    } satisfies Omit<PreparedStudentUpdate, "expectedVersion">;

    await executor.update({ ...baseCommand, expectedVersion: versionBefore });
    const preserved = await client.query<{ contact_email: string | null }>(
      "select contact_email from app.students where id = $1",
      [studentId],
    );
    expect(preserved.rows[0]?.contact_email).toBe(contactEmail);

    const cleared = await executor.update({
      ...baseCommand,
      expectedVersion: versionBefore + 1,
      clearEmail: true,
    } as PreparedStudentUpdate & { clearEmail: boolean });

    expect(cleared.student?.email).toBeNull();
    const state = await client.query<{ contact_email: string | null }>(
      "select contact_email from app.students where id = $1",
      [studentId],
    );
    expect(state.rows[0]?.contact_email).toBeNull();
    await expect(findStudent(database, studentId)).resolves.toEqual(
      expect.objectContaining({ email: null }),
    );

    const notifications = { sendEmail: jest.fn() };
    const commands = new StudentCommandService(
      database,
      { record: jest.fn() } as never,
      { assertCanWriteCrm: jest.fn() } as never,
      notifications as never,
      { emitCrmChanged: jest.fn() } as never,
      executor,
    );
    await expect(
      commands.inviteStudent(
        { userId: accountUserId, role: "admin" },
        studentId,
      ),
    ).rejects.toThrow("У ученика нет email для приглашения.");
    expect(notifications.sendEmail).not.toHaveBeenCalled();
    const outbox = await client.query<{ count: string }>(
      `select count(*)::text as count from app.email_outbox
       where recipient_student_id = $1`,
      [studentId],
    );
    expect(outbox.rows[0]?.count).toBe("0");
  });

  it("preserves an omitted lead email and clears it only when explicitly requested", async () => {
    const actorUserId = randomUUID();
    const leadId = randomUUID();
    const suffix = randomUUID();
    const contactEmail = `lead-${suffix}@example.test`;
    await client.query(
      `insert into app.users (id, email, role, is_app_account)
       values ($1, $2, 'admin', true)`,
      [actorUserId, `admin-${suffix}@example.test`],
    );
    const inserted = await client.query<{ version: string | number }>(
      `insert into app.leads (id, first_name, email, created_by)
       values ($1, 'Мария', $2, $3)
       returning version`,
      [leadId, contactEmail, actorUserId],
    );
    const writes = new LeadWriteRepository(database, {
      assertLeadTransition: jest.fn(),
    } as never);

    await writes.update(
      { userId: actorUserId, role: "admin" },
      leadId,
      { expectedVersion: Number(inserted.rows[0]!.version) },
    );
    const preserved = await client.query<{ email: string | null }>(
      "select email from app.leads where id = $1",
      [leadId],
    );
    expect(preserved.rows[0]?.email).toBe(contactEmail);

    await writes.update(
      { userId: actorUserId, role: "admin" },
      leadId,
      {
        expectedVersion: Number(inserted.rows[0]!.version) + 1,
        clearEmail: true,
      } as UpdateLeadDto & { clearEmail: boolean },
    );
    const cleared = await client.query<{ email: string | null }>(
      "select email from app.leads where id = $1",
      [leadId],
    );
    expect(cleared.rows[0]?.email).toBeNull();
  });

  it("never sends a stale student invitation after the card email changes", async () => {
    const userId = randomUUID();
    const profileId = randomUUID();
    const studentId = randomUUID();
    const suffix = randomUUID();
    const oldEmail = `old-${suffix}@example.test`;
    const currentEmail = `current-${suffix}@example.test`;
    await client.query(
      `insert into app.users (id, email, role, is_app_account)
       values ($1, $2, 'client', true)`,
      [userId, `login-${suffix}@example.test`],
    );
    await client.query(
      `insert into app.profiles (id, user_id, first_name)
       values ($1, $2, 'Ольга')`,
      [profileId, userId],
    );
    await client.query(
      `insert into app.students (
         id, client_id, profile_id, status, contact_email
       ) values ($1, $1, $2, 'active', $3)`,
      [studentId, profileId, currentEmail],
    );
    const inserted = await client.query<{ id: string }>(
      `insert into app.email_outbox (
         user_id, to_email_hash, template, recipient_student_id, payload
       ) values ($1, $2, 'student_invite', $3, $4::jsonb)
       returning id`,
      [
        userId,
        createHash("sha256").update(oldEmail).digest("hex"),
        studentId,
        JSON.stringify({ title: "Приглашение", body: "Установите приложение" }),
      ],
    );
    const resend = {
      send: jest.fn().mockResolvedValue({ provider: "resend", status: "sent" }),
    };
    const smtp = { send: jest.fn() };
    const worker = new NotificationWorker(
      database,
      { record: jest.fn() } as never,
      resend as never,
      smtp as never,
      { decrypt: jest.fn() } as never,
      { send: jest.fn() } as never,
    );

    await expect(worker.dispatchEmailById(inserted.rows[0]!.id)).resolves.toEqual({
      processed: true,
      status: "failed",
    });
    expect(resend.send).not.toHaveBeenCalled();
    expect(smtp.send).not.toHaveBeenCalled();
    const state = await client.query<{
      status: string;
      attempt_count: string | number;
      last_error: string | null;
    }>(
      `select status, attempt_count, last_error
       from app.email_outbox where id = $1`,
      [inserted.rows[0]!.id],
    );
    expect(state.rows[0]).toEqual({
      status: "failed",
      attempt_count: 5,
      last_error: "recipient_contact_changed",
    });

    await client.query(
      "update app.students set contact_email = null where id = $1",
      [studentId],
    );
    const clearedRecipient = await client.query<{ id: string }>(
      `insert into app.email_outbox (
         user_id, to_email_hash, template, recipient_student_id, payload
       ) values ($1, $2, 'student_invite', $3, $4::jsonb)
       returning id`,
      [
        userId,
        createHash("sha256").update(oldEmail).digest("hex"),
        studentId,
        JSON.stringify({ title: "Приглашение", body: "Установите приложение" }),
      ],
    );
    resend.send.mockClear();
    smtp.send.mockClear();

    await expect(
      worker.dispatchEmailById(clearedRecipient.rows[0]!.id),
    ).resolves.toEqual({ processed: true, status: "failed" });
    expect(resend.send).not.toHaveBeenCalled();
    expect(smtp.send).not.toHaveBeenCalled();
    const clearedState = await client.query<{
      status: string;
      attempt_count: string | number;
      last_error: string | null;
    }>(
      `select status, attempt_count, last_error
       from app.email_outbox where id = $1`,
      [clearedRecipient.rows[0]!.id],
    );
    expect(clearedState.rows[0]).toEqual({
      status: "failed",
      attempt_count: 5,
      last_error: "recipient_contact_changed",
    });
  });

  it("sends a student invitation only to the current matching card email", async () => {
    const userId = randomUUID();
    const profileId = randomUUID();
    const studentId = randomUUID();
    const suffix = randomUUID();
    const currentEmail = `current-${suffix}@example.test`;
    await client.query(
      `insert into app.users (id, email, role, is_app_account)
       values ($1, $2, 'client', true)`,
      [userId, `login-${suffix}@example.test`],
    );
    await client.query(
      `insert into app.profiles (id, user_id, first_name)
       values ($1, $2, 'Ирина')`,
      [profileId, userId],
    );
    await client.query(
      `insert into app.students (
         id, client_id, profile_id, status, contact_email
       ) values ($1, $1, $2, 'active', $3)`,
      [studentId, profileId, currentEmail],
    );
    const inserted = await client.query<{ id: string }>(
      `insert into app.email_outbox (
         user_id, to_email_hash, template, recipient_student_id, payload
       ) values ($1, $2, 'student_invite', $3, $4::jsonb)
       returning id`,
      [
        userId,
        createHash("sha256").update(currentEmail).digest("hex"),
        studentId,
        JSON.stringify({ title: "Приглашение", body: "Установите приложение" }),
      ],
    );
    const resend = {
      send: jest.fn().mockResolvedValue({ provider: "resend", status: "sent" }),
    };
    const worker = new NotificationWorker(
      database,
      { record: jest.fn() } as never,
      resend as never,
      { send: jest.fn() } as never,
      { decrypt: jest.fn() } as never,
      { send: jest.fn() } as never,
    );

    await expect(worker.dispatchEmailById(inserted.rows[0]!.id)).resolves.toEqual({
      processed: true,
      status: "sent",
    });
    expect(resend.send).toHaveBeenCalledWith(
      expect.objectContaining({ to: currentEmail }),
    );
  });
});
