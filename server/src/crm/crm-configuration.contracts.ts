export interface LessonSettlementTypeConfig {
  stableKey: string;
  label: string;
  colorToken: string;
  hourShareBasisPoints: number;
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
