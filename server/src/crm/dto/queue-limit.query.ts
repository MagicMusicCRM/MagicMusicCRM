import { Type } from "class-transformer";
import { IsInt, IsOptional, Max, Min } from "class-validator";

/** Shared query for list endpoints that only take an optional `limit`
 *  (phone-review queue, merge candidates). Validated + whitelisted. */
export class QueueLimitQuery {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(200)
  limit?: number;
}
