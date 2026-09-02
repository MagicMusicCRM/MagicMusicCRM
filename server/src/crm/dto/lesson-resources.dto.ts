import { IsUUID } from "class-validator";

export class LessonResourcesDto {
  @IsUUID()
  teacherId!: string;

  @IsUUID()
  branchId!: string;

  @IsUUID()
  roomId!: string;
}
