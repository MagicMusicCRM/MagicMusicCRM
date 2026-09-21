import { ForbiddenException } from "@nestjs/common";
import { DatabaseService } from "../db/database.service";
import { NotificationDeliveryJournalService } from "./notification-delivery-journal.service";

describe("NotificationDeliveryJournalService", () => {
  const actor = {
    userId: "11111111-1111-4111-8111-111111111111",
    role: "manager" as const,
  };

  it("returns scoped channel delivery facts and entity links", async () => {
    const query = jest
      .fn()
      .mockResolvedValueOnce({ rows: [{ role: "manager" }] })
      .mockResolvedValueOnce({
        rows: [
          {
            notification_id: "notification-1",
            notification_type: "system",
            title: "Новая задача",
            event_type: "task_assigned",
            entity_type: "shared_task",
            entity_id: "task-1",
            recipient_user_id: "user-2",
            recipient_name: "Анна Менеджер",
            recipient_entity_type: "staff",
            recipient_entity_id: "staff-2",
            branch_id: "branch-1",
            branch_name: "Центр",
            channel: "push",
            provider: "firebase",
            status: "sent",
            attempt_count: 1,
            last_error: null,
            created_at: "2026-09-20T10:00:00.000Z",
            updated_at: "2026-09-20T10:01:00.000Z",
            total_count: "1",
          },
        ],
      });
    const service = new NotificationDeliveryJournalService({
      query,
    } as unknown as DatabaseService);

    const result = await service.list(actor, {
      from: "2026-09-01T00:00:00.000Z",
      to: "2026-10-01T00:00:00.000Z",
      branchId: "22222222-2222-4222-8222-222222222222",
      status: "sent",
    });

    expect(result.total).toBe(1);
    expect(result.items[0]).toMatchObject({
      entityType: "task",
      entityId: "task-1",
      recipientEntityType: "staff",
      recipientEntityId: "staff-2",
      branchName: "Центр",
      status: "sent",
    });
    const sql = String(query.mock.calls[1]![0]);
    expect(sql).toContain("app.notification_deliveries");
    expect(sql).toContain("app.email_outbox");
    expect(sql).toContain("outbox.attempt_count");
    expect(sql).toContain("outbox.last_error");
    expect(sql).toContain("scope_assignment.branch_id");
    expect(query.mock.calls[1]![1]).toEqual([
      "2026-09-01T00:00:00.000Z",
      "2026-10-01T00:00:00.000Z",
      "22222222-2222-4222-8222-222222222222",
      null,
      "sent",
      50,
      0,
      actor.userId,
    ]);
  });

  it("rejects a stale privileged token after the database role changed", async () => {
    const service = new NotificationDeliveryJournalService({
      query: jest.fn().mockResolvedValue({ rows: [{ role: "teacher" }] }),
    } as unknown as DatabaseService);

    await expect(service.list(actor, {})).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });
});
