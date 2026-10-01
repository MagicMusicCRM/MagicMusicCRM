import { Type } from "class-transformer";
import {
  IsDateString,
  IsBoolean,
  IsInt,
  IsOptional,
  IsUUID,
  ValidateNested,
} from "class-validator";
import { ClientRefDto } from "./client-ref.dto";

export class LessonConstraintPreviewDto {
  @IsOptional()
  @ValidateNested()
  @Type(() => ClientRefDto)
  clientRef?: ClientRefDto;

  @IsOptional()
  @IsUUID()
  groupId?: string;

  @IsUUID()
  teacherId!: string;

  @IsUUID()
  branchId!: string;

  @IsUUID()
  roomId!: string;

  @IsDateString()
  scheduledAt!: string;

  @IsInt()
  durationMinutes!: number;

  @IsOptional()
  @IsUUID()
  excludeLessonId?: string;

  @IsOptional()
  @IsBoolean()
  includeSuggestions?: boolean;
}
