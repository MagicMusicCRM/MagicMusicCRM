import { IsIn, IsOptional, Matches } from "class-validator";
import { AnalyticsRangeQuery } from "./analytics-range.query";

export const SALES_CLIENT_SEGMENTS = [
  "inquiries",
  "trial_booked",
  "trial_attended",
  "purchases",
  "first_paid",
  "without_trial",
  "stalled",
] as const;

export type SalesClientSegment = (typeof SALES_CLIENT_SEGMENTS)[number];

export class SalesClientsQuery extends AnalyticsRangeQuery {
  @IsOptional()
  @IsIn(SALES_CLIENT_SEGMENTS)
  segment?: SalesClientSegment;

  @IsOptional()
  @Matches(
    /^(none|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12})$/,
  )
  sourceId?: string;
}
