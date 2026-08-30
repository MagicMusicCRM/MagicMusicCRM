import { PGlite } from "@electric-sql/pglite";
import { DatabaseService } from "../../db/database.service";
import { ClientInternalContextService } from "./client-internal-context.service";

const ids = {
  lead: "00000000-0000-4000-8000-000000000001",
  student: "00000000-0000-4000-8000-000000000002",
  actor: "00000000-0000-4000-8000-000000000003",
  oldStatus: "00000000-0000-4000-8000-000000000004",
  newStatus: "00000000-0000-4000-8000-000000000005",
  statusEvent: "00000000-0000-4000-8000-000000000006",
  auditEvent: "00000000-0000-4000-8000-000000000007",
} as const;

const databaseFor = (db: PGlite): DatabaseService =>
  ({
    query: async <T extends Record<string, unknown>>(
      sql: string,
      params?: unknown[],
    ) => {
      const result = await db.query<T>(sql, params);
      return { rows: result.rows };
    },
  }) as unknown as DatabaseService;

describe("ClientInternalContextService PostgreSQL history union", () => {
  it("paginates status and audit facts through one readable cursor", async () => {
    const db = new PGlite();
    try {
      await db.exec(`
        create schema app;
        create table app.client_conversion_links (lead_id uuid, student_id uuid);
        create table app.audit_events (
          id uuid primary key, actor_user_id uuid, action text, entity_type text,
          entity_id text, reason text, reason_text text, metadata jsonb,
          before_ref jsonb, after_ref jsonb, created_at timestamptz
        );
        create table app.users (
          id uuid primary key, full_name text, role text,
          deleted_at timestamptz
        );
        create table app.profiles (
          id uuid, user_id uuid, first_name text, last_name text, deleted_at timestamptz
        );
        create table app.students (
          id uuid primary key, profile_id uuid, deleted_at timestamptz
        );
        create table app.leads (
          id uuid primary key, first_name text, last_name text, deleted_at timestamptz
        );
        create table app.client_internal_notes (id uuid, lead_id uuid, student_id uuid);
        create table app.entity_comments (
          id uuid, entity_type text, entity_id uuid, deleted_at timestamptz
        );
        create table app.shared_tasks (
          id uuid, linked_entity_type text, linked_entity_id uuid,
          deleted_at timestamptz
        );
        create table app.subscriptions (
          id uuid, student_id uuid, payer_student_id uuid
        );
        create table app.client_payment_records (
          id uuid, student_id uuid, issued_subscription_id uuid
        );
        create table app.lessons (id uuid, lead_id uuid, student_id uuid);
        create table app.schedule_plans (id uuid, student_id uuid);
        create table app.schedule_plan_participants (plan_id uuid, student_id uuid);
        create table app.lead_statuses (id uuid primary key, name text);
        create table app.lead_status_history (
          id uuid primary key, lead_id uuid, old_status_id uuid,
          new_status_id uuid, old_owner_id uuid, new_owner_id uuid,
          changed_by uuid, changed_at timestamptz, comment text,
          reason_name_snapshot text
        );

        insert into app.client_conversion_links values ('${ids.lead}', '${ids.student}');
        insert into app.users values (
          '${ids.actor}', 'Анна Администратор', 'director', null
        );
        insert into app.profiles (user_id, first_name, last_name, deleted_at)
        values ('${ids.actor}', 'Анна', 'Администратор', null);
        insert into app.lead_statuses values
          ('${ids.oldStatus}', 'Новый'), ('${ids.newStatus}', 'Занимается');
        insert into app.lead_status_history (
          id, lead_id, old_status_id, new_status_id, old_owner_id,
          new_owner_id, changed_by, changed_at, comment
        ) values (
          '${ids.statusEvent}', '${ids.lead}', '${ids.oldStatus}',
          '${ids.newStatus}', '${ids.actor}', '${ids.actor}', '${ids.actor}',
          '2026-08-30T12:00:00Z', 'Клиент подтвердил обучение'
        );
        insert into app.audit_events (
          id, actor_user_id, action, entity_type, entity_id, metadata, created_at
        ) values (
          '${ids.auditEvent}', '${ids.actor}', 'crm.client_blacklisted',
          'lead', '${ids.lead}', '{"reason":"Дубликат"}',
          '2026-08-30T11:00:00Z'
        );
      `);

      const references = { resolve: jest.fn().mockResolvedValue(undefined) };
      const service = new ClientInternalContextService(
        databaseFor(db),
        references as never,
        {} as never,
        {} as never,
      );
      const actor = { userId: ids.actor, role: "director" as const };
      const ref = { type: "student" as const, id: ids.student };

      const first = await service.listOperationalHistory(actor, ref, {
        limit: 1,
      });
      expect(first).toEqual({
        items: [
          {
            id: ids.statusEvent,
            actionKey: "crm.lead_status_changed",
            title: "Действие выполнено",
            summary: "Клиент подтвердил обучение",
            reason: null,
            actor: {
              id: ids.actor,
              name: "Анна Администратор",
              role: "director",
            },
            target: {
              type: "lead",
              id: ids.lead,
              label: "Лид",
              displayName: null,
              routeType: "lead",
            },
            changes: [
              {
                key: "status",
                label: "Статус",
                before: "Новый",
                after: "Занимается",
              },
            ],
            occurredAt: new Date("2026-08-30T12:00:00.000Z"),
          },
        ],
        nextCursor: ids.statusEvent,
      });

      const second = await service.listOperationalHistory(actor, ref, {
        limit: 1,
        cursor: first.nextCursor!,
      });
      expect(second).toEqual({
        items: [
          {
            id: ids.auditEvent,
            actionKey: "crm.client_blacklisted",
            title: "Действие выполнено",
            summary: null,
            reason: null,
            actor: {
              id: ids.actor,
              name: "Анна Администратор",
              role: "director",
            },
            target: {
              type: "lead",
              id: ids.lead,
              label: "Лид",
              displayName: null,
              routeType: "lead",
            },
            changes: [],
            occurredAt: new Date("2026-08-30T11:00:00.000Z"),
          },
        ],
        nextCursor: null,
      });
      expect(JSON.stringify(second.items)).not.toContain("Дубликат");

      await db.exec(
        `update app.users set role = 'teacher' where id = '${ids.actor}'`,
      );
      const resolveCallsBeforeDowngrade = references.resolve.mock.calls.length;
      await expect(
        service.listOperationalHistory(actor, ref, { limit: 1 }),
      ).rejects.toMatchObject({
        name: "ForbiddenException",
        message: "Внутренняя информация клиента недоступна.",
      });
      expect(references.resolve).toHaveBeenCalledTimes(
        resolveCallsBeforeDowngrade,
      );
    } finally {
      await db.close();
    }
  });
});
