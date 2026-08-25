import type { ConfigSnapshot } from "./crm-configuration.contracts";

export interface ClientFieldDefinitionRow {
  id: string;
  field_key: string;
  label: string;
  value_type: string;
  is_required: boolean;
  is_active: boolean;
  is_system: boolean;
  category_key: string;
  category_label: string;
  sort_order: number;
  width: string;
  placements: string[];
  options: string[];
  visible_on_lead: boolean;
  visible_on_student: boolean;
}

export function buildCrmConfigurationBaseline(
  definitions: ClientFieldDefinitionRow[],
): ConfigSnapshot {
  const categoryLabels = new Map<string, string>();
  for (const definition of definitions) {
    categoryLabels.set(definition.category_key, definition.category_label);
  }
  if (categoryLabels.size === 0) {
    categoryLabels.set("general", "Основная информация");
  }

  return {
    categories: [...categoryLabels.entries()].map(([key, label], order) => ({
      key,
      label,
      order,
      active: true,
    })),
    fields: [...definitions]
      .sort(
        (left, right) =>
          left.sort_order - right.sort_order ||
          left.label.localeCompare(right.label),
      )
      .map((definition) => ({
        id: definition.id,
        key: definition.field_key,
        label: definition.label,
        valueType: definition.value_type,
        required: definition.is_required,
        active: definition.is_active,
        system: definition.is_system,
        categoryKey: definition.category_key,
        order: definition.sort_order,
        width: definition.width,
        placements: definition.placements,
        options: definition.options,
        visibility: {
          lead: definition.visible_on_lead,
          student: definition.visible_on_student,
        },
      })),
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
        allowedContexts: ["settle"],
        active: true,
        order: 0,
      },
      {
        stableKey: "partially_paid_lesson",
        label: "Частично оплачиваемое занятие",
        colorToken: "info",
        hourShareBasisPoints: 5000,
        allowedContexts: ["settle"],
        active: true,
        order: 1,
      },
      {
        stableKey: "free_lesson",
        label: "Бесплатное занятие",
        colorToken: "warning",
        hourShareBasisPoints: 0,
        allowedContexts: ["cancel", "reschedule", "settle"],
        active: true,
        order: 2,
      },
      {
        stableKey: "paid_miss",
        label: "Оплачиваемый пропуск",
        colorToken: "blue",
        hourShareBasisPoints: 10000,
        allowedContexts: ["cancel", "reschedule", "settle"],
        active: true,
        order: 3,
      },
      {
        stableKey: "partially_paid_miss",
        label: "Частично оплачиваемый пропуск",
        colorToken: "cyan",
        hourShareBasisPoints: 5000,
        allowedContexts: ["cancel", "reschedule", "settle"],
        active: true,
        order: 4,
      },
      {
        stableKey: "unpaid_miss",
        label: "Неоплачиваемый пропуск",
        colorToken: "neutral",
        hourShareBasisPoints: 0,
        allowedContexts: ["cancel", "reschedule", "settle"],
        active: true,
        order: 5,
      },
      {
        stableKey: "penalty_lesson",
        label: "Занятие со штрафом",
        colorToken: "violet",
        hourShareBasisPoints: 10000,
        fixedPenaltyMinor: "0",
        allowedContexts: ["cancel", "reschedule", "settle"],
        active: true,
        order: 6,
      },
    ],
    teacherCompensationRules: [
      {
        stableKey: "none",
        label: "Не оплачивать",
        mode: "none",
        value: "0",
        active: true,
        order: 0,
      },
      {
        stableKey: "standard",
        label: "Полная стандартная ставка",
        mode: "standard",
        value: "0",
        active: true,
        order: 1,
      },
      {
        stableKey: "percent",
        label: "Процент ставки",
        mode: "percent",
        value: "10000",
        active: true,
        order: 2,
      },
      {
        stableKey: "fixed",
        label: "Фиксированная сумма",
        mode: "fixed",
        value: "0",
        active: true,
        order: 3,
      },
      {
        stableKey: "hourly",
        label: "Почасовая сумма",
        mode: "hourly",
        value: "0",
        active: true,
        order: 4,
      },
    ],
  };
}
