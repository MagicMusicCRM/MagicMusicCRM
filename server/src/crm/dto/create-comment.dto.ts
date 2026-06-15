import { IsBoolean, IsIn, IsOptional, IsString, IsUUID, MaxLength } from "class-validator";

export class CreateCommentDto {
  @IsIn(["student", "teacher", "group", "lesson", "lead", "profile"])
  entityType!: string;

  @IsUUID()
  entityId!: string;

  @IsString()
  @MaxLength(4000)
  body!: string;

  @IsOptional()
  @IsBoolean()
  progress?: boolean;
}
