import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { MigrationRunner } from "../db/migration-runner";
import { RealtimeBus } from "../realtime/realtime-bus";
import { CrmPolicy } from "./crm.policy";
import { LeadIntakeService } from "./lead-intake.service";

const defaultTestDatabaseUrl =
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
const testDatabaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ?? defaultTestDatabaseUrl;
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(
    new URL(testDatabaseUrl).hostname,
  )
) {
  throw new Error("Lead intake tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("App client intake identity (PostgreSQL)", () => {
  let database: DatabaseService;
  let service: LeadIntakeService;
  const userIds: string[] = [];
  const profileIds: string[] = [];
  const leadIds: string[] = [];
  const studentIds: string[] = [];

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
    service = new LeadIntakeService(
      database,
      new AuditService(database),
      new CrmPolicy(),
      { emitCrmChanged: jest.fn() } as unknown as RealtimeBus,
    );
  });

  afterAll(async () => {
    if (userIds.length > 0) {
      await database.query(
        `delete from app.user_crm_links where user_id = any($1::uuid[])`,
        [userIds],
      );
      await database.query(
        `delete from app.audit_events
          where actor_user_id = any($1::uuid[])
             or entity_id = any($2::text[])`,
        [userIds, [...leadIds, ...studentIds]],
      );
    }
    if (studentIds.length > 0) {
      await database.query(
        `delete from app.students where id = any($1::uuid[])`,
        [studentIds],
      );
    }
    if (leadIds.length > 0) {
      await database.query(`delete from app.leads where id = any($1::uuid[])`, [
        leadIds,
      ]);
    }
    if (profileIds.length > 0) {
      await database.query(
        `delete from app.profiles where id = any($1::uuid[])`,
        [profileIds],
      );
    }
    if (userIds.length > 0) {
      await database.query(`delete from app.users where id = any($1::uuid[])`, [
        userIds,
      ]);
    }
    await database.onModuleDestroy();
  });

  async function createClient(phone: string) {
    const userId = randomUUID();
    const profileId = randomUUID();
    const suffix = randomUUID();
    userIds.push(userId);
    profileIds.push(profileId);
    await database.query(
      `insert into app.users (
         id, email, role, profile_completed, is_app_account, email_verified_at
       ) values ($1, $2, 'client', true, true, now())`,
      [userId, `intake-${suffix}@test.local`],
    );
    await database.query(
      `insert into app.profiles (
         id, user_id, first_name, last_name, phone
       ) values ($1, $2, 'Новый', 'Клиент', $3)`,
      [profileId, userId, phone],
    );
    return {
      actor: { userId, role: "client" } as ActorContext,
      profileId,
      userId,
    };
  }

  async function createLead(phone: string) {
    const id = randomUUID();
    leadIds.push(id);
    await database.query(
      `insert into app.leads (id, first_name, last_name, phone)
       values ($1, 'Существующий', 'Лид', $2)`,
      [id, phone],
    );
    return id;
  }

  async function createLegacyStudent(phone: string) {
    const userId = randomUUID();
    const profileId = randomUUID();
    const studentId = randomUUID();
    const suffix = randomUUID();
    userIds.push(userId);
    profileIds.push(profileId);
    studentIds.push(studentId);
    await database.query(
      `insert into app.users (
         id, email, role, profile_completed, is_app_account
       ) values ($1, $2, 'client', true, false)`,
      [userId, `legacy-student-${suffix}@test.local`],
    );
    await database.query(
      `insert into app.profiles (
         id, user_id, first_name, last_name, phone, dob, custom_data
       ) values (
         $1, $2, 'Существующий', 'Ученик', $3, '2012-03-04',
         '{"schoolNote":"preserved"}'::jsonb
       )`,
      [profileId, userId, phone],
    );
    await database.query(
      `insert into app.students (id, profile_id, status)
       values ($1, $2, 'active')`,
      [studentId, profileId],
    );
    return studentId;
  }

  it("creates exactly one app-sourced Lead for a truly new client, even when chat races onboarding", async () => {
    const phone = `+7999${String(Math.floor(Math.random() * 10 ** 7)).padStart(7, "0")}`;
    const client = await createClient(phone);

    const outcomes = await Promise.all([
      service.autoCreateLeadFromChat(
        client.actor,
        client.userId,
        "onboarding",
      ),
      service.autoCreateLeadFromChat(client.actor, client.userId, "chat"),
    ]);
    expect(outcomes.filter((item) => item.created)).toHaveLength(1);

    const facts = await database.query<{
      lead_id: string;
      canonical_name: string;
      display_name: string;
      link_count: string;
    }>(
      `select lead.id as lead_id, source.canonical_name, source.display_name,
              count(link.id)::text as link_count
         from app.leads lead
         join app.lead_sources source on source.id = lead.source_id
         join app.user_crm_links link
           on link.entity_type = 'lead'
          and link.entity_id = lead.id
          and link.deleted_at is null
        where lead.phone_normalized = $1
          and lead.deleted_at is null
          and link.user_id = $2
        group by lead.id, source.canonical_name, source.display_name`,
      [phone, client.userId],
    );
    expect(facts.rows).toEqual([
      expect.objectContaining({
        canonical_name: "app",
        display_name: "Приложение",
        link_count: "1",
      }),
    ]);
    leadIds.push(facts.rows[0].lead_id);
  });

  it("links the single matching Lead without changing its source or creating another card", async () => {
    const phone = `+7998${String(Math.floor(Math.random() * 10 ** 7)).padStart(7, "0")}`;
    const leadId = await createLead(phone);
    const client = await createClient(phone);

    await expect(
      service.autoCreateLeadFromChat(
        client.actor,
        client.userId,
        "onboarding",
      ),
    ).resolves.toEqual({ leadId, created: false });

    const facts = await database.query<{ leads: string; links: string }>(
      `select
         (select count(*)::text from app.leads
           where phone_normalized = $1 and deleted_at is null) as leads,
         (select count(*)::text from app.user_crm_links
           where user_id = $2 and entity_type = 'lead'
             and entity_id = $3 and deleted_at is null) as links`,
      [phone, client.userId, leadId],
    );
    expect(facts.rows[0]).toEqual({ leads: "1", links: "1" });
  });

  it("prefers the single matching Student over a Lead and preserves both cards", async () => {
    const phone = `+7997${String(Math.floor(Math.random() * 10 ** 7)).padStart(7, "0")}`;
    const leadId = await createLead(phone);
    const studentId = await createLegacyStudent(phone);
    const client = await createClient(phone);

    await expect(
      service.autoCreateLeadFromChat(
        client.actor,
        client.userId,
        "onboarding",
      ),
    ).resolves.toEqual({ leadId: null, created: false });

    const facts = await database.query<{
      student_profile_id: string;
      first_name: string;
      dob: string;
      custom_data: Record<string, unknown>;
      student_links: string;
      lead_links: string;
      leads: string;
    }>(
      `select student.profile_id as student_profile_id,
              profile.first_name,
              profile.dob::text as dob,
              profile.custom_data,
              count(link.id) filter (
                where link.entity_type = 'student'
              )::text as student_links,
              count(link.id) filter (
                where link.entity_type = 'lead'
              )::text as lead_links,
              (select count(*)::text from app.leads
                where id = $3 and deleted_at is null) as leads
         from app.students student
         join app.profiles profile
           on profile.id = student.profile_id and profile.deleted_at is null
         left join app.user_crm_links link
           on link.user_id = $2 and link.deleted_at is null
        where student.id = $1
        group by student.profile_id, profile.first_name, profile.dob,
          profile.custom_data`,
      [studentId, client.userId, leadId],
    );
    expect(facts.rows[0]).toEqual({
      student_profile_id: client.profileId,
      first_name: "Существующий",
      dob: "2012-03-04",
      custom_data: { schoolNote: "preserved" },
      student_links: "1",
      lead_links: "0",
      leads: "1",
    });
  });

  it("creates no duplicate and no link when several Lead cards share the phone", async () => {
    const phone = `+7996${String(Math.floor(Math.random() * 10 ** 7)).padStart(7, "0")}`;
    await createLead(phone);
    await createLead(phone);
    const client = await createClient(phone);

    await expect(
      service.autoCreateLeadFromChat(
        client.actor,
        client.userId,
        "onboarding",
      ),
    ).resolves.toEqual({ leadId: null, created: false });

    const facts = await database.query<{ leads: string; links: string }>(
      `select
         (select count(*)::text from app.leads
           where phone_normalized = $1 and deleted_at is null) as leads,
         (select count(*)::text from app.user_crm_links
           where user_id = $2 and deleted_at is null) as links`,
      [phone, client.userId],
    );
    expect(facts.rows[0]).toEqual({ leads: "2", links: "0" });
  });
});
