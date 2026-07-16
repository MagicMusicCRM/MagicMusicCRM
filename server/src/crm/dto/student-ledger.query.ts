import { Type } from "class-transformer";
import { IsIn, IsInt, IsOptional, Max, Min } from "class-validator";

/** Query for GET /crm/students/:id/ledger — replaces raw @Query strings with a
 *  validated, whitelisted DTO (unknown params are rejected by the global pipe). */
export class StudentLedgerQuery {
  // FinanceService only honours "income"/"outcome"; anything else is ignored, but
  // validate here so callers get a 400 instead of a silently dropped filter.
  @IsOptional()
  @IsIn(["income", "outcome"])
  direction?: "income" | "outcome";

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(300)
  limit?: number;
}
