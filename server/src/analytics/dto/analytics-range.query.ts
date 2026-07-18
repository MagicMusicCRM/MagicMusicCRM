import { Type } from "class-transformer";
import {
  IsDateString,
  IsInt,
  IsOptional,
  IsUUID,
  Max,
  Min,
} from "class-validator";

/**
 * Shared query DTO for every /analytics route. Previously each route bound an
 * inline TS type — a non-class metatype the global ValidationPipe skips, so
 * bad dates/branchIds flowed raw into SQL and typo'd param names were
 * silently ignored (unfiltered data instead of a 400). The Flutter client
 * sends exactly from/to (ISO datetime), branchId (uuid) and inactiveDays.
 */
export class AnalyticsRangeQuery {
  @IsOptional()
  @IsDateString()
  from?: string;

  @IsOptional()
  @IsDateString()
  to?: string;

  @IsOptional()
  @IsUUID()
  branchId?: string;

  // churn-risk only; harmless elsewhere.
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(365)
  inactiveDays?: number;
}
