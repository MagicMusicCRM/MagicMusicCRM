import { buildCrmConfigurationBaseline } from "./crm-configuration-baseline";
import { buildCrmConfigurationImpact } from "./crm-configuration-impact.policy";

function field(
  key: string,
  overrides: Record<string, unknown> = {},
) {
  return {
    id: `${key}-id`,
    key,
    label: key,
    valueType: "text",
    required: false,
    active: true,
    system: false,
    categoryKey: "general",
    order: 0,
    width: "full",
    placements: ["create"],
    options: [],
    visibility: { lead: true, student: true },
    ...overrides,
  };
}

describe("CRM configuration impact policy", () => {
  it("blocks branch schema changes and non-overridable settings", async () => {
    const school = buildCrmConfigurationBaseline([]);
    school.businessSettings[0].branchOverridable = false;
    const current = structuredClone(school);
    const next = structuredClone(school);
    next.categories[0].label = "Другая категория";
    next.businessSettings[0].value = 45;

    const impact = await buildCrmConfigurationImpact({
      next,
      current,
      school,
      hasStoredClientFieldValues: async () => false,
    });

    expect(impact.valid).toBe(false);
    expect(impact.blockingIssues).toEqual([
      {
        field: "categories",
        code: "BRANCH_SCHEMA_OVERRIDE_FORBIDDEN",
        message: "Филиал может переопределять только бизнес-параметры.",
      },
      {
        field: "businessSettings.default_lesson_duration_minutes",
        code: "BRANCH_OVERRIDE_FORBIDDEN",
        message: "Параметр не допускает филиальное переопределение.",
      },
    ]);
  });

  it("requires stable commerce keys to be archived instead of removed", async () => {
    const current = buildCrmConfigurationBaseline([]);
    const next = structuredClone(current);
    next.lessonSettlementTypes = next.lessonSettlementTypes.slice(1);
    next.teacherCompensationRules = next.teacherCompensationRules.slice(1);

    const impact = await buildCrmConfigurationImpact({
      next,
      current,
      hasStoredClientFieldValues: async () => false,
    });

    expect(impact.blockingIssues).toEqual([
      {
        field: "lessonSettlementTypes.lesson",
        code: "CATALOG_KEY_REMOVAL_FORBIDDEN",
        message:
          "Стабильный ключ нельзя удалить или переименовать; архивируйте тип.",
      },
      {
        field: "teacherCompensationRules.none",
        code: "CATALOG_KEY_REMOVAL_FORBIDDEN",
        message:
          "Стабильный ключ нельзя удалить или переименовать; архивируйте тип.",
      },
    ]);
  });

  it("protects a system field type and active state", async () => {
    const current = buildCrmConfigurationBaseline([]);
    current.fields = [field("phone", { system: true })];
    const next = structuredClone(current);
    next.fields[0].valueType = "number";
    next.fields[0].active = false;

    const impact = await buildCrmConfigurationImpact({
      next,
      current,
      hasStoredClientFieldValues: async () => false,
    });

    expect(impact.blockingIssues).toContainEqual({
      field: "fields.phone",
      code: "SYSTEM_FIELD_LOCKED",
      message: "Тип и активность системного поля защищены.",
    });
  });

  it("blocks a populated custom field type change", async () => {
    const current = buildCrmConfigurationBaseline([]);
    current.fields = [field("experience")];
    const next = structuredClone(current);
    next.fields[0].valueType = "number";

    const impact = await buildCrmConfigurationImpact({
      next,
      current,
      hasStoredClientFieldValues: async (definitionId) =>
        definitionId === "experience-id",
    });

    expect(impact.blockingIssues).toEqual([
      {
        field: "fields.experience.valueType",
        code: "FIELD_TYPE_MIGRATION_REQUIRED",
        message:
          "Поле с сохранёнными значениями нельзя перевести в другой тип.",
      },
    ]);
  });

  it("reports field counts, future-snapshot warnings, and affected screens", async () => {
    const current = buildCrmConfigurationBaseline([]);
    current.fields = [field("archive"), field("rename")];
    const next = structuredClone(current);
    next.fields = [
      field("rename", { label: "Новое название" }),
      field("create"),
    ];
    next.businessSettings[0].value = 45;
    next.lessonSettlementTypes[0].label = "Обычное занятие";
    next.teacherCompensationRules[0].label = "Без оплаты";

    const impact = await buildCrmConfigurationImpact({
      next,
      current,
      hasStoredClientFieldValues: async () => false,
    });

    expect(impact).toEqual({
      valid: true,
      blockingIssues: [],
      warnings: [
        "Новые значения применятся только к будущим бизнес-снимкам.",
        "Новые правила применятся только к будущим решениям; история сохранит прежние снимки.",
      ],
      changes: {
        fieldsCreated: 1,
        fieldsUpdated: 1,
        fieldsArchived: 1,
        settingsChanged: 1,
        settlementTypesChanged: 1,
        compensationRulesChanged: 1,
      },
      affectedScreens: [
        "lead.create",
        "student.create",
        "client.card.custom_fields",
        "schedule.lesson.create",
        "client.payments",
        "schedule.lesson.decision",
        "teacher.compensation",
      ],
    });
  });
});
