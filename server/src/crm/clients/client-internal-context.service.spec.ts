import { ClientInternalContextService } from "./client-internal-context.service";

type HistoryArguments = Parameters<
  ClientInternalContextService["listOperationalHistory"]
>;
type Role = HistoryArguments[0]["role"];

const actor = (role: Role): HistoryArguments[0] => ({
  userId: `${role}-user`,
  role,
});

const ref: HistoryArguments[1] = { type: "student", id: "student-a" };

const historyRow = (overrides: Record<string, unknown> = {}) => ({
  id: "event-a",
  action: "crm.student_updated",
  reason: null,
  reason_text: null,
  metadata: null,
  before_ref: null,
  after_ref: null,
  actor_id: "actor-a",
  actor_name: "Наталия Назарова",
  actor_role: "director",
  target_type: "student",
  target_id: "student-a",
  target_display_name: "Мария Баранова",
  created_at: "2026-08-30T12:00:00.000Z",
  ...overrides,
});

const createService = (rows: Record<string, unknown>[] = []) => {
  const query = jest.fn().mockImplementation((sql: string) =>
    Promise.resolve({
      rows: sql.includes("as allowed") ? [{ allowed: true }] : rows,
    }),
  );
  const resolve = jest.fn().mockResolvedValue(ref);
  const dependencies = [
    { query },
    { resolve },
    {},
    {},
  ] as unknown as ConstructorParameters<typeof ClientInternalContextService>;
  const service = new ClientInternalContextService(...dependencies);
  return { service, query, resolve };
};

describe("ClientInternalContextService operational history", () => {
  it.each<Role>(["client", "teacher"])(
    "rejects the %s role before reference resolution and database access",
    async (role) => {
      const { service, query, resolve } = createService();

      await expect(
        service.listOperationalHistory(actor(role), ref, {}),
      ).rejects.toMatchObject({
        name: "ForbiddenException",
        message: "Внутренняя информация клиента недоступна.",
      });
      expect(resolve).not.toHaveBeenCalled();
      expect(query).not.toHaveBeenCalled();
    },
  );

  it.each<Role>(["admin", "manager", "director", "system_admin"])(
    "preserves %s access and resolves the scoped client reference",
    async (role) => {
      const { service, query, resolve } = createService();

      await expect(
        service.listOperationalHistory(actor(role), ref, {}),
      ).resolves.toEqual({ items: [], nextCursor: null });
      expect(resolve).toHaveBeenCalledWith(actor(role), ref);
      expect(query.mock.calls[0]![1]).toEqual([`${role}-user`]);
    },
  );

  it("rejects a stale management token after the database role is downgraded", async () => {
    const { service, query, resolve } = createService();
    query.mockResolvedValueOnce({ rows: [{ allowed: false }] });

    await expect(
      service.listOperationalHistory(actor("manager"), ref, {}),
    ).rejects.toMatchObject({
      name: "ForbiddenException",
      message: "Внутренняя информация клиента недоступна.",
    });
    expect(resolve).not.toHaveBeenCalled();
    expect(query).toHaveBeenCalledTimes(1);
  });

  it("presents audit, lineage, note, and generic updates through the shared contract", async () => {
    const rows = [
      historyRow({
        id: "direction",
        metadata: {
          changes: [
            { field: "direction", from: "Вокал", to: "Фортепиано" },
          ],
        },
      }),
      historyRow({
        id: "lead-status",
        action: "crm.lead_status_changed",
        reason_text: "Клиент подтвердил обучение",
        before_ref: { status: "Новый" },
        after_ref: { status: "Занимается" },
        target_type: "lead",
        target_id: "lead-a",
        target_display_name: "Мария Баранова",
      }),
      historyRow({
        id: "note",
        action: "crm.client_internal_note_changed",
        before_ref: { version: 3, bodyLength: 20 },
        after_ref: { version: 4, bodyLength: 24 },
      }),
      historyRow({
        id: "generic-field",
        before_ref: { musicLevel: "Начальный" },
        after_ref: { musicLevel: "Продвинутый" },
      }),
      historyRow({ id: "auth", action: "auth.session_rotated" }),
      historyRow({ id: "session", action: "session.refresh" }),
    ];
    const { service } = createService(rows);

    const result = await service.listOperationalHistory(actor("manager"), ref, {});

    expect(result.items[0]).toMatchObject({
      title: "Направление изменено",
      actor: { name: "Наталия Назарова" },
      target: { type: "student", id: "student-a", displayName: "Мария Баранова" },
      changes: [
        {
          key: "direction",
          label: "Направление",
          before: "Вокал",
          after: "Фортепиано",
        },
      ],
    });
    expect(result.items.find((item) => item.id === "lead-status")).toMatchObject({
      actionKey: "crm.lead_status_changed",
      summary: "Клиент подтвердил обучение",
      target: { type: "lead", id: "lead-a", displayName: "Мария Баранова" },
      changes: [
        { key: "status", label: "Статус", before: "Новый", after: "Занимается" },
      ],
    });
    expect(result.items.find((item) => item.id === "generic-field")).toMatchObject({
      changes: [
        {
          key: "musicLevel",
          label: "Music level",
          before: "Начальный",
          after: "Продвинутый",
        },
      ],
    });
    expect(result.items.map((item) => item.id)).toEqual([
      "direction",
      "lead-status",
      "note",
      "generic-field",
    ]);
    expect(JSON.stringify(result.items)).not.toMatch(/Версия|auth\.|session|refresh/i);
  });

  it("preserves newest-first cursor pagination with default 10 and maximum 100", async () => {
    const rows = [
      historyRow({ id: "event-c" }),
      historyRow({ id: "event-b" }),
      historyRow({ id: "event-a" }),
    ];
    const { service, query } = createService(rows);

    const result = await service.listOperationalHistory(actor("manager"), ref, {
      cursor: "11111111-1111-4111-8111-111111111111",
      limit: 2,
    });

    expect(result.items.map((item) => item.id)).toEqual(["event-c", "event-b"]);
    expect(result.nextCursor).toBe("event-b");
    expect(query.mock.calls[1]![1]).toEqual([
      "student",
      "student-a",
      "11111111-1111-4111-8111-111111111111",
      3,
    ]);
    const sql = String(query.mock.calls[1]![0]);
    expect(sql).toContain("app.lead_status_history");
    expect(sql).toContain("history_event as");
    expect(sql).toContain("from history_event where id = $3::uuid");
    expect(sql).toContain("order by history.created_at desc, history.id desc");
    expect(sql).toContain("limit $4");
    expect(sql).toContain("(history.created_at, history.id) <");
    expect(sql).toContain("audit.action like 'crm.%'");
    expect(sql).toContain("audit.action like 'workflow.%'");
    expect(sql).not.toContain("any($3::text[])");

    const defaults = createService();
    await defaults.service.listOperationalHistory(actor("admin"), ref, {});
    expect(defaults.query.mock.calls[1]![1]).toEqual([
      "student",
      "student-a",
      null,
      11,
    ]);

    const capped = createService();
    await capped.service.listOperationalHistory(actor("admin"), ref, { limit: 150 });
    expect(capped.query.mock.calls[1]![1]).toEqual([
      "student",
      "student-a",
      null,
      101,
    ]);
  });
});
