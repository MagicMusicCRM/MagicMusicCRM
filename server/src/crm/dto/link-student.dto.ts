import { IsUUID } from "class-validator";

/** Ручное «Прикрепить к ученику» из карточки лида. */
export class LinkStudentDto {
  @IsUUID()
  studentId!: string;
}
