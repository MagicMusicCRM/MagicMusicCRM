import { Type } from "class-transformer";
import {
  IsDateString,
  IsInt,
  IsOptional,
  IsUUID,
  ValidateNested,
} from "class-validator";
import { ClientRefDto } from "./client-ref.dto";

export class LessonConstraintPreviewDto {
  @ValidateNested()
  @Type(() => ClientRefDto)
  clientRef!: ClientRefDto;

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
}
