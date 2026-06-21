import {
  IsISO8601,
  IsIn,
  IsOptional,
  IsString,
  MaxLength,
} from "class-validator";

export class UpdateHomeworkDto {
  @IsOptional()
  @IsString()
  @MaxLength(200)
  title?: string;

  @IsOptional()
  @IsString()
  @MaxLength(4000)
  description?: string;

  @IsOptional()
  @IsISO8601()
  dueAt?: string;

  @IsOptional()
  @IsIn(["assigned", "submitted", "reviewed"])
  status?: string;
}
