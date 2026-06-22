import { IsBoolean, IsIn, IsOptional, IsString, IsUUID, MaxLength } from "class-validator";

export class CreateCommentDto {
  @IsIn(["student", "teacher", "group", "lesson", "lead", "profile"])
  entityType!: string;

  @IsUUID()
  entityId!: string;

  @IsString()
  @MaxLength(4000)
  body!: string;

  // Stream the comment belongs to. admin_comment = administrator comments (staff
  // only); teacher_note = «Заметки преподавателя»; progress = client-visible.
  @IsOptional()
  @IsIn(["admin_comment", "teacher_note", "progress"])
  kind?: string;

  // Back-compat: progress=true is equivalent to kind='progress'.
  @IsOptional()
  @IsBoolean()
  progress?: boolean;
}
