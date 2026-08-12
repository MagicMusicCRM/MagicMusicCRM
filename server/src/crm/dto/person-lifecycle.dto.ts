import {
  IsBoolean,
  IsInt,
  IsString,
  MaxLength,
  Min,
  MinLength,
} from "class-validator";

export class PersonLifecycleCommandDto {
  @IsInt()
  @Min(1)
  expectedVersion!: number;

  @IsString()
  @MinLength(5)
  @MaxLength(500)
  reasonText!: string;

  @IsBoolean()
  confirm!: boolean;
}
