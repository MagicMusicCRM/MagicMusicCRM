import { IsBoolean } from "class-validator";

export class SetCommentVisibilityDto {
  @IsBoolean()
  visibleToTeacher!: boolean;
}
