import { diffEntityFields, LessonRow, toLessonDto, toTimelineDto } from "./crm-mappers";

describe("lesson editor projection", () => {
  it("keeps funding inputs and removes internal decision fields", () => {
    const dto = toLessonDto({
      id: "lesson-1",
      financial_decision: {
        settlementTypeKey: "lesson",
        teacherCompensationRuleKey: "fixed",
        teacherCompensationValueMinor: "150000",
        teacherCreditedDurationMinutes: 0,
        teacherCompensationSource: "manual",
        teacherRateSnapshot: { type: "hourly", value: "9000" },
        privateMetadata: "internal",
        clientDecisions: [{
          clientId: "recipient-1", payerStudentId: "payer-1",
          chargeType: "personal_account",
          chargeDurationMinutes: 0,
          settlementTypeKey: "lesson", basePriceMinor: "220000",
          discount: { type: "percent", percent: 10, reason: "Скидка" },
          surcharge: { amountMinor: "5000", reason: "Доплата" },
          teacherRateSnapshot: { type: "hourly", value: "9000" },
        }],
      },
    } as unknown as LessonRow);

    expect(dto.financialDecision).toEqual({
      settlementTypeKey: "lesson",
      teacherCompensationRuleKey: "fixed",
      teacherCompensationValueMinor: "150000",
      teacherCreditedDurationMinutes: 0,
      teacherCompensationSource: "manual",
      clientDecisions: [{
        clientId: "recipient-1", payerStudentId: "payer-1",
        chargeType: "personal_account",
        chargeDurationMinutes: 0,
        settlementTypeKey: "lesson", basePriceMinor: "220000",
        discount: { type: "percent", percent: 10, reason: "Скидка" },
        surcharge: { amountMinor: "5000", reason: "Доплата" },
      }],
    });
    expect(JSON.stringify(dto)).not.toContain("teacherRateSnapshot");
    expect(JSON.stringify(dto)).not.toContain("privateMetadata");
  });

  it("keeps withheld finance and authoritative empty membership distinct", () => {
    const dto = toLessonDto({
      id: "lesson-1", financial_decision: null, group_participants: [],
    } as unknown as LessonRow);
    expect(dto.financialDecision).toBeNull();
    expect(dto.groupParticipants).toEqual([]);
    expect(toLessonDto({ id: "lesson-1" } as LessonRow))
      .not.toHaveProperty("groupParticipants");
  });

  it("merges sparse group decisions without converting personal funding to a subscription", () => {
    const dto = toLessonDto({
      id: "lesson-1", group_id: "group-1",
      group_participants: [{ clientId: "student-a" }, { clientId: "student-b" }],
      client_financial_baseline: [
        { clientId: "student-a", chargeType: "subscription", subscriptionId: "old-sub" },
        { clientId: "student-b", chargeType: "personal_account", basePriceMinor: "70000" },
      ],
      financial_decision: {
        settlementTypeKey: "lesson", teacherCompensationRuleKey: "standard",
        clientDecisions: [
          { clientId: "student-a", chargeType: "personal_account", basePriceMinor: "30000" },
          { clientId: "excluded-student", chargeType: "subscription", subscriptionId: "excluded-sub" },
        ],
      },
    } as unknown as LessonRow);
    expect(dto.financialDecision?.clientDecisions).toEqual([
      { clientId: "student-a", chargeType: "personal_account", basePriceMinor: "30000" },
      { clientId: "student-b", chargeType: "personal_account", basePriceMinor: "70000" },
    ]);
  });

  it("reopens actual payer and normalized pricing instead of an older original plan", () => {
    const dto = toLessonDto({
      id: "lesson-1", financial_decision_is_plan: true,
      client_financial_baseline: [{
        clientId: "recipient", payerStudentId: "actual-payer", _effectiveFact: true,
        chargeType: "personal_account", basePriceMinor: "200000",
        discount: { type: "percent", percentBasisPoints: 1250, reason: "Льгота" },
        surcharge: { type: "fixed", amountMinor: "5000", reason: "Доплата" },
      }],
      financial_decision: {
        settlementTypeKey: "lesson", teacherCompensationRuleKey: "standard",
        clientDecisions: [{ clientId: "recipient", payerStudentId: "old-payer", subscriptionId: "old-sub" }],
      },
    } as unknown as LessonRow);
    expect(dto.financialDecision?.clientDecisions).toEqual([{
      clientId: "recipient", payerStudentId: "actual-payer",
      chargeType: "personal_account", basePriceMinor: "200000",
      discount: { type: "percent", percent: 12.5, reason: "Льгота" },
      surcharge: { amountMinor: "5000", reason: "Доплата" },
    }]);
  });

  it.each([
    { chargeType: "subscription", subscriptionId: "new-sub" },
    { subscriptionId: "new-sub" },
  ])("clears inherited personal pricing when a plan switches to subscription: %j", (override) => {
    const dto = toLessonDto({
      id: "lesson-1",
      client_financial_baseline: [{
        clientId: "recipient", payerStudentId: "payer",
        chargeType: "personal_account", basePriceMinor: "200000",
        discount: { type: "percent", percentBasisPoints: 1250, reason: "Льгота" },
        surcharge: { type: "fixed", amountMinor: "5000", reason: "Доплата" },
      }],
      financial_decision: {
        clientDecisions: [{ clientId: "recipient", ...override }],
      },
    } as unknown as LessonRow);

    expect(dto.financialDecision?.clientDecisions).toEqual([{
      clientId: "recipient", payerStudentId: "payer",
      chargeType: "subscription", subscriptionId: "new-sub",
    }]);
  });
});

describe("diffEntityFields", () => {
  const FIELDS = ["first_name", "phone", "email", "status"];

  it("reports only the fields that actually changed", () => {
    const changes = diffEntityFields(
      { first_name: "Анна", phone: "+79161234567", status: "active" },
      { first_name: "Анна", phone: "+79990000000", status: "active" },
      FIELDS,
    );

    expect(changes).toEqual([
      {
        field: "phone",
        from: "+79161234567",
        to: "+79990000000",
        label: "Телефон",
        valueType: "text",
        displayMode: "values",
      },
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
    expect(changes).toEqual([{
      field: "email",
      from: null,
      to: null,
      label: "Электронная почта",
      valueType: "text",
      displayMode: "values",
    }]);
  });

  it("diffs custom_data per key rather than as a blob", () => {
    const changes = diffEntityFields(
      { custom_data: { level: "A1", gender: "f" } },
      { custom_data: { level: "A2", gender: "f" } },
      [],
    );

    // «Уровень: A1 → A2» is an audit entry; a jsonb dump is not.
    expect(changes).toEqual([
      {
        field: "custom_data.level",
        from: "A1",
        to: "A2",
        label: "Уровень",
        valueType: "text",
        displayMode: "values",
      },
    ]);
  });

  it("sees a custom field appear and disappear", () => {
    const changes = diffEntityFields(
      { custom_data: { level: "A1" } },
      { custom_data: { category: "kids" } },
      [],
    );

    expect(changes).toEqual([
      {
        field: "custom_data.category",
        from: null,
        to: "kids",
        label: "Категория обучения",
        valueType: "text",
        displayMode: "values",
      },
      {
        field: "custom_data.level",
        from: "A1",
        to: null,
        label: "Уровень",
        valueType: "text",
        displayMode: "values",
      },
    ]);
  });

  it("stores a primitive list without JSON serialization", () => {
    const changes = diffEntityFields(
      { custom_data: { disciplines: ["Вокал"] } },
      { custom_data: { disciplines: ["Вокал", "Гитара"] } },
      [],
    );

    expect(changes).toEqual([
      {
        field: "custom_data.disciplines",
        from: ["Вокал"],
        to: ["Вокал", "Гитара"],
        label: "Направления",
        valueType: "list",
        displayMode: "values",
      },
    ]);
  });

  it("stores responsibility as a changed-only fact without UUIDs", () => {
    const oldUuid = "11111111-1111-4111-8111-111111111111";
    const newUuid = "22222222-2222-4222-8222-222222222222";
    const changes = diffEntityFields(
      { assigned_to: oldUuid, custom_data: {} },
      { assigned_to: newUuid, custom_data: {} },
      ["assigned_to"],
    );

    expect(changes).toEqual([{
      field: "assigned_to",
      from: null,
      to: null,
      label: "Ответственный",
      valueType: "reference",
      displayMode: "changed_only",
    }]);
    expect(JSON.stringify(changes)).not.toContain(oldUuid);
  });

  it("stores contactPersons only as safe counts", () => {
    const changes = diffEntityFields(
      { custom_data: { contactPersons: [] } },
      {
        custom_data: {
          contactPersons: [{ name: "Анна", phone: "+79991234567" }],
        },
      },
      [],
    );

    expect(changes[0]).toMatchObject({
      field: "custom_data.contactPersons",
      from: 0,
      to: 1,
      displayMode: "count",
    });
    expect(JSON.stringify(changes)).not.toContain("+79991234567");
  });

  it("keeps a same-count contact replacement as a changed-only fact", () => {
    const oldPhone = "+79991234567";
    const newPhone = "+79997654321";
    const changes = diffEntityFields(
      {
        custom_data: {
          contactPersons: [{ name: "Анна", phone: oldPhone }],
        },
      },
      {
        custom_data: {
          contactPersons: [{ name: "Мария", phone: newPhone }],
        },
      },
      [],
    );

    expect(changes).toEqual([{
      field: "custom_data.contactPersons",
      from: null,
      to: null,
      label: "Контактные лица",
      valueType: "contact_list",
      displayMode: "changed_only",
    }]);
    expect(JSON.stringify(changes)).not.toContain(oldPhone);
    expect(JSON.stringify(changes)).not.toContain(newPhone);
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

    expect(dto.title).toBe("Лид изменён");
    expect(dto.body).toBe(
      "Телефон: +79161234567 → +79990000000\nУровень: A1 → A2",
    );
  });

  it("says a valueless field changed instead of printing nulls", () => {
    const dto = toTimelineDto(
      auditRow(JSON.stringify({ changes: [{ field: "email", from: null, to: null }] })),
    );

    expect(dto.body).toBe("Электронная почта: изменено");
  });

  it("sanitizes historical UUID, hash, and contact JSON before rendering", () => {
    const oldUuid = "11111111-1111-4111-8111-111111111111";
    const newUuid = "22222222-2222-4222-8222-222222222222";
    const hash = "sha256:abcdef0123456789";
    const contactPhone = "+79991234567";
    const dto = toTimelineDto(
      auditRow(JSON.stringify({
        changes: [
          { field: "assigned_to", from: oldUuid, to: newUuid },
          { field: "legacyHash", from: null, to: hash },
          {
            field: "custom_data.contactPersons",
            from: JSON.stringify([{ name: "Анна", phone: contactPhone }]),
            to: JSON.stringify([
              { name: "Анна", phone: contactPhone },
              { name: "Мария", phone: "+79997654321" },
            ]),
          },
        ],
      })),
    );

    expect(dto.body).toBe(
      "Ответственный: изменено\n" +
      "Контактные лица: Контактных лиц: 1 → Контактных лиц: 2",
    );
    expect(dto.body).not.toContain(oldUuid);
    expect(dto.body).not.toContain(newUuid);
    expect(dto.body).not.toContain(hash);
    expect(dto.body).not.toContain(contactPhone);
    expect(dto.body).not.toContain("[{");
  });

  it("formats typed lists, dates, and booleans through shared policy", () => {
    const dto = toTimelineDto(
      auditRow(JSON.stringify({
        changes: [
          {
            field: "custom_data.disciplines",
            from: ["PIANO"],
            to: ["DRUMS", "Авторское"],
          },
          {
            field: "custom_data.birthday",
            from: "2000-02-01",
            to: "2001-03-02",
          },
          { field: "custom_data.noEmail", from: false, to: true },
        ],
      })),
    );

    expect(dto.body).toBe(
      "Направления: PIANO → DRUMS, Авторское\n" +
      "Дата рождения: 01.02.2000 → 02.03.2001\n" +
      "Нет email: Нет → Да",
    );
  });

  it("uses the shared action title and compatibility change aliases", () => {
    const dto = toTimelineDto({
      ...auditRow(JSON.stringify({
        changes: [
          { key: "direction", before: "Вокал", after: "Фортепиано" },
        ],
      })),
      title: "crm.student_updated",
      status: "student",
    });

    expect(dto.title).toBe("Направление изменено");
    expect(dto.body).toBe("Направление: Вокал → Фортепиано");
  });

  it("skips malformed historical changes and keeps the valid entries", () => {
    const dto = toTimelineDto({
      ...auditRow(JSON.stringify({
        changes: [
          null,
          "broken",
          {},
          { field: 42, from: "До", to: "После" },
          { field: "phone", from: "+70000000000" },
          { key: "custom_data.noEmail", before: false, after: true },
        ],
      })),
      title: "crm.student_updated",
      status: "student",
    });

    expect(dto.title).toBe("Данные ученика изменены");
    expect(dto.body).toBe("Нет email: Нет → Да");
  });

  it("drops the body of an audited action that carries no diff", () => {
    const dto = toTimelineDto(auditRow(JSON.stringify({})));

    // Otherwise a create/delete event renders as a literal "{}" in the card.
    expect(dto.title).toBe("Лид изменён");
    expect(dto.body).toBeNull();
  });

  it("does not expose malformed audit metadata", () => {
    const dto = toTimelineDto(auditRow("not json at all"));

    expect(dto.title).toBe("Лид изменён");
    expect(dto.body).toBeNull();
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
