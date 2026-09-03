import { UnprocessableEntityException } from "@nestjs/common";
import { normalizeCrmConfigurationSnapshot } from "./crm-configuration-snapshot-normalizer";

function validRawSnapshot(): Record<string, unknown> {
  return {
    categories: [
      { key: "general", label: "Основная информация", order: 0, active: true },
    ],
    fields: [],
    optionSets: [],
    businessSettings: [
      {
        key: "default_lesson_duration_minutes",
        label: "Длительность занятия по умолчанию",
        valueType: "integer",
        unit: "мин",
        min: 15,
        max: 240,
        value: 60,
        branchOverridable: true,
      },
      {
        key: "payment_reminder_days",
        label: "Напомнить об оплате заранее",
        valueType: "integer",
        unit: "дн.",
        min: 0,
        max: 60,
        value: 3,
        branchOverridable: true,
      },
    ],
    lessonSettlementTypes: [
      {
        stableKey: "lesson",
        label: "Занятие",
        colorToken: "success",
        hourShareBasisPoints: 10000,
        clientDurationMode: "full",
        teacherDurationMode: "full",
        defaultTeacherCompensationRuleKey: "standard",
        allowedContexts: ["settle"],
        active: true,
        order: 0,
      },
    ],
    teacherCompensationRules: [
      {
        stableKey: "standard",
        label: "Полная стандартная ставка",
        mode: "standard",
        value: "0",
        active: true,
        order: 0,
      },
    ],
  };
}

function rows(
  snapshot: Record<string, unknown>,
  key: string,
): Array<Record<string, unknown>> {
  return snapshot[key] as Array<Record<string, unknown>>;
}

function validField(overrides: Record<string, unknown> = {}) {
  return {
    key: "phone",
    label: "Телефон",
    valueType: "phone",
    required: false,
    active: true,
    system: false,
    categoryKey: "general",
    order: 0,
    width: "full",
    placements: ["create", "edit"],
    options: [],
    visibility: { lead: true, student: true },
    ...overrides,
  };
}

function invalidResponse(snapshot: Record<string, unknown>): unknown {
  try {
    normalizeCrmConfigurationSnapshot(snapshot);
  } catch (error) {
    if (error instanceof UnprocessableEntityException) {
      return error.getResponse();
    }
    throw error;
  }
  throw new Error("Expected configuration normalization to fail");
}

describe("normalizeCrmConfigurationSnapshot", () => {
  it("merges legacy Lead and Student field copies into one visible field", () => {
    const raw = validRawSnapshot();
    raw.fields = [
      {
        key: "phone",
        label: "Телефон",
        valueType: "phone",
        required: false,
        active: true,
        system: false,
        categoryKey: "general",
        order: 2,
        width: "full",
        placements: ["create", "edit"],
        options: [],
        entityType: "lead",
      },
      {
        key: "phone",
        label: "Телефон",
        valueType: "phone",
        required: true,
        active: true,
        system: false,
        categoryKey: "general",
        order: 4,
        width: "full",
        placements: ["create", "edit"],
        options: [],
        entityType: "student",
      },
    ];

    const normalized = normalizeCrmConfigurationSnapshot(raw);

    expect(normalized.fields).toEqual([
      {
        key: "phone",
        label: "Телефон",
        valueType: "phone",
        required: true,
        active: true,
        system: false,
        categoryKey: "general",
        order: 2,
        width: "full",
        placements: ["create", "edit"],
        options: [],
        visibility: { lead: true, student: true },
      },
    ]);
  });

  it("rejects a field whose category is not declared", () => {
    const raw = validRawSnapshot();
    raw.fields = [validField({ categoryKey: "missing" })];

    expect(invalidResponse(raw)).toEqual({
      code: "UNKNOWN_CATEGORY",
      field: "fields.0.categoryKey",
      message: "Категория не найдена.",
    });
  });

  it("rejects an unsupported field placement", () => {
    const raw = validRawSnapshot();
    raw.fields = [validField({ placements: ["sidebar"] })];

    expect(invalidResponse(raw)).toEqual({
      code: "INVALID_PLACEMENT",
      field: "fields.0.placements.0",
      message: "Размещение поля не поддерживается.",
    });
  });

  it("requires an active field to be visible in at least one card", () => {
    const raw = validRawSnapshot();
    raw.fields = [
      validField({ visibility: { lead: false, student: false } }),
    ];

    expect(invalidResponse(raw)).toEqual({
      code: "FIELD_VISIBILITY_REQUIRED",
      field: "fields.0.visibility",
      message: "Активное поле должно быть видно хотя бы в одной карточке.",
    });
  });

  it("rejects incompatible legacy field copies", () => {
    const raw = validRawSnapshot();
    raw.fields = [
      validField({ entityType: "lead", visibility: undefined }),
      validField({
        entityType: "student",
        visibility: undefined,
        valueType: "text",
      }),
    ];

    expect(invalidResponse(raw)).toEqual({
      code: "INCOMPATIBLE_DUPLICATE_FIELD",
      field: "fields.phone.valueType",
      message: "Старые копии поля Lead/Student имеют разные типы.",
    });
  });

  it("rejects a field that references an unknown option set", () => {
    const raw = validRawSnapshot();
    raw.fields = [
      validField({ valueType: "select", optionSetKey: "unknown" }),
    ];

    expect(invalidResponse(raw)).toEqual({
      code: "UNKNOWN_OPTION_SET",
      field: "fields.phone.optionSetKey",
      message: "Выбранный справочник не найден.",
    });
  });

  it("enforces the configured business-setting bounds", () => {
    const raw = validRawSnapshot();
    rows(raw, "businessSettings")[0].value = 241;

    expect(invalidResponse(raw)).toEqual({
      code: "SETTING_OUT_OF_RANGE",
      field: "businessSettings.0.value",
      message: "Допустимо 15–240.",
    });
  });

  it("rejects an unsupported lesson settlement context", () => {
    const raw = validRawSnapshot();
    rows(raw, "lessonSettlementTypes")[0].allowedContexts = ["preview"];

    expect(invalidResponse(raw)).toEqual({
      code: "INVALID_SETTLEMENT_CONTEXT",
      field: "lessonSettlementTypes.0.allowedContexts.0",
      message: "Допустимы settle, reschedule и cancel.",
    });
  });

  it("rejects an unsupported settlement duration mode", () => {
    const raw = validRawSnapshot();
    rows(raw, "lessonSettlementTypes")[0].clientDurationMode = "fraction";

    expect(invalidResponse(raw)).toEqual({
      code: "INVALID_SETTLEMENT_DURATION_MODE",
      field: "lessonSettlementTypes.0.clientDurationMode",
      message: "Допустимы zero, full и manual.",
    });
  });

  it("preserves the system-owned settlement policy metadata", () => {
    const normalized = normalizeCrmConfigurationSnapshot(validRawSnapshot());

    expect(normalized.lessonSettlementTypes[0]).toMatchObject({
      clientDurationMode: "full",
      teacherDurationMode: "full",
      defaultTeacherCompensationRuleKey: "standard",
    });
  });

  it("requires at least one active lesson settlement type", () => {
    const raw = validRawSnapshot();
    rows(raw, "lessonSettlementTypes")[0].active = false;

    expect(invalidResponse(raw)).toEqual({
      code: "ACTIVE_SETTLEMENT_TYPE_REQUIRED",
      field: "lessonSettlementTypes",
      message: "Оставьте активным хотя бы один тип списания.",
    });
  });

  it("rejects a non-zero value for the standard compensation mode", () => {
    const raw = validRawSnapshot();
    rows(raw, "teacherCompensationRules")[0].value = "1";

    expect(invalidResponse(raw)).toEqual({
      code: "INVALID_COMPENSATION_VALUE",
      field: "teacherCompensationRules.0.value",
      message: "Для none/standard значение должно быть равно нулю.",
    });
  });

  it("requires at least one active teacher compensation rule", () => {
    const raw = validRawSnapshot();
    rows(raw, "teacherCompensationRules")[0].active = false;

    expect(invalidResponse(raw)).toEqual({
      code: "ACTIVE_COMPENSATION_RULE_REQUIRED",
      field: "teacherCompensationRules",
      message: "Оставьте активным хотя бы один тип оплаты преподавателю.",
    });
  });

  it("projects active option labels and stabilizes catalog ordering", () => {
    const raw = validRawSnapshot();
    raw.fields = [
      validField({
        key: "format",
        valueType: "select",
        optionSetKey: "formats",
      }),
    ];
    raw.optionSets = [
      {
        key: "formats",
        label: "Форматы",
        multiple: false,
        options: [
          { key: "online", label: "Онлайн", order: 2, active: true },
          { key: "archived", label: "Архив", order: 1, active: false },
          { key: "studio", label: "Студия", order: 0, active: true },
        ],
      },
    ];
    rows(raw, "lessonSettlementTypes").push({
      stableKey: "free",
      label: "Бесплатно",
      colorToken: "warning",
      hourShareBasisPoints: 0,
      clientDurationMode: "zero",
      teacherDurationMode: "zero",
      defaultTeacherCompensationRuleKey: "none",
      allowedContexts: ["settle", "cancel"],
      active: true,
      order: 0,
    });
    rows(raw, "lessonSettlementTypes")[0].order = 1;
    rows(raw, "teacherCompensationRules").push({
      stableKey: "none",
      label: "Не оплачивать",
      mode: "none",
      value: "0",
      active: true,
      order: 0,
    });
    rows(raw, "teacherCompensationRules")[0].order = 1;

    const normalized = normalizeCrmConfigurationSnapshot(raw);

    expect(normalized.fields[0].options).toEqual(["Студия", "Онлайн"]);
    expect(
      normalized.lessonSettlementTypes.map((item) => item.stableKey),
    ).toEqual(["free", "lesson"]);
    expect(normalized.lessonSettlementTypes[0].allowedContexts).toEqual([
      "cancel",
      "settle",
    ]);
    expect(
      normalized.teacherCompensationRules.map((item) => item.stableKey),
    ).toEqual(["none", "standard"]);
  });
});
