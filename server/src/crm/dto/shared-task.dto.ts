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
}

export class SharedTaskListQuery {
  @IsOptional()
  @IsIn(["open", "closed"])
  state?: "open" | "closed";

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(200)
  limit?: number;
}
