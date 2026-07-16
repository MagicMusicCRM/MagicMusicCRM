import { Type } from "class-transformer";
import { IsIn, IsInt, IsOptional, IsUUID, Max, Min } from "class-validator";

/**
 * Filters for the supervisor control feed. `field` defaults to 'due_at' in the
 * service — that is the case the customer asked to control («кто какие задачи
 * когда переносит») — but the whitelist keeps the value out of raw SQL reach.
 */
export class TaskHistoryQuery {
  @IsOptional()
  @IsIn(["created", "status", "due_at", "assigned_to", "title", "description", "entity"])
  field?: string;

  @IsOptional()
  @IsUUID()
  changedBy?: string;

  @IsOptional()
  from?: string;

  @IsOptional()
  to?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(200)
  limit?: number;
}
