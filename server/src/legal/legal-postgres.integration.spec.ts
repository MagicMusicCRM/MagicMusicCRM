import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
} from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { Pool, PoolClient } from "pg";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { MigrationRunner } from "../db/migration-runner";
import { LegalPolicy } from "./legal.policy";
import { LegalService } from "./legal.service";

const databaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ??
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(
    new URL(databaseUrl).hostname,
  )
) {
  throw new Error("Legal lifecycle tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("Account deletion lifecycle (PostgreSQL)", () => {
  let pool: Pool;
  let client: PoolClient;
  let legal: LegalService;
  let clientActor: ActorContext;
  let manager: ActorContext;
  let director: ActorContext;
  let ownerUserId: string;

  beforeAll(async () => {
    pool = new Pool({ connectionString: databaseUrl });
    await new MigrationRunner(pool).up();
    client = await pool.connect();
    await client.query("begin");

    clientActor = { userId: randomUUID(), role: "client" };
    manager = { userId: randomUUID(), role: "manager" };
    director = { userId: randomUUID(), role: "director" };
    ownerUserId = randomUUID();
    const suffix = randomUUID();
    await client.query(
      `
        insert into app.users (
          id, email, password_hash, full_name, phone, role, profile_completed
        )
        values
          ($1, $2, 'client-password-sentinel', 'UAT Клиент', '+79991234567', 'client', true),
          ($3, $4, 'manager-password-sentinel', 'UAT Управляющий', null, 'manager', true),
          ($5, $6, 'director-password-sentinel', 'UAT Директор', null, 'director', true),
          ($7, $8, 'owner-password-sentinel', 'Owner Sentinel', '+79990000000', 'director', true)
      `,
      [
        clientActor.userId,
        `uat115-client-${suffix}@test.local`,
        manager.userId,
        `uat115-manager-${suffix}@test.local`,
        director.userId,
        `uat115-director-${suffix}@test.local`,
        ownerUserId,
        `uat115-owner-${suffix}@test.local`,
      ],
    );
    await client.query(
      `
        insert into app.profiles (
          user_id, first_name, last_name, phone, custom_data
        )
        values
          ($1, 'UAT', 'Клиент', '+79991234567', '{"source":"uat115"}'::jsonb),
          ($2, 'Owner', 'Sentinel', '+79990000000', '{"protected":true}'::jsonb)
      `,
      [clientActor.userId, ownerUserId],
    );
    await client.query(
      `
        insert into app.user_identities (
          user_id, provider, provider_user_id, email, email_verified
        ) values ($1, 'google', $2, $3, true)
      `,
      [
        clientActor.userId,
        `uat115-google-${suffix}`,
        `uat115-client-${suffix}@test.local`,
      ],
    );
    await client.query(
      `insert into app.notification_devices (user_id, platform, token_hash)
       values ($1, 'windows', $2)`,
      [clientActor.userId, `uat115-device-${suffix}`],
    );
    await client.query(
      `insert into app.password_reset_tokens (user_id, token_hash, expires_at)
       values ($1, $2, now() + interval '1 hour')`,
      [clientActor.userId, `uat115-reset-${suffix}`],
    );
    await client.query(
      `insert into app.email_verification_tokens (user_id, token_hash, expires_at)
       values ($1, $2, now() + interval '1 hour')`,
      [clientActor.userId, `uat115-email-${suffix}`],
    );
    await client.query(
      `insert into app.otp_challenges (
         user_id, email_hash, purpose, code_hash, expires_at
       ) values ($1, $2, 'login', $3, now() + interval '1 hour')`,
      [
        clientActor.userId,
        `uat115-email-hash-${suffix}`,
        `uat115-otp-${suffix}`,
      ],
    );
    await client.query(
      `insert into app.refresh_sessions (
         user_id, token_hash, family_id, expires_at
       ) values ($1, $2, $3, now() + interval '1 hour')`,
      [clientActor.userId, `uat115-session-${suffix}`, randomUUID()],
    );

    const database = {
      query: (text: string, params?: unknown[]) => client.query(text, params),
      transaction: <T>(work: (transactionClient: PoolClient) => Promise<T>) =>
        work(client),
    } as unknown as DatabaseService;
    legal = new LegalService(
      database,
      new AuditService(database),
      new LegalPolicy(),
    );
  });

  afterAll(async () => {
    await client.query("rollback");
    client.release();
    await pool.end();
  });

  it("keeps owner credentials intact while the UAT client consents, cancels, and is anonymized", async () => {
    const ownerBefore = await client.query(
      `
        select u.email, u.password_hash, u.full_name, u.deleted_at,
          p.first_name, p.last_name, p.phone, p.custom_data
        from app.users u
        join app.profiles p on p.user_id = u.id
        where u.id = $1
      `,
      [ownerUserId],
    );

    const documents = await legal.listCurrentDocuments();
    expect(documents.length).toBeGreaterThanOrEqual(3);
    await legal.acceptCurrentDocuments(
      clientActor,
      { documentIds: documents.map((document) => document.id) },
      { ip: "127.0.0.1", userAgent: "UAT-115 PostgreSQL" },
    );
    await expect(legal.getGate(clientActor)).resolves.toMatchObject({
      profileComplete: true,
      legalAccepted: true,
      deletionPending: false,
    });

    const first = await legal.createDeletionRequest(clientActor, {
      acknowledgement: true,
      reason: "Проверка отмены",
    });
    await expect(legal.getGate(clientActor)).resolves.toMatchObject({
      deletionPending: true,
    });
    await expect(
      legal.cancelOwnDeletionRequest(clientActor),
    ).resolves.toMatchObject({ id: first.id, status: "cancelled" });
    await expect(legal.getGate(clientActor)).resolves.toMatchObject({
      deletionPending: false,
    });

    const second = await legal.createDeletionRequest(clientActor, {
      acknowledgement: true,
      reason: "Проверка обезличивания",
    });
    await expect(
      legal.updateDeletionRequest(manager, second.id, { status: "processing" }),
    ).rejects.toThrow(ForbiddenException);
    await expect(
      legal.listDeletionRequests(manager, {}),
    ).resolves.toMatchObject({
      items: expect.arrayContaining([
        expect.objectContaining({ id: second.id, status: "pending" }),
      ]),
    });
    await expect(
      legal.updateDeletionRequest(director, second.id, {
        status: "completed",
        resolutionNote: "Нельзя миновать обработку",
      }),
    ).rejects.toThrow(ForbiddenException);

    await expect(
      legal.updateDeletionRequest(director, second.id, {
        status: "processing",
      }),
    ).resolves.toMatchObject({ status: "processing" });
    await expect(legal.cancelOwnDeletionRequest(clientActor)).rejects.toThrow(
      ConflictException,
    );
    await expect(
      legal.updateDeletionRequest(director, second.id, {
        status: "completed",
        resolutionNote: "   ",
      }),
    ).rejects.toThrow(BadRequestException);
    await expect(
      legal.updateDeletionRequest(director, second.id, {
        status: "completed",
        resolutionNote: "PII проверена, обязательная история сохранена",
      }),
    ).resolves.toMatchObject({ status: "completed" });

    const clientFacts = await client.query<{
      email: string;
      password_hash: string | null;
      full_name: string | null;
      user_phone: string | null;
      user_deleted: Date | null;
      first_name: string | null;
      last_name: string | null;
      profile_phone: string | null;
      custom_data: Record<string, unknown>;
      profile_deleted: Date | null;
      identities: string;
      devices: string;
      reset_tokens: string;
      email_tokens: string;
      otp_tokens: string;
      live_sessions: string;
      consents: string;
      completed_requests: string;
      audits: string;
    }>(
      `
        select u.email, u.password_hash, u.full_name, u.phone as user_phone,
          u.deleted_at as user_deleted,
          p.first_name, p.last_name, p.phone as profile_phone, p.custom_data,
          p.deleted_at as profile_deleted,
          (select count(*)::text from app.user_identities where user_id = u.id) as identities,
          (select count(*)::text from app.notification_devices where user_id = u.id) as devices,
          (select count(*)::text from app.password_reset_tokens where user_id = u.id) as reset_tokens,
          (select count(*)::text from app.email_verification_tokens where user_id = u.id) as email_tokens,
          (select count(*)::text from app.otp_challenges where user_id = u.id) as otp_tokens,
          (select count(*)::text from app.refresh_sessions where user_id = u.id and revoked_at is null) as live_sessions,
          (select count(*)::text from app.legal_consents where user_id = u.id) as consents,
          (select count(*)::text from app.account_deletion_requests
            where user_id = u.id and status = 'completed') as completed_requests,
          (select count(*)::text from app.audit_events
            where entity_type = 'account_deletion_request'
              and action like 'legal.deletion%') as audits
        from app.users u
        join app.profiles p on p.user_id = u.id
        where u.id = $1
      `,
      [clientActor.userId],
    );
    expect(clientFacts.rows[0]).toMatchObject({
      password_hash: null,
      full_name: null,
      user_phone: null,
      first_name: null,
      last_name: null,
      profile_phone: null,
      custom_data: {},
      identities: "0",
      devices: "0",
      reset_tokens: "0",
      email_tokens: "0",
      otp_tokens: "0",
      live_sessions: "0",
      completed_requests: "1",
    });
    expect(clientFacts.rows[0].email).toMatch(/^deleted-.*@deleted\.invalid$/);
    expect(clientFacts.rows[0].user_deleted).not.toBeNull();
    expect(clientFacts.rows[0].profile_deleted).not.toBeNull();
    expect(Number(clientFacts.rows[0].consents)).toBe(documents.length);
    expect(Number(clientFacts.rows[0].audits)).toBeGreaterThanOrEqual(5);

    const ownerAfter = await client.query(
      `
        select u.email, u.password_hash, u.full_name, u.deleted_at,
          p.first_name, p.last_name, p.phone, p.custom_data
        from app.users u
        join app.profiles p on p.user_id = u.id
        where u.id = $1
      `,
      [ownerUserId],
    );
    expect(ownerAfter.rows).toEqual(ownerBefore.rows);
  });
});
