import { Type } from "class-transformer";
import {
  ArrayMaxSize,
  IsArray,
  IsIn,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  ValidateNested,
} from "class-validator";

class AttendanceItemDto {
  @IsUUID()
  studentId!: string;

  @IsIn(["present", "absent"])
  status!: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  passReason?: string;
}

export class UpsertAttendanceDto {
  @IsArray()
  @ArrayMaxSize(100)
  @ValidateNested({ each: true })
  @Type(() => AttendanceItemDto)
  items!: AttendanceItemDto[];
}
