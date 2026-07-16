import { diffEntityFields, toTimelineDto } from "./crm-mappers";

describe("diffEntityFields", () => {
  const FIELDS = ["first_name", "phone", "email", "status"];

  it("reports only the fields that actually changed", () => {
    const changes = diffEntityFields(
      { first_name: "Анна", phone: "+79161234567", status: "active" },
      { first_name: "Анна", phone: "+79990000000", status: "active" },
      FIELDS,
    );

    expect(changes).toEqual([
      { field: "phone", from: "+79161234567", to: "+79990000000" },
    ]);
  });

  it("does not report an untouched field as erased", () => {
    // Both lead and student updates are coalesce-updates: an unmentioned field
    // comes back unchanged, and null on either side must not read as a change.
    const changes = diffEntityFields(
      { first_name: "Анна", phone: null },
      { first_name: "Анна", phone: null },
      FIELDS,
    );

    expect(changes).toEqual([]);
  });

  it("treats an empty string as no value, not as a change to ''", () => {
    const changes = diffEntityFields(
      { notes: null },
      { notes: "" },
      ["notes"],
    );

    expect(changes).toEqual([]);
  });

  it("records that the e-mail changed without storing either address", () => {
    const changes = diffEntityFields(
      { email: "a@example.com" },
      { email: "b@example.com" },
      FIELDS,
    );

    // AuditService pipes metadata through redactSensitive, which masks e-mail
    // values — storing them would render as «Почта: [EMAIL] → [EMAIL]».
    expect(changes).toEqual([{ field: "email", from: null, to: null }]);
  });

  it("diffs custom_data per key rather than as a blob", () => {
    const changes = diffEntityFields(
      { custom_data: { level: "A1", gender: "f" } },
      { custom_data: { level: "A2", gender: "f" } },
      [],
    );

    // «Уровень: A1 → A2» is an audit entry; a jsonb dump is not.
    expect(changes).toEqual([
      { field: "custom_data.level", from: "A1", to: "A2" },
    ]);
  });

  it("sees a custom field appear and disappear", () => {
    const changes = diffEntityFields(
      { custom_data: { level: "A1" } },
      { custom_data: { category: "kids" } },
      [],
    );

    expect(changes).toEqual([
      { field: "custom_data.category", from: null, to: "kids" },
      { field: "custom_data.level", from: "A1", to: null },
    ]);
  });

  it("serialises a list value instead of rendering [object Object]", () => {
    const changes = diffEntityFields(
      { custom_data: { disciplines: ["Вокал"] } },
      { custom_data: { disciplines: ["Вокал", "Гитара"] } },
      [],
    );

    expect(changes).toEqual([
      {
        field: "custom_data.disciplines",
        from: '["Вокал"]',
        to: '["Вокал","Гитара"]',
      },
    ]);
  });
});

describe("toTimelineDto — audit rows", () => {
  const auditRow = (body: string | null) => ({
    id: "audit-1",
    type: "audit",
    title: "crm.lead_updated",
    body,
    status: "lead",
    amount: null,
    actor_user_id: "manager-a",
    actor_first_name: "Мария",
    actor_last_name: "Менеджер",
    occurred_at: "2026-07-16T10:00:00.000Z",
  });

  it("renders a change list as readable lines, not raw json", () => {
    const dto = toTimelineDto(
      auditRow(
        JSON.stringify({
          changes: [
            { field: "phone", from: "+79161234567", to: "+79990000000" },
            { field: "custom_data.level", from: "A1", to: "A2" },
          ],
        }),
      ),
    );

    expect(dto.title).toBe("Правка полей");
    expect(dto.body).toBe(
      "Телефон: +79161234567 → +79990000000\nУровень: A1 → A2",
    );
  });

  it("says a valueless field changed instead of printing nulls", () => {
    const dto = toTimelineDto(
      auditRow(JSON.stringify({ changes: [{ field: "email", from: null, to: null }] })),
    );

    expect(dto.body).toBe("Почта: изменено");
  });

  it("drops the body of an audited action that carries no diff", () => {
    const dto = toTimelineDto(auditRow(JSON.stringify({})));

    // Otherwise a create/delete event renders as a literal "{}" in the card.
    expect(dto.title).toBe("crm.lead_updated");
    expect(dto.body).toBeNull();
  });

  it("leaves a non-json body alone rather than throwing", () => {
    const dto = toTimelineDto(auditRow("not json at all"));

    expect(dto.body).toBe("not json at all");
  });

  it("leaves non-audit rows untouched", () => {
    const dto = toTimelineDto({
      ...auditRow("Позвонил, договорились"),
      type: "comment",
      title: "Комментарий",
    });

    expect(dto.title).toBe("Комментарий");
    expect(dto.body).toBe("Позвонил, договорились");
  });
});
