import { Type } from "class-transformer";
import {
  ArrayMaxSize,
  ArrayNotEmpty,
  IsArray,
  IsNumber,
  IsOptional,
  IsUUID,
  Min,
} from "class-validator";

/**
 * Sets one per-lesson teacher rate across many lessons at once — the
 * end-of-month «пробные группы без покупки переводят в 0» pass (spec §3).
 *
 * `teacherRate: 0` is the meaningful value here, not a missing one: 0 means
 * «входит в оклад» and drops the lesson out of payroll accrual. Omitting the
 * field clears the per-lesson override so the group/history rate applies again.
 */
export class BulkLessonRateDto {
  @IsArray()
  @ArrayNotEmpty()
  // Bounded so one request can not try to rewrite the whole schedule in a
  // single transaction and hold locks across it.
  @ArrayMaxSize(500)
  @IsUUID("4", { each: true })
  lessonIds!: string[];

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  teacherRate?: number | null;
}
