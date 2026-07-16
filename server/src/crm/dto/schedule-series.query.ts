import { Transform } from "class-transformer";
import { IsBoolean, IsDateString, IsOptional, IsUUID } from "class-validator";

/** Query for GET /crm/schedule-series — validated, whitelisted replacement for
 *  the raw @Query("studentId"/"groupId"/"includeExpired") strings. */
export class ScheduleSeriesQuery {
  @IsOptional()
  @IsUUID()
  studentId?: string;

  @IsOptional()
  @IsUUID()
  groupId?: string;

  @IsOptional()
  @Transform(({ value }) => value === true || value === "true")
  @IsBoolean()
  includeExpired?: boolean;
}

/** Query for DELETE /crm/schedule-series/:id — the optional `from` cut-off date. */
export class ScheduleSeriesDeleteQuery {
  @IsOptional()
  @IsDateString()
  from?: string;
}
