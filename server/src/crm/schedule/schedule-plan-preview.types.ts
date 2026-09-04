import type { PreparedLessonSettlementPlan } from "../commerce/lesson-settlement.port";
import type { SchedulePlanRowDto } from "../dto/schedule-plan.dto";
import { groupScheduleConflicts } from "./schedule-analyzer";
import type { SchedulePlanRowPreview } from "./schedule-plan-overlap-analyzer";

export interface SchedulePlanConstraintProjection {
  valid: boolean;
  conflicts: ReturnType<typeof groupScheduleConflicts>;
  rows: Array<{
    index: number;
    valid: boolean;
    occurrencesChecked: number;
    failures: SchedulePlanRowPreview["failures"];
    suggestions: SchedulePlanRowPreview["suggestions"];
  }>;
  historical: SchedulePlanHistoricalProjection;
}

export interface SchedulePlanHistoricalOccurrence {
  rowIndex: number;
  localDate: string;
  startAt: string;
  endAt: string;
}

export interface SchedulePlanHistoricalProjection {
  confirmRequired: boolean;
  count: number;
  from: string | null;
  until: string | null;
  occurrences: SchedulePlanHistoricalOccurrence[];
  previewToken?: string;
  previewExpiresAt?: string;
}

export interface PreparedSchedulePlanRow {
  row: SchedulePlanRowDto;
  settlementPlan: PreparedLessonSettlementPlan;
}
