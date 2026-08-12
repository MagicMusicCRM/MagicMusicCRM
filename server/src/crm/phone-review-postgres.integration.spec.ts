import { BadRequestException, ForbiddenException } from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { Pool, PoolClient } from "pg";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { MigrationRunner } from "../db/migration-runner";
import { CrmPolicy } from "./crm.policy";
import { PhoneReviewService } from "./phone-review.service";

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
  let actor: ActorContext;
  let leadId: string;
  let profileId: string;
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
      `insert into app.leads (id, first_name, phone)
       values ($1, 'Очередь', '123')`,
      [leadId],
    );
    await client.query(
      `insert into app.profiles (id, user_id, first_name, phone)
       values ($1, $2, 'Иностранный', '+1 212 555 0100')`,
      [profileId, profileUserId],
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
      profile_phone: string;
      profile_normalized: string | null;
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
          p.phone as profile_phone,
          p.phone_normalized as profile_normalized,
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
        join app.phone_review_queue lead_q on lead_q.id = $1
        join app.phone_review_queue profile_q on profile_q.id = $2
        where l.id = $4
      `,
      [leadQueueId, profileQueueId, profileId, leadId],
    );
    expect(facts.rows[0]).toEqual({
      lead_phone: "+79991234567",
      lead_normalized: "+79991234567",
      profile_phone: "+1 212 555 0100",
      profile_normalized: null,
      corrected_action: "corrected",
      corrected_note: "Подтверждено по карточке клиента",
      corrected_phone: "+79991234567",
      accepted_action: "accepted_as_is",
      accepted_note: "Подтверждён иностранный номер",
      accepted_phone: null,
      unresolved: "0",
      audits: "2",
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
