import {
  IsBoolean,
  IsInt,
  IsOptional,
  IsString,
  Matches,
  Min,
} from "class-validator";

export class SetCommentVisibilityDto {
  @IsOptional()
  @IsBoolean()
  visibleToTeacher?: boolean;

  @IsOptional()
  @IsBoolean()
  sharedWithTeacher?: boolean;

  @IsOptional()
  @IsInt()
  @Min(1)
  expectedVersion?: number;

  @IsOptional()
  @IsString()
  @Matches(/^[A-Za-z0-9._:-]{1,120}$/)
  reasonCode?: string;
}
