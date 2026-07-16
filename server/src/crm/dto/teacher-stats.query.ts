import {
  IsDateString,
  IsIn,
  IsOptional,
  IsString,
  IsUUID,
} from "class-validator";

// KVA-238: фильтры отчёта «Статистика преподавателей».
//
// unitType: individual — индивидуальные занятия, group — групповые,
// individual_trial / group_trial — пробные того и другого вида
// (✔ владелец 17.07), trial — любое пробное.
//
// `trial` оставлен намеренно: это разрез, которым уже пользуются, и сузить его
// молча значило бы поменять цифры под теми, кто на него смотрит.
export class TeacherStatsQuery {
  @IsOptional()
  @IsDateString()
  from?: string;

  @IsOptional()
  @IsDateString()
  to?: string;

  @IsOptional()
  @IsUUID()
  branchId?: string;

  @IsOptional()
  @IsUUID()
  teacherId?: string;

  @IsOptional()
  @IsIn(["individual", "group", "trial", "individual_trial", "group_trial"])
  unitType?:
    | "individual"
    | "group"
    | "trial"
    | "individual_trial"
    | "group_trial";

  /** Teacher status (active/fired/…) — «Статус преподавателя» in the report. */
  @IsOptional()
  @IsString()
  status?: string;

  /** Matched against the teacher's disciplines (m2m), case-insensitive. */
  @IsOptional()
  @IsString()
  discipline?: string;

  /** Matched against the teacher's categories (Взрослые/Дети). */
  @IsOptional()
  @IsString()
  category?: string;
}
