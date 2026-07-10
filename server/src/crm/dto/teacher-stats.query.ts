import { IsDateString, IsIn, IsOptional, IsUUID } from "class-validator";

// KVA-238: фильтры отчёта «Статистика преподавателей». unitType: individual —
// индивидуальные занятия, group — групповые, trial — пробные (lessons.is_trial).
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
  @IsIn(["individual", "group", "trial"])
  unitType?: "individual" | "group" | "trial";
}
