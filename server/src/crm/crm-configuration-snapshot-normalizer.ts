import { UnprocessableEntityException } from "@nestjs/common";
import type {
  ConfigCategory,
  ConfigField,
  ConfigOptionSet,
  ConfigSetting,
  ConfigSnapshot,
  LessonSettlementTypeConfig,
  TeacherCompensationRuleConfig,
} from "./crm-configuration.contracts";

const valueTypes = new Set([
  "text",
  "textarea",
  "number",
  "money",
  "duration",
  "boolean",
  "toggle",
  "date",
  "datetime",
  "select",
  "radio",
  "multi_select",
  "checkbox_group",
  "email",
  "phone",
  "url",
]);
const placementTypes = new Set(["create", "edit", "card", "table"]);
const widthTypes = new Set(["third", "half", "full"]);
const settingDefinitions = {
  default_lesson_duration_minutes: { min: 15, max: 240 },
  payment_reminder_days: { min: 0, max: 60 },
} as const;
const settlementContexts = new Set(["settle", "reschedule", "cancel"]);
const settlementDurationModes = new Set(["zero", "full", "manual"]);
const compensationModes = new Set([
  "none",
  "standard",
  "percent",
  "fixed",
  "hourly",
]);

export function normalizeCrmConfigurationSnapshot(
  raw: Record<string, unknown>,
): ConfigSnapshot {
  const categories = normalizeCategories(raw.categories);
  const fields = normalizeFields(
    raw.fields,
    new Set(categories.map((category) => category.key)),
  );
  const optionSets = normalizeOptionSets(raw.optionSets ?? []);
  applyOptionSets(fields, optionSets);
  return {
    categories,
    fields,
    optionSets,
    businessSettings: normalizeBusinessSettings(raw.businessSettings),
    lessonSettlementTypes: normalizeSettlementTypes(
      raw.lessonSettlementTypes,
    ),
    teacherCompensationRules: normalizeCompensationRules(
      raw.teacherCompensationRules,
    ),
  };
}

function normalizeCategories(raw: unknown): ConfigCategory[] {
  const categories = readArray(raw, "categories").map((item, index) => {
    const row = readObject(item, `categories.${index}`);
    return {
      key: readKey(row.key, `categories.${index}.key`),
      label: readText(row.label, `categories.${index}.label`, 80),
      order: readInteger(row.order, `categories.${index}.order`, 0, 1000),
      active: readBoolean(row.active, `categories.${index}.active`),
    };
  });
  assertUnique(
    categories.map((row) => row.key),
    "categories",
    "DUPLICATE_CATEGORY",
  );
  return categories;
}

function normalizeFields(
  raw: unknown,
  categoryKeys: Set<string>,
): ConfigField[] {
  const parsedFields = readArray(raw, "fields").map((item, index) =>
    normalizeField(item, index, categoryKeys),
  );
  return mergeLegacyFields(parsedFields);
}

function normalizeField(
  item: unknown,
  index: number,
  categoryKeys: Set<string>,
): ConfigField {
  const row = readObject(item, `fields.${index}`);
  const visibility = normalizeFieldVisibility(row, index);
  const valueType = normalizeFieldValueType(row, index);
  const categoryKey = normalizeFieldCategoryKey(row, index, categoryKeys);
  const width = normalizeFieldWidth(row, index);
  const placements = normalizeFieldPlacements(row, index);
  const options = normalizeFieldOptions(row, index);
  const system = readBoolean(row.system, `fields.${index}.system`);
  const active = readBoolean(row.active, `fields.${index}.active`);
  assertActiveFieldVisibility(active, visibility, index);
  assertSelectableFieldOptions(row, index, system, valueType, options);
  return {
    ...(typeof row.id === "string" ? { id: row.id } : {}),
    key: readKey(row.key, `fields.${index}.key`),
    label: readText(row.label, `fields.${index}.label`, 120),
    valueType,
    required: readBoolean(row.required, `fields.${index}.required`),
    active,
    system,
    categoryKey,
    order: readInteger(row.order, `fields.${index}.order`, 0, 10000),
    width,
    placements,
    options,
    visibility,
    ...(typeof row.optionSetKey === "string" && row.optionSetKey.trim()
      ? {
          optionSetKey: readKey(
            row.optionSetKey,
            `fields.${index}.optionSetKey`,
          ),
        }
      : {}),
  };
}

function normalizeFieldVisibility(
  row: Record<string, unknown>,
  index: number,
): ConfigField["visibility"] {
  if (row.visibility !== undefined) {
    const visibility = readObject(
      row.visibility,
      `fields.${index}.visibility`,
    );
    return {
      lead: readBoolean(visibility.lead, `fields.${index}.visibility.lead`),
      student: readBoolean(
        visibility.student,
        `fields.${index}.visibility.student`,
      ),
    };
  }
  if (row.entityType === "lead") {
    return { lead: true, student: false };
  }
  if (row.entityType === "student") {
    return { lead: false, student: true };
  }
  return { lead: true, student: true };
}

function normalizeFieldValueType(
  row: Record<string, unknown>,
  index: number,
): string {
  const valueType = readText(
    row.valueType,
    `fields.${index}.valueType`,
    32,
  );
  if (!valueTypes.has(valueType)) {
    invalid(
      `fields.${index}.valueType`,
      "INVALID_TYPE",
      "Тип поля не поддерживается.",
    );
  }
  return valueType;
}

function normalizeFieldCategoryKey(
  row: Record<string, unknown>,
  index: number,
  categoryKeys: Set<string>,
): string {
  const categoryKey = readKey(
    row.categoryKey,
    `fields.${index}.categoryKey`,
  );
  if (!categoryKeys.has(categoryKey)) {
    invalid(
      `fields.${index}.categoryKey`,
      "UNKNOWN_CATEGORY",
      "Категория не найдена.",
    );
  }
  return categoryKey;
}

function normalizeFieldWidth(
  row: Record<string, unknown>,
  index: number,
): string {
  const width = readText(row.width, `fields.${index}.width`, 16);
  if (!widthTypes.has(width)) {
    invalid(
      `fields.${index}.width`,
      "INVALID_WIDTH",
      "Ширина поля не поддерживается.",
    );
  }
  return width;
}

function normalizeFieldPlacements(
  row: Record<string, unknown>,
  index: number,
): string[] {
  const placements = readArray(
    row.placements,
    `fields.${index}.placements`,
  ).map((placement, placementIndex) => {
    const value = readText(
      placement,
      `fields.${index}.placements.${placementIndex}`,
      16,
    );
    if (!placementTypes.has(value)) {
      invalid(
        `fields.${index}.placements.${placementIndex}`,
        "INVALID_PLACEMENT",
        "Размещение поля не поддерживается.",
      );
    }
    return value;
  });
  return [...new Set(placements)];
}

function normalizeFieldOptions(
  row: Record<string, unknown>,
  index: number,
): string[] {
  const options = readArray(
    row.options ?? [],
    `fields.${index}.options`,
  ).map((option, optionIndex) =>
    readText(option, `fields.${index}.options.${optionIndex}`, 160),
  );
  return [...new Set(options)];
}

function assertActiveFieldVisibility(
  active: boolean,
  visibility: ConfigField["visibility"],
  index: number,
): void {
  if (!active) return;
  if (visibility.lead || visibility.student) return;
  invalid(
    `fields.${index}.visibility`,
    "FIELD_VISIBILITY_REQUIRED",
    "Активное поле должно быть видно хотя бы в одной карточке.",
  );
}

function assertSelectableFieldOptions(
  row: Record<string, unknown>,
  index: number,
  system: boolean,
  valueType: string,
  options: string[],
): void {
  if (system) return;
  if (
    !new Set(["select", "radio", "multi_select", "checkbox_group"]).has(
      valueType,
    )
  ) {
    return;
  }
  if (options.length > 0) return;
  if (typeof row.optionSetKey === "string") return;
  invalid(
    `fields.${index}.options`,
    "OPTIONS_REQUIRED",
    "Добавьте хотя бы один вариант.",
  );
}

function mergeLegacyFields(parsedFields: ConfigField[]): ConfigField[] {
  const fieldsByKey = new Map<string, ConfigField>();
  for (const field of parsedFields) {
    const existing = fieldsByKey.get(field.key);
    if (!existing) {
      fieldsByKey.set(field.key, field);
      continue;
    }
    if (existing.valueType !== field.valueType) {
      invalid(
        `fields.${field.key}.valueType`,
        "INCOMPATIBLE_DUPLICATE_FIELD",
        "Старые копии поля Lead/Student имеют разные типы.",
      );
    }
    existing.visibility = {
      lead: existing.visibility.lead || field.visibility.lead,
      student: existing.visibility.student || field.visibility.student,
    };
    existing.required = existing.required || field.required;
    existing.active = existing.active || field.active;
    existing.system = existing.system || field.system;
    existing.options = [...new Set([...existing.options, ...field.options])];
    existing.order = Math.min(existing.order, field.order);
    if (
      existing.optionSetKey &&
      field.optionSetKey &&
      existing.optionSetKey !== field.optionSetKey
    ) {
      delete existing.optionSetKey;
    } else if (!existing.optionSetKey && field.optionSetKey) {
      existing.optionSetKey = field.optionSetKey;
    }
  }
  return [...fieldsByKey.values()];
}

function normalizeOptionSets(raw: unknown): ConfigOptionSet[] {
  const optionSets = readArray(raw, "optionSets").map((item, index) => {
    const row = readObject(item, `optionSets.${index}`);
    const options = readArray(
      row.options,
      `optionSets.${index}.options`,
    ).map((option, optionIndex) => {
      const value = readObject(
        option,
        `optionSets.${index}.options.${optionIndex}`,
      );
      return {
        key: readKey(
          value.key,
          `optionSets.${index}.options.${optionIndex}.key`,
        ),
        label: readText(
          value.label,
          `optionSets.${index}.options.${optionIndex}.label`,
          160,
        ),
        order: readInteger(
          value.order,
          `optionSets.${index}.options.${optionIndex}.order`,
          0,
          1000,
        ),
        active: readBoolean(
          value.active,
          `optionSets.${index}.options.${optionIndex}.active`,
        ),
      };
    });
    assertUnique(
      options.map((option) => option.key),
      `optionSets.${index}.options`,
      "DUPLICATE_OPTION",
    );
    return {
      key: readKey(row.key, `optionSets.${index}.key`),
      label: readText(row.label, `optionSets.${index}.label`, 120),
      multiple: readBoolean(row.multiple, `optionSets.${index}.multiple`),
      options,
    };
  });
  assertUnique(
    optionSets.map((set) => set.key),
    "optionSets",
    "DUPLICATE_OPTION_SET",
  );
  return optionSets;
}

function applyOptionSets(
  fields: ConfigField[],
  optionSets: ConfigOptionSet[],
): void {
  const optionSetsByKey = new Map(optionSets.map((set) => [set.key, set]));
  for (const field of fields) {
    if (!field.optionSetKey) continue;
    const optionSet = optionSetsByKey.get(field.optionSetKey);
    if (!optionSet) {
      invalid(
        `fields.${field.key}.optionSetKey`,
        "UNKNOWN_OPTION_SET",
        "Выбранный справочник не найден.",
      );
    }
    field.options = optionSet.options
      .filter((option) => option.active)
      .sort((left, right) => left.order - right.order)
      .map((option) => option.label);
  }
}

function normalizeBusinessSettings(raw: unknown): ConfigSetting[] {
  const businessSettings = readArray(raw, "businessSettings").map(
    (item, index) => {
      const row = readObject(item, `businessSettings.${index}`);
      const key = readKey(row.key, `businessSettings.${index}.key`);
      const definition =
        settingDefinitions[key as keyof typeof settingDefinitions];
      if (!definition) {
        invalid(
          `businessSettings.${index}.key`,
          "UNKNOWN_SETTING",
          "Параметр не входит в безопасный список.",
        );
      }
      const value = readNumber(row.value, `businessSettings.${index}.value`);
      if (value < definition.min || value > definition.max) {
        invalid(
          `businessSettings.${index}.value`,
          "SETTING_OUT_OF_RANGE",
          `Допустимо ${definition.min}–${definition.max}.`,
        );
      }
      return {
        key: key as ConfigSetting["key"],
        label: readText(row.label, `businessSettings.${index}.label`, 120),
        valueType: "integer" as const,
        unit: readText(row.unit, `businessSettings.${index}.unit`, 20),
        min: definition.min,
        max: definition.max,
        value,
        branchOverridable: readBoolean(
          row.branchOverridable,
          `businessSettings.${index}.branchOverridable`,
        ),
      };
    },
  );
  assertUnique(
    businessSettings.map((setting) => setting.key),
    "businessSettings",
    "DUPLICATE_SETTING",
  );
  return businessSettings;
}

function normalizeSettlementTypes(raw: unknown): LessonSettlementTypeConfig[] {
  const settlementTypes = readArray(raw, "lessonSettlementTypes")
    .map((item, index) => {
      const row = readObject(item, `lessonSettlementTypes.${index}`);
      const allowedContexts = readArray(
        row.allowedContexts,
        `lessonSettlementTypes.${index}.allowedContexts`,
      ).map((context, contextIndex) => {
        const value = readText(
          context,
          `lessonSettlementTypes.${index}.allowedContexts.${contextIndex}`,
          32,
        );
        if (!settlementContexts.has(value)) {
          invalid(
            `lessonSettlementTypes.${index}.allowedContexts.${contextIndex}`,
            "INVALID_SETTLEMENT_CONTEXT",
            "Допустимы settle, reschedule и cancel.",
          );
        }
        return value;
      });
      if (allowedContexts.length === 0) {
        invalid(
          `lessonSettlementTypes.${index}.allowedContexts`,
          "SETTLEMENT_CONTEXT_REQUIRED",
          "Укажите хотя бы один допустимый сценарий.",
        );
      }
      const hourShareBasisPoints = readInteger(
        row.hourShareBasisPoints,
        `lessonSettlementTypes.${index}.hourShareBasisPoints`,
        0,
        20000,
      );
      const legacyPolicy = legacySettlementPolicy(hourShareBasisPoints);
      return {
        stableKey: readKey(
          row.stableKey,
          `lessonSettlementTypes.${index}.stableKey`,
        ),
        label: readText(
          row.label,
          `lessonSettlementTypes.${index}.label`,
          120,
        ),
        colorToken: readToken(
          row.colorToken,
          `lessonSettlementTypes.${index}.colorToken`,
        ),
        hourShareBasisPoints,
        clientDurationMode: row.clientDurationMode === undefined
          ? legacyPolicy.durationMode
          : readSettlementDurationMode(
              row.clientDurationMode,
              `lessonSettlementTypes.${index}.clientDurationMode`,
            ),
        teacherDurationMode: row.teacherDurationMode === undefined
          ? legacyPolicy.durationMode
          : readSettlementDurationMode(
              row.teacherDurationMode,
              `lessonSettlementTypes.${index}.teacherDurationMode`,
            ),
        defaultTeacherCompensationRuleKey:
          row.defaultTeacherCompensationRuleKey === undefined
            ? legacyPolicy.teacherCompensationRuleKey
            : readKey(
                row.defaultTeacherCompensationRuleKey,
                `lessonSettlementTypes.${index}.defaultTeacherCompensationRuleKey`,
              ),
        ...(row.fixedPenaltyMinor === undefined ||
        row.fixedPenaltyMinor === null
          ? {}
          : {
              fixedPenaltyMinor: readMinor(
                row.fixedPenaltyMinor,
                `lessonSettlementTypes.${index}.fixedPenaltyMinor`,
              ),
            }),
        allowedContexts: [...new Set(allowedContexts)].sort(),
        active: readBoolean(
          row.active,
          `lessonSettlementTypes.${index}.active`,
        ),
        order: readInteger(
          row.order,
          `lessonSettlementTypes.${index}.order`,
          0,
          1000,
        ),
      };
    })
    .sort(
      (left, right) =>
        left.order - right.order ||
        left.stableKey.localeCompare(right.stableKey),
    );
  assertUnique(
    settlementTypes.map((type) => type.stableKey),
    "lessonSettlementTypes",
    "DUPLICATE_SETTLEMENT_TYPE",
  );
  if (!settlementTypes.some((type) => type.active)) {
    invalid(
      "lessonSettlementTypes",
      "ACTIVE_SETTLEMENT_TYPE_REQUIRED",
      "Оставьте активным хотя бы один тип списания.",
    );
  }
  return settlementTypes;
}

function legacySettlementPolicy(hourShareBasisPoints: number): {
  durationMode: LessonSettlementTypeConfig["clientDurationMode"];
  teacherCompensationRuleKey: string;
} {
  if (hourShareBasisPoints === 0) {
    return { durationMode: "zero", teacherCompensationRuleKey: "none" };
  }
  if (hourShareBasisPoints === 10_000) {
    return { durationMode: "full", teacherCompensationRuleKey: "standard" };
  }
  return { durationMode: "manual", teacherCompensationRuleKey: "percent" };
}

function readSettlementDurationMode(
  value: unknown,
  field: string,
): LessonSettlementTypeConfig["clientDurationMode"] {
  const mode = readText(value, field, 16);
  if (!settlementDurationModes.has(mode)) {
    invalid(
      field,
      "INVALID_SETTLEMENT_DURATION_MODE",
      "Допустимы zero, full и manual.",
    );
  }
  return mode as LessonSettlementTypeConfig["clientDurationMode"];
}

function normalizeCompensationRules(
  raw: unknown,
): TeacherCompensationRuleConfig[] {
  const compensationRules = readArray(raw, "teacherCompensationRules")
    .map(normalizeCompensationRule)
    .sort(
      (left, right) =>
        left.order - right.order ||
        left.stableKey.localeCompare(right.stableKey),
    );
  assertUnique(
    compensationRules.map((rule) => rule.stableKey),
    "teacherCompensationRules",
    "DUPLICATE_COMPENSATION_RULE",
  );
  if (!compensationRules.some((rule) => rule.active)) {
    invalid(
      "teacherCompensationRules",
      "ACTIVE_COMPENSATION_RULE_REQUIRED",
      "Оставьте активным хотя бы один тип оплаты преподавателю.",
    );
  }
  return compensationRules;
}

function normalizeCompensationRule(
  item: unknown,
  index: number,
): TeacherCompensationRuleConfig {
  const row = readObject(item, `teacherCompensationRules.${index}`);
  const mode = readText(
    row.mode,
    `teacherCompensationRules.${index}.mode`,
    16,
  ) as TeacherCompensationRuleConfig["mode"];
  if (!compensationModes.has(mode)) {
    invalid(
      `teacherCompensationRules.${index}.mode`,
      "INVALID_COMPENSATION_MODE",
      "Режим оплаты преподавателю не поддерживается.",
    );
  }
  const value = readMinor(
    row.value,
    `teacherCompensationRules.${index}.value`,
  );
  assertCompensationValue(mode, value, index);
  return {
    stableKey: readKey(
      row.stableKey,
      `teacherCompensationRules.${index}.stableKey`,
    ),
    label: readText(
      row.label,
      `teacherCompensationRules.${index}.label`,
      120,
    ),
    mode,
    value,
    active: readBoolean(
      row.active,
      `teacherCompensationRules.${index}.active`,
    ),
    order: readInteger(
      row.order,
      `teacherCompensationRules.${index}.order`,
      0,
      1000,
    ),
  };
}

function assertCompensationValue(
  mode: TeacherCompensationRuleConfig["mode"],
  value: string,
  index: number,
): void {
  if (mode === "percent") {
    if (BigInt(value) <= 20000n) return;
    invalid(
      `teacherCompensationRules.${index}.value`,
      "INVALID_COMPENSATION_VALUE",
      "Процент задаётся в basis points от 0 до 20000.",
    );
  }
  if (mode !== "none" && mode !== "standard") return;
  if (value === "0") return;
  invalid(
    `teacherCompensationRules.${index}.value`,
    "INVALID_COMPENSATION_VALUE",
    "Для none/standard значение должно быть равно нулю.",
  );
}

function readArray(value: unknown, field: string): unknown[] {
  if (!Array.isArray(value)) {
    invalid(field, "ARRAY_REQUIRED", "Ожидается список.");
  }
  return value as unknown[];
}

function readObject(value: unknown, field: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    invalid(field, "OBJECT_REQUIRED", "Ожидается объект.");
  }
  return value as Record<string, unknown>;
}

function readText(value: unknown, field: string, max: number): string {
  if (
    typeof value !== "string" ||
    !value.trim() ||
    value.trim().length > max
  ) {
    invalid(
      field,
      "INVALID_TEXT",
      `Заполните значение длиной до ${max} символов.`,
    );
  }
  return (value as string).trim();
}

function readToken(value: unknown, field: string): string {
  const token = readText(value, field, 80);
  if (!/^[A-Za-z][A-Za-z0-9._:-]{0,79}$/.test(token)) {
    invalid(
      field,
      "INVALID_TOKEN",
      "Токен должен начинаться с буквы и содержать только безопасные символы.",
    );
  }
  return token;
}

function readMinor(value: unknown, field: string): string {
  if (typeof value !== "string" || !/^(0|[1-9][0-9]{0,14})$/.test(value)) {
    invalid(
      field,
      "INVALID_MINOR_VALUE",
      "Значение указывается целым числом минимальных денежных единиц.",
    );
  }
  return value as string;
}

function readKey(value: unknown, field: string): string {
  const key = readText(value, field, 64);
  if (!/^[A-Za-z][A-Za-z0-9_-]{0,63}$/.test(key)) {
    invalid(
      field,
      "INVALID_KEY",
      "Ключ должен начинаться с буквы и содержать только буквы, цифры, _ или -.",
    );
  }
  return key;
}

function readBoolean(value: unknown, field: string): boolean {
  if (typeof value !== "boolean") {
    invalid(field, "BOOLEAN_REQUIRED", "Ожидается да/нет.");
  }
  return value as boolean;
}

function readNumber(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    invalid(field, "NUMBER_REQUIRED", "Ожидается число.");
  }
  return value as number;
}

function readInteger(
  value: unknown,
  field: string,
  min: number,
  max: number,
): number {
  const number = readNumber(value, field);
  if (!Number.isInteger(number) || number < min || number > max) {
    invalid(
      field,
      "INTEGER_OUT_OF_RANGE",
      `Допустимо целое число ${min}–${max}.`,
    );
  }
  return number;
}

function assertUnique(values: string[], field: string, code: string): void {
  if (new Set(values).size !== values.length) {
    invalid(field, code, "Ключи должны быть уникальными.");
  }
}

function invalid(field: string, code: string, message: string): never {
  throw new UnprocessableEntityException({ code, field, message });
}
