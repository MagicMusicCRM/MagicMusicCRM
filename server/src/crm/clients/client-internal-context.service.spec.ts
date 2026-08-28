import { ForbiddenException } from "@nestjs/common";
import { ActorContext, UserRole } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { PlatformIntegrityRepository } from "../../platform/platform-integrity.repository";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { ClientReferenceService } from "./client-reference.service";
import { ClientInternalContextService } from "./client-internal-context.service";

const actor = (role: UserRole): ActorContext => ({
  userId: `${role}-user`,
  role,
});

const ref = { type: "student" as const, id: "student-a" };

const historyRow = (overrides: Record<string, unknown> = {}) => ({
  id: "event-a",
  action: "unknown.action",
  reason: null,
  reason_text: null,
  metadata: null,
  before_ref: null,
  after_ref: null,
  actor_name: "Мария Управляющая",
  created_at: "2026-08-28T08:00:00.000Z",
  ...overrides,
});

const createService = (rows: Record<string, unknown>[] = []) => {
  const query = jest.fn().mockResolvedValue({ rows });
  const resolve = jest.fn().mockResolvedValue(ref);
  const service = new ClientInternalContextService(
    { query } as unknown as DatabaseService,
    { resolve } as unknown as ClientReferenceService,
    {} as PlatformIntegrityRepository,
    {} as RealtimeBus,
  );
  return { service, query, resolve };
};

describe("ClientInternalContextService operational history", () => {
  it.each<UserRole>(["client", "teacher"])(
    "rejects the %s role before reference resolution and database access",
    async (role) => {
      const { service, query, resolve } = createService();

      await expect(
        service.listOperationalHistory(actor(role), ref, {}),
      ).rejects.toEqual(
        new ForbiddenException("Внутренняя информация клиента недоступна."),
      );
      expect(resolve).not.toHaveBeenCalled();
      expect(query).not.toHaveBeenCalled();
    },
  );

  it.each<UserRole>(["admin", "manager", "director", "system_admin"])(
    "allows the %s role only after resolving the scoped reference",
    async (role) => {
      const { service, query, resolve } = createService();

      await expect(
        service.listOperationalHistory(actor(role), ref, {}),
      ).resolves.toEqual({ items: [], nextCursor: null });
      expect(resolve).toHaveBeenCalledWith(actor(role), ref);
      expect(resolve.mock.invocationCallOrder[0]).toBeLessThan(
        query.mock.invocationCallOrder[0]!,
      );
    },
  );

  it("preserves query parameters, over-fetch pagination and row order", async () => {
    const rows = [
      historyRow({ id: "event-c" }),
      historyRow({ id: "event-b" }),
      historyRow({ id: "event-a" }),
    ];
    const { service, query } = createService(rows);

    const result = await service.listOperationalHistory(
      actor("manager"),
      ref,
      { cursor: "11111111-1111-4111-8111-111111111111", limit: 2 },
    );

    expect(result.items.map((item) => item.id)).toEqual([
      "event-c",
      "event-b",
    ]);
    expect(result.nextCursor).toBe("event-b");
    expect(query).toHaveBeenCalledTimes(1);
    expect(query.mock.calls[0]![1]).toEqual([
      "student",
      "student-a",
      expect.arrayContaining([
        "crm.lead_converted",
        "crm.client_internal_note_changed",
        "crm.client_unblacklisted",
      ]),
      "11111111-1111-4111-8111-111111111111",
      3,
    ]);
    const sql = String(query.mock.calls[0]![0]);
    expect(sql).toContain("order by audit.created_at desc, audit.id desc");
    expect(sql).toContain("limit $5");
    expect(sql).toContain("(audit.created_at, audit.id) <");
  });

  it("keeps the default and capped query limits exact", async () => {
    const first = createService();
    await first.service.listOperationalHistory(actor("admin"), ref, {});
    expect(first.query.mock.calls[0]![1]).toEqual([
      "student",
      "student-a",
      expect.any(Array),
      null,
      31,
    ]);

    const second = createService();
    await second.service.listOperationalHistory(actor("admin"), ref, {
      limit: 150,
    });
    expect(second.query.mock.calls[0]![1]).toEqual([
      "student",
      "student-a",
      expect.any(Array),
      null,
      101,
    ]);
  });

  it("preserves every action label and the unknown-action fallback", async () => {
    const labels: Record<string, string> = {
      "crm.lead_converted": "Лид конвертирован в ученика",
      "crm.subscription_purchased": "Абонемент куплен",
      "crm.subscription_issued": "Абонемент выдан",
      "crm.subscription_replaced": "Абонемент заменён",
      "crm.subscription_cancelled": "Абонемент отменён",
      "crm.payment_record_created": "Оплата добавлена",
      "crm.payment_record_transitioned": "Статус оплаты изменён",
      "crm.installment_payment_due":
        "Срок платежа рассрочки наступил — требуется проверка",
      "crm.payment_reversed": "Оплата удалена из обычного учёта",
      "crm.payment_adjustment_recorded": "Возврат или корректировка",
      "crm.lesson_rescheduled": "Занятие перенесено",
      "crm.lesson_cancelled": "Занятие отменено",
      "crm.lesson_settled": "Занятие рассчитано",
      "crm.lessons_bulk_transitioned": "Занятия изменены",
      "crm.schedule_plan_ended": "Постоянное расписание завершено",
      "crm.client_internal_note_changed": "Общая заметка изменена",
      "crm.comment_created": "Комментарий добавлен",
      "crm.comment_teacher_sharing_changed":
        "Видимость комментария изменена",
      "workflow.shared_task_created": "Задача создана",
      "workflow.shared_task_updated": "Задача изменена",
      "workflow.shared_task_closed": "Задача закрыта",
      "crm.client_blacklisted": "Клиент добавлен в чёрный список",
      "crm.client_unblacklisted": "Клиент убран из чёрного списка",
      "unknown.action": "Действие с клиентом",
    };
    const rows = Object.keys(labels).map((actionKey, index) =>
      historyRow({ id: `event-${index}`, action: actionKey }),
    );
    const { service } = createService(rows);

    const result = await service.listOperationalHistory(
      actor("director"),
      ref,
      { limit: 100 },
    );

    expect(
      Object.fromEntries(
        result.items.map((item) => [item.actionKey, item.action]),
      ),
    ).toEqual(labels);
  });

  it("preserves reason precedence and exact sentinel redaction", async () => {
    const rows = [
      historyRow({
        id: "reason-text",
        action: "crm.comment_created",
        reason_text: "  Публичная причина  ",
        metadata: { reason: "metadata" },
        reason: "database",
      }),
      historyRow({
        id: "metadata",
        action: "crm.comment_created",
        metadata: { reason: "  Метаданные  " },
        reason: "database",
      }),
      historyRow({
        id: "default",
        action: "crm.comment_created",
        metadata: { reason: " [PRIVATE] " },
        reason: "database",
      }),
      historyRow({ id: "database", reason: "  Без trim  " }),
      historyRow({ id: "fallback" }),
      ...["[PRIVATE]", " [PII] ", "\t[REDACTED]\n"].map(
        (reason, index) =>
          historyRow({
            id: `sentinel-${index}`,
            metadata: { reason },
            reason: "Безопасная причина",
          }),
      ),
      historyRow({
        id: "lookalike",
        metadata: { reason: "[private]" },
        reason: "database",
      }),
      historyRow({
        id: "non-string",
        metadata: { reason: 42 },
        reason: "database",
      }),
    ];
    const { service } = createService(rows);

    const result = await service.listOperationalHistory(
      actor("system_admin"),
      ref,
      { limit: 100 },
    );

    expect(
      Object.fromEntries(result.items.map((item) => [item.id, item.reason])),
    ).toEqual({
      "reason-text": "Публичная причина",
      metadata: "Метаданные",
      default: "Комментарий добавлен",
      database: "  Без trim  ",
      fallback: "Причина не указана",
      "sentinel-0": "Безопасная причина",
      "sentinel-1": "Безопасная причина",
      "sentinel-2": "Безопасная причина",
      lookalike: "[private]",
      "non-string": "database",
    });
  });

  it("preserves every summary branch and status precedence", async () => {
    const rows = [
      historyRow({ id: "paid", metadata: { targetStatus: "paid" } }),
      historyRow({
        id: "pending",
        metadata: { targetStatus: "posted_pending" },
      }),
      historyRow({ id: "unpaid", metadata: { targetStatus: "unpaid" } }),
      historyRow({ id: "custom", metadata: { targetStatus: "review" } }),
      historyRow({
        id: "status-wins",
        action: "crm.client_internal_note_changed",
        metadata: { targetStatus: "paid" },
        before_ref: { version: 3 },
        after_ref: { version: 4 },
      }),
      historyRow({
        id: "note",
        action: "crm.client_internal_note_changed",
        metadata: { targetStatus: 0 },
        before_ref: {},
        after_ref: {},
      }),
      historyRow({
        id: "shared",
        action: "crm.comment_teacher_sharing_changed",
        after_ref: { sharedWithTeacher: true },
      }),
      historyRow({
        id: "hidden",
        action: "crm.comment_teacher_sharing_changed",
        after_ref: { sharedWithTeacher: 1 },
      }),
      historyRow({
        id: "bulk",
        action: "crm.lessons_bulk_transitioned",
        before_ref: { items: [1, 2, 3] },
      }),
      historyRow({
        id: "bulk-empty",
        action: "crm.lessons_bulk_transitioned",
        before_ref: { items: "three" },
      }),
      historyRow({ id: "other" }),
    ];
    const { service } = createService(rows);

    const result = await service.listOperationalHistory(
      actor("manager"),
      ref,
      { limit: 100 },
    );

    expect(
      Object.fromEntries(result.items.map((item) => [item.id, item.summary])),
    ).toEqual({
      paid: "Новый статус: Оплачен",
      pending: "Новый статус: Срок наступил — требуется проверка",
      unpaid: "Новый статус: Не оплачен",
      custom: "Новый статус: review",
      "status-wins": "Новый статус: Оплачен",
      note: "Версия 0 → —",
      shared: "Опубликован преподавателю",
      hidden: "Скрыт от преподавателя",
      bulk: "Изменено занятий: 3",
      "bulk-empty": "Изменено занятий: 0",
      other: null,
    });
  });

  it("returns the exact DTO shape without leaking unused audit payloads", async () => {
    const occurredAt = new Date("2026-08-28T08:00:00.000Z");
    const secret = "PRIVATE-HISTORY-SECRET-771";
    const row = historyRow({
      id: "event-shape",
      action: "unknown.action",
      reason_text: "Причина",
      metadata: { unused: secret },
      before_ref: { unusedBefore: secret },
      after_ref: { unusedAfter: secret },
      actor_name: "Анна Администратор",
      created_at: occurredAt,
    });
    const { service } = createService([row]);

    const result = await service.listOperationalHistory(
      actor("admin"),
      ref,
      {},
    );
    const item = result.items[0]!;

    expect(item).toEqual({
      id: "event-shape",
      actionKey: "unknown.action",
      action: "Действие с клиентом",
      reason: "Причина",
      summary: null,
      actorName: "Анна Администратор",
      occurredAt,
    });
    expect(Object.keys(item)).toEqual([
      "id",
      "actionKey",
      "action",
      "reason",
      "summary",
      "actorName",
      "occurredAt",
    ]);
    expect(item.occurredAt).toBe(occurredAt);
    expect(JSON.stringify(item)).not.toContain(secret);
  });
});
