import { IsIn, IsOptional } from "class-validator";
import { AnalyticsRangeQuery } from "./analytics-range.query";

export const FINANCE_DEBT_SEGMENTS = [
  "overdue",
  "remaining",
  "paid_unused",
  "forecast",
] as const;

export type FinanceDebtSegment = (typeof FINANCE_DEBT_SEGMENTS)[number];

export class FinanceDebtQuery extends AnalyticsRangeQuery {
  @IsOptional()
  @IsIn(FINANCE_DEBT_SEGMENTS)
  segment?: FinanceDebtSegment;
}
