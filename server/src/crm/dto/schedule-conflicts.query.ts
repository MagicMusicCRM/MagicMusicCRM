import { IsDateString, IsOptional, IsUUID } from "class-validator";

/**
 * Contract 1 (правки №2): GET /api/crm/schedule/conflicts
 * ?teacherId=&roomId=&startsAt=&endsAt=&excludeLessonId=
 * At least one of teacherId/roomId is expected; with neither the endpoint
 * simply reports «свободно» (no conflicts) rather than 400ing.
 */
export class ScheduleConflictsQuery {
  @IsOptional()
  @IsUUID()
  teacherId?: string;

  @IsOptional()
  @IsUUID()
  roomId?: string;

  @IsDateString()
  startsAt!: string;

  @IsDateString()
  endsAt!: string;

  @IsOptional()
  @IsUUID()
  excludeLessonId?: string;
}
