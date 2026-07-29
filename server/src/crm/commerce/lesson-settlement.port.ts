import { PoolClient } from "pg";

export type ClientChargeFactType =
  | "subscription"
  | "personal_account"
  | "none";

export type TeacherCompensationFactType = "fixed" | "hourly" | "none";

export interface LessonSettlementResult {
  lessonId: string;
  clientFact: {
    id: string;
    clientType: "lead" | "student";
    clientId: string;
    chargeType: ClientChargeFactType;
    snapshotValue: string;
    subscriptionId: string | null;
    amountMinor: string;
    units: string;
    currencyCode: string;
  };
  teacherFact: {
    id: string;
    teacherId: string;
    compensationType: TeacherCompensationFactType;
    snapshotRate: string;
    rateMinor: string;
    durationMinutes: number;
    amountMinor: string;
    currencyCode: string;
  };
}

export interface LessonSettlementPort {
  settle(
    client: PoolClient,
    lessonId: string,
  ): Promise<LessonSettlementResult>;
}

export const LESSON_SETTLEMENT_PORT = Symbol("LESSON_SETTLEMENT_PORT");
