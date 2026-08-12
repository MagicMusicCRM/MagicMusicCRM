import { Transform, Type } from "class-transformer";
import {
  IsBoolean,
  IsDateString,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  Max,
  MaxLength,
  Min,
  Validate,
  ValidationArguments,
  ValidatorConstraint,
  ValidatorConstraintInterface,
} from "class-validator";

const LEAD_BOARD_CURSOR_PATTERN =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{1,6}Z\|[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

@ValidatorConstraint({ name: "leadBoardStatusScope", async: false })
class LeadBoardStatusScopeConstraint implements ValidatorConstraintInterface {
  validate(_value: unknown, args: ValidationArguments) {
    const query = args.object as LeadBoardQuery;
    return !(query.statusId && query.unassigned === true);
  }

  defaultMessage() {
    return "statusId and unassigned=true are mutually exclusive";
  }
}

export class LeadBoardQuery {
  @IsOptional()
  @IsString()
  @MaxLength(160)
  q?: string;

  @IsOptional()
  @IsUUID()
  @Validate(LeadBoardStatusScopeConstraint)
  statusId?: string;

  /** Explicitly selects the synthetic "Без статуса" board column. */
  @IsOptional()
  @Transform(({ value }) => {
    if (value === "true") return true;
    if (value === "false") return false;
    return value;
  })
  @IsBoolean()
  unassigned?: boolean;

  @IsOptional()
  @IsUUID()
  branchId?: string;

  @IsOptional()
  @IsUUID()
  assignedTo?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  source?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  discipline?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  level?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  category?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  requestType?: string;

  @IsOptional()
  @IsString()
  @MaxLength(160)
  goal?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  gender?: string;

  @IsOptional()
  @IsString()
  @MaxLength(160)
  preferredSchedule?: string;

  @IsOptional()
  @IsDateString()
  from?: string;

  @IsOptional()
  @IsDateString()
  to?: string;

  @IsOptional()
  @IsIn(["newest", "oldest"])
  sort?: "newest" | "oldest";

  @IsOptional()
  @IsIn(["all", "active", "processed", "deferred", "new"])
  quick?: "all" | "active" | "processed" | "deferred" | "new";

  @IsOptional()
  @Transform(({ value }) => value === true || value === "true")
  @IsBoolean()
  openTasks?: boolean;

  @IsOptional()
  @Transform(({ value }) => value === true || value === "true")
  @IsBoolean()
  hideConverted?: boolean;

  @IsOptional()
  @IsString()
  @Matches(LEAD_BOARD_CURSOR_PATTERN)
  @MaxLength(180)
  cursor?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(50)
  limit?: number;
}
