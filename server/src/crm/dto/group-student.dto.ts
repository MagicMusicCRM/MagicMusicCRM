import { IsUUID } from "class-validator";

export class GroupStudentDto {
  @IsUUID()
  studentId!: string;
}
