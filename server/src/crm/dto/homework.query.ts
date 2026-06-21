import { Type } from "class-transformer";
import {
  IsIn,
  IsInt,
  IsOptional,
  IsUUID,
  Max,
  Min,
} from "class-validator";

export class HomeworkQuery {
  @IsOptional()
  @IsUUID()
  studentId?: string;

  @IsOptional()
  @IsUUID()
  lessonId?: string;

  @IsOptional()
  @IsIn(["assigned", "submitted", "reviewed"])
  status?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(200)
  limit?: number;
}
