import { Type } from "class-transformer";
import {
  ArrayMinSize,
  IsArray,
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
  ValidateIf,
  ValidateNested,
} from "class-validator";

export class SharedTaskAudienceDto {
  @IsIn(["user", "branch", "allBranches"])
  type!: "user" | "branch" | "allBranches";

  @ValidateIf((value: SharedTaskAudienceDto) => value.type !== "allBranches")
  @IsUUID()
  targetId?: string;
}

export class SharedTaskEntityLinkDto {
  @IsString()
  @MaxLength(80)
  type!: string;

  @IsUUID()
  id!: string;
}

export class SharedTaskReminderDto {
  @IsDateString()
  dueAt!: string;

  @IsIn(["in_app", "push", "email"])
  channel!: "in_app" | "push" | "email";
}

export class CreateSharedTaskDto {
  @IsString()
  @MaxLength(240)
  title!: string;

  @IsOptional()
  @IsString()
  @MaxLength(4000)
  body?: string;

  @IsBoolean()
  allDay!: boolean;

  @IsOptional()
  @IsIn(["low", "medium", "high"])
  priority?: "low" | "medium" | "high";

  @IsDateString()
  startAt!: string;

  @ValidateIf((value: CreateSharedTaskDto) => !value.allDay)
  @IsDateString()
  endAt?: string;

  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => SharedTaskAudienceDto)
  audiences!: SharedTaskAudienceDto[];

  @IsOptional()
  @ValidateNested()
  @Type(() => SharedTaskEntityLinkDto)
  linkedEntity?: SharedTaskEntityLinkDto;

  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => SharedTaskReminderDto)
  reminders?: SharedTaskReminderDto[];
}

export class PreviewSharedTaskAudienceDto {
  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => SharedTaskAudienceDto)
  audiences!: SharedTaskAudienceDto[];
}

export class UpdateSharedTaskDto extends CreateSharedTaskDto {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  expectedVersion!: number;
}

export class CloseSharedTaskDto {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  expectedVersion!: number;

  @IsString()
  @MaxLength(80)
  @Matches(/^[a-z0-9][a-z0-9._-]*$/)
  resultCode!: string;

  @IsString()
  @MaxLength(120)
  resultLabel!: string;

  @IsOptional()
  @IsString()
  @MaxLength(4000)
  comment?: string;
}

export class SharedTaskResultsQuery {
  @IsOptional()
  @IsDateString()
  from?: string;

  @IsOptional()
  @IsDateString()
  to?: string;

  @IsOptional()
  @IsUUID()
  branchId?: string;

  @IsOptional()
  @IsUUID()
  closedBy?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  resultCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(240)
  q?: string;

  @IsOptional()
  @IsIn(["true", "false"])
  late?: "true" | "false";

  @IsOptional()
  @IsIn(["true", "false"])
  includeUndated?: "true" | "false";

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(500)
  limit?: number;
}

export class SharedTaskListQuery {
  @IsOptional()
  @IsIn(["open", "closed"])
  state?: "open" | "closed";

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(2000)
  limit?: number;

  @IsOptional()
  @IsUUID()
  taskId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  linkedEntityType?: string;

  @IsOptional()
  @IsUUID()
  linkedEntityId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(240)
  q?: string;

  @IsOptional()
  @IsIn(["low", "medium", "high"])
  priority?: "low" | "medium" | "high";

  @IsOptional()
  @IsIn(["mine", "branch", "school", "all"])
  scope?: "mine" | "branch" | "school" | "all";

  @IsOptional()
  @IsDateString()
  from?: string;

  @IsOptional()
  @IsDateString()
  to?: string;
}
