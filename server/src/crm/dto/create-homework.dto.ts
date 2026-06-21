import {
  IsISO8601,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
} from "class-validator";

export class CreateHomeworkDto {
  @IsUUID()
  studentId: string;

  @IsOptional()
  @IsUUID()
  lessonId?: string;

  @IsString()
  @MaxLength(200)
  title: string;

  @IsOptional()
  @IsString()
  @MaxLength(4000)
  description?: string;

  @IsOptional()
  @IsISO8601()
  dueAt?: string;
}
