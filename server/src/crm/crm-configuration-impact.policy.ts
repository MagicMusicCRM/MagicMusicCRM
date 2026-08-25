import { sameCrmConfigurationValue } from "./crm-configuration-branch.policy";
import type {
  ConfigField,
  ConfigSnapshot,
  ImpactReport,
} from "./crm-configuration.contracts";

export interface CrmConfigurationImpactInput {
  next: ConfigSnapshot;
  current: ConfigSnapshot;
  school?: ConfigSnapshot;
  hasStoredClientFieldValues: (definitionId: string) => Promise<boolean>;
}

type BlockingIssue = ImpactReport["blockingIssues"][number];

export async function buildCrmConfigurationImpact(
  input: CrmConfigurationImpactInput,
): Promise<ImpactReport> {
  const blockingIssues: BlockingIssue[] = [];
  collectBranchIssues(blockingIssues, input.next, input.school);
  collectStableCatalogIssues(blockingIssues, input.current, input.next);
  await collectFieldIssues(blockingIssues, input);
  return summarizeImpact(blockingIssues, input.current, input.next);
}

function collectBranchIssues(
  blockingIssues: BlockingIssue[],
  next: ConfigSnapshot,
  school?: ConfigSnapshot,
): void {
  if (!school) return;
  for (const key of ["categories", "fields", "optionSets"] as const) {
    if (!sameCrmConfigurationValue(next[key], school[key])) {
      blockingIssues.push({
        field: key,
        code: "BRANCH_SCHEMA_OVERRIDE_FORBIDDEN",
        message: "Филиал может переопределять только бизнес-параметры.",
      });
    }
  }
  const schoolSettings = new Map(
    school.businessSettings.map((setting) => [setting.key, setting]),
  );
  for (const setting of next.businessSettings) {
    if (
      setting.value !== schoolSettings.get(setting.key)?.value &&
      !schoolSettings.get(setting.key)?.branchOverridable
    ) {
      blockingIssues.push({
        field: `businessSettings.${setting.key}`,
        code: "BRANCH_OVERRIDE_FORBIDDEN",
        message: "Параметр не допускает филиальное переопределение.",
      });
    }
  }
}

function collectStableCatalogIssues(
  blockingIssues: BlockingIssue[],
  current: ConfigSnapshot,
  next: ConfigSnapshot,
): void {
  for (const [field, previous, following] of [
    [
      "lessonSettlementTypes",
      current.lessonSettlementTypes,
      next.lessonSettlementTypes,
    ],
    [
      "teacherCompensationRules",
      current.teacherCompensationRules,
      next.teacherCompensationRules,
    ],
  ] as const) {
    const nextKeys = new Set(following.map((item) => item.stableKey));
    for (const item of previous) {
      if (!nextKeys.has(item.stableKey)) {
        blockingIssues.push({
          field: `${field}.${item.stableKey}`,
          code: "CATALOG_KEY_REMOVAL_FORBIDDEN",
          message:
            "Стабильный ключ нельзя удалить или переименовать; архивируйте тип.",
        });
      }
    }
  }
}

async function collectFieldIssues(
  blockingIssues: BlockingIssue[],
  input: CrmConfigurationImpactInput,
): Promise<void> {
  const currentFields = new Map(
    input.current.fields.map((field) => [field.key, field]),
  );
  for (const field of input.next.fields) {
    const before = currentFields.get(field.key);
    if (!before) continue;
    if (
      before.system &&
      (field.valueType !== before.valueType || !field.active)
    ) {
      blockingIssues.push({
        field: `fields.${field.key}`,
        code: "SYSTEM_FIELD_LOCKED",
        message: "Тип и активность системного поля защищены.",
      });
    }
    if (
      before.valueType !== field.valueType &&
      before.id &&
      (await input.hasStoredClientFieldValues(before.id))
    ) {
      blockingIssues.push({
        field: `fields.${field.key}.valueType`,
        code: "FIELD_TYPE_MIGRATION_REQUIRED",
        message: "Поле с сохранёнными значениями нельзя перевести в другой тип.",
      });
    }
  }
}

function summarizeImpact(
  blockingIssues: BlockingIssue[],
  current: ConfigSnapshot,
  next: ConfigSnapshot,
): ImpactReport {
  const currentFields = new Map(
    current.fields.map((field) => [field.key, field]),
  );
  const nextFields = new Map(next.fields.map((field) => [field.key, field]));
  const fieldChanged = (field: ConfigField) =>
    JSON.stringify(field) !== JSON.stringify(currentFields.get(field.key));
  const settings = new Map(
    current.businessSettings.map((setting) => [setting.key, setting.value]),
  );
  const settingsChanged = next.businessSettings.filter(
    (setting) => settings.get(setting.key) !== setting.value,
  ).length;
  const settlementTypesChanged = countChangedCatalogItems(
    next.lessonSettlementTypes,
    current.lessonSettlementTypes,
  );
  const compensationRulesChanged = countChangedCatalogItems(
    next.teacherCompensationRules,
    current.teacherCompensationRules,
  );
  const hasFieldChanges =
    next.fields.some(fieldChanged) ||
    current.fields.some((field) => !nextFields.has(field.key));
  return {
    valid: blockingIssues.length === 0,
    blockingIssues,
    warnings: [
      ...(settingsChanged > 0
        ? ["Новые значения применятся только к будущим бизнес-снимкам."]
        : []),
      ...(settlementTypesChanged > 0 || compensationRulesChanged > 0
        ? [
            "Новые правила применятся только к будущим решениям; история сохранит прежние снимки.",
          ]
        : []),
    ],
    changes: {
      fieldsCreated: next.fields.filter(
        (field) => !currentFields.has(field.key),
      ).length,
      fieldsUpdated: next.fields.filter(
        (field) => currentFields.has(field.key) && fieldChanged(field),
      ).length,
      fieldsArchived: current.fields.filter(
        (field) => !nextFields.has(field.key),
      ).length,
      settingsChanged,
      settlementTypesChanged,
      compensationRulesChanged,
    },
    affectedScreens: [
      ...(hasFieldChanges
        ? ["lead.create", "student.create", "client.card.custom_fields"]
        : []),
      ...(settingsChanged
        ? ["schedule.lesson.create", "client.payments"]
        : []),
      ...(settlementTypesChanged > 0 ? ["schedule.lesson.decision"] : []),
      ...(compensationRulesChanged > 0 ? ["teacher.compensation"] : []),
    ],
  };
}

function countChangedCatalogItems<T extends { stableKey: string }>(
  following: T[],
  previous: T[],
): number {
  const previousByKey = new Map(
    previous.map((item) => [item.stableKey, item]),
  );
  return following.filter(
    (item) =>
      !sameCrmConfigurationValue(item, previousByKey.get(item.stableKey)),
  ).length;
}
