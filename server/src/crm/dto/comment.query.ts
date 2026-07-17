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

  /**
   * Подмешать в ленту комментарии к ЗАНЯТИЯМ этого ученика.
   *
   * ✔ Требование заказчика: «в приложении в разделе комментариев админов
   * показывались как обычные комментарии к клиенту, так и комментарии к
   * определённым занятиям этого клиента — в нашей CRM тоже нужно».
   *
   * Комментарий живёт на занятии (`entity_type='lesson'`) — так решил заказчик,
   * чтобы у группового занятия он был один на всех. Но человеку он нужен в
   * ленте клиента, вперемешку с обычными. Отсюда этот флаг: одна лента, один
   * запрос.
   *
   * Имеет смысл только при `entityType='student'`: у лида занятий нет.
   */
  @IsOptional()
  @Transform(({ value }) => value === true || value === "true")
  @IsBoolean()
  includeLessonComments?: boolean;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number;
}
