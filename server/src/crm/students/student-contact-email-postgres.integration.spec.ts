import { createHash, randomUUID } from "node:crypto";
import { Pool, PoolClient } from "pg";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { linkInvitedStudentsByVerifiedEmail } from "../../auth/student-invitation-linker";
import type { StudentFunnelService } from "../student-funnel.service";
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
});
