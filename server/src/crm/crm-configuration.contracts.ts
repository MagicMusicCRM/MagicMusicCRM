export type SettlementDurationMode = "zero" | "full" | "manual";

export interface LessonSettlementTypeConfig {
  stableKey: string;
  label: string;
  colorToken: string;
  hourShareBasisPoints: number;
  clientDurationMode: SettlementDurationMode;
  teacherDurationMode: SettlementDurationMode;
  defaultTeacherCompensationRuleKey: string;
  fixedPenaltyMinor?: string;
  allowedContexts: string[];
  active: boolean;
  order: number;
}

export interface TeacherCompensationRuleConfig {
  stableKey: string;
  label: string;
  mode: "none" | "standard" | "percent" | "fixed" | "hourly";
  value: string;
  active: boolean;
  order: number;
}

export interface ConfigCategory {
  key: string;
  label: string;
  order: number;
  active: boolean;
}

export interface ConfigField {
  id?: string;
  key: string;
  label: string;
  valueType: string;
  required: boolean;
  active: boolean;
  system: boolean;
  categoryKey: string;
  order: number;
  width: string;
  placements: string[];
  options: string[];
  optionSetKey?: string;
  visibility: {
    lead: boolean;
    student: boolean;
  };
}

export interface ConfigOptionSet {
  key: string;
  label: string;
  multiple: boolean;
  options: Array<{
    key: string;
    label: string;
    order: number;
    active: boolean;
  }>;
}

export interface ConfigSetting {
  key: "default_lesson_duration_minutes" | "payment_reminder_days";
  label: string;
  valueType: "integer";
  unit: string;
  min: number;
  max: number;
  value: number;
  branchOverridable: boolean;
}

export interface ConfigSnapshot {
  categories: ConfigCategory[];
  fields: ConfigField[];
  optionSets: ConfigOptionSet[];
  businessSettings: ConfigSetting[];
  lessonSettlementTypes: LessonSettlementTypeConfig[];
  teacherCompensationRules: TeacherCompensationRuleConfig[];
}

export interface ConfigBranchPatch {
  businessSettings: ConfigSetting[];
  lessonSettlementTypes?: LessonSettlementTypeConfig[];
  teacherCompensationRules?: TeacherCompensationRuleConfig[];
}

export interface ImpactReport {
  valid: boolean;
  blockingIssues: Array<{ field: string; code: string; message: string }>;
  warnings: string[];
  changes: {
    fieldsCreated: number;
    fieldsUpdated: number;
    fieldsArchived: number;
    settingsChanged: number;
    settlementTypesChanged: number;
    compensationRulesChanged: number;
  };
  affectedScreens: string[];
}
