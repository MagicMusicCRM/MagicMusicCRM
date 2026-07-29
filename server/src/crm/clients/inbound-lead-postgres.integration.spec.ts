import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import { AuditService } from "../../audit/audit.service";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { ChatWorkTimelineService } from "../../messenger/chat-work-timeline.service";
import { PlatformIntegrityRepository } from "../../platform/platform-integrity.repository";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { CrmPolicy } from "../crm.policy";
import { LeadsService } from "../leads.service";
import { TimelineService } from "../timeline.service";
import { ClientConfigRepository } from "./client-config.repository";
import { ClientWriteValidator } from "./client-write.validator";
import { InboundLeadService } from "./inbound-lead.service";

const defaultTestDatabaseUrl =
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
const testDatabaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ?? defaultTestDatabaseUrl;
const parsedDatabaseUrl = new URL(testDatabaseUrl);
if (!new Set(["127.0.0.1", "localhost", "[::1]"]).has(parsedDatabaseUrl.hostname)) {
  throw new Error("Inbound lead tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("manual and inbound Lead commands (PostgreSQL)", () => {
  let database: DatabaseService;
  let inbound: InboundLeadService;
  let manual: LeadsService;
  let sourceId: string;
  let actor: ActorContext;
  const ingestionIds: string[] = [];
  const leadIds: string[] = [];
  const userIds: string[] = [];

  beforeAll(async () => {
    const migrationPool = new Pool({ connectionString: testDatabaseUrl });
    try {
      await new MigrationRunner(migrationPool).up();
    } finally {
      await migrationPool.end();
    }
    database = new DatabaseService({
      getOrThrow: () => testDatabaseUrl,
    } as unknown as ConfigService);
    const configRepository = new ClientConfigRepository(database);
    inbound = new InboundLeadService(
      new PlatformIntegrityService(
        database,
        new PlatformIntegrityRepository(),
      ),
      configRepository,
      new ClientWriteValidator(configRepository),
    );

    const user = await database.query<{ id: string }>(
      `
        insert into app.users (email, role, email_verified_at)
        values ($1, 'manager', now())
        returning id
      `,
      [`v4-inbound-${randomUUID()}@example.com`],
    );
    userIds.push(user.rows[0]!.id);
    actor = { userId: user.rows[0]!.id, role: "manager" };
    manual = new LeadsService(
      database,
      { record: jest.fn().mockResolvedValue(undefined) } as unknown as AuditService,
      new CrmPolicy(),
      { listForEntity: jest.fn().mockResolvedValue([]) } as unknown as ChatWorkTimelineService,
      { emitCrmChanged: jest.fn() } as unknown as RealtimeBus,
      { listFieldAudit: jest.fn().mockResolvedValue({ items: [] }) } as unknown as TimelineService,
    );

    const source = await database.query<{ id: string }>(
      `
        insert into app.lead_sources (
          canonical_name,
          display_name,
          is_active
        )
        values ($1, $2, true)
        returning id
      `,
      [
        `integration_${randomUUID().replace(/-/g, "")}`,
        "V4 inbound integration",
      ],
    );
    sourceId = source.rows[0]!.id;
  });

  afterAll(async () => {
    if (ingestionIds.length > 0) {
      await database.query(
        `
          delete from app.idempotency_records
          where actor_key = 'integration:lead-webhook'
            and idempotency_key = any($1::text[])
        `,
        [ingestionIds],
      );
      await database.query(
        `
          delete from app.aggregate_versions
          where aggregate_type = 'inbound_lead_ingestion'
            and aggregate_id = any($1::text[])
        `,
        [ingestionIds],
      );
      await database.query(
        `
          delete from app.platform_outbox_events
          where request_id = any($1::text[])
        `,
        [ingestionIds.map((id) => `inbound-lead:${id}`)],
      );
      await database.query(
        `
          delete from app.audit_events
          where request_id = any($1::text[])
        `,
        [ingestionIds.map((id) => `inbound-lead:${id}`)],
      );
    }
    if (leadIds.length > 0) {
      await database.query(
        "delete from app.leads where id = any($1::uuid[])",
        [leadIds],
      );
    }
    await database.query("delete from app.lead_sources where id = $1", [
      sourceId,
    ]);
    if (userIds.length > 0) {
      await database.query(
        "delete from app.users where id = any($1::uuid[])",
        [userIds],
      );
    }
    await database.onModuleDestroy();
  });

  it("keeps manual notifications at zero and deduplicates inbound Lead + outbox", async () => {
    const ingestionId = randomUUID();
    ingestionIds.push(ingestionId);
    const before = await database.query<{
      notification_count: string;
      outbox_count: string;
    }>(
      `
        select
          (select count(*)::text from app.notifications
            where type = 'new_lead') as notification_count,
          (select count(*)::text from app.platform_outbox_events
            where event_type = 'inbound.lead.created') as outbox_count
      `,
    );

    const manualLead = await manual.createLead(actor, {
      firstName: "Ручной",
      lastName: "Лид",
      phone: "+79990000001",
      source: "manual",
    });
    leadIds.push(manualLead.id);

    const payload = {
      firstName: "Входящий",
      lastName: "Лид",
      phone: "8 (999) 000-00-02",
      sourceId,
      email: "INBOUND@example.com",
      discipline: "Вокал",
      comment: "Нужен пробный урок",
    };
    const first = await inbound.ingest({ ingestionId, payload });
    await database.query(
      "update app.lead_sources set is_active = false where id = $1",
      [sourceId],
    );
    const replay = await inbound.ingest({ ingestionId, payload });
    leadIds.push(first.leadId);

    expect(first).toMatchObject({ replayed: false });
    expect(replay).toEqual({ leadId: first.leadId, replayed: true });

    const after = await database.query<{
      inbound_leads: string;
      inbound_outbox: string;
      notification_count: string;
      total_outbox: string;
      first_name: string;
      last_name: string;
      phone: string;
      email: string;
      source_id: string;
      notes: string;
    }>(
      `
        select
          (
            select count(*)::text from app.leads
            where inbound_id = $1
          ) as inbound_leads,
          (
            select count(*)::text from app.platform_outbox_events
            where request_id = $2
              and event_type = 'inbound.lead.created'
          ) as inbound_outbox,
          (
            select count(*)::text from app.notifications
            where type = 'new_lead'
          ) as notification_count,
          (
            select count(*)::text from app.platform_outbox_events
            where event_type = 'inbound.lead.created'
          ) as total_outbox,
          lead.first_name,
          lead.last_name,
          lead.phone,
          lead.email,
          lead.source_id,
          lead.notes
        from app.leads lead
        where lead.id = $3
      `,
      [ingestionId, `inbound-lead:${ingestionId}`, first.leadId],
    );
    expect(after.rows[0]).toMatchObject({
      inbound_leads: "1",
      inbound_outbox: "1",
      notification_count: before.rows[0]!.notification_count,
      total_outbox: String(Number(before.rows[0]!.outbox_count) + 1),
      first_name: "Входящий",
      last_name: "Лид",
      phone: "+79990000002",
      email: "inbound@example.com",
      source_id: sourceId,
      notes: "Дисциплина: Вокал\nНужен пробный урок",
    });
  });
});
