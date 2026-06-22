import { Transform, Type } from "class-transformer";
import {
  IsBoolean,
  IsIn,
  IsInt,
  IsOptional,
  IsUUID,
  Max,
  Min,
} from "class-validator";

export class CommentQuery {
  @IsOptional()
  @IsIn(["student", "teacher", "group", "lesson", "lead", "profile"])
  entityType?: string;

  @IsOptional()
  @IsUUID()
  entityId?: string;

  @IsOptional()
  @Transform(({ value }) => value === true || value === "true")
  @IsBoolean()
  progressOnly?: boolean;

  // Request a single stream (e.g. the card's admin-comments vs teacher-notes
  // section). Server still enforces what this role is allowed to see.
  @IsOptional()
  @IsIn(["admin_comment", "teacher_note", "progress"])
  kind?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number;
}
