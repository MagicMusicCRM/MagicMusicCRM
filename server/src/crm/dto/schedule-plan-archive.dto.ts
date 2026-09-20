import { Equals, IsInt, IsString, Matches, MaxLength, Min, MinLength } from "class-validator";

export class SchedulePlanArchiveCommandDto {
  @IsInt() @Min(1) expectedVersion!: number;
  @IsString() @Matches(/^[a-f0-9]{64}$/) impactFingerprint!: string;
  @IsString() @MinLength(1) @MaxLength(500) reasonText!: string;
  @Equals(true) confirm!: true;
}
