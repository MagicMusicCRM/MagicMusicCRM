import { Transform } from "class-transformer";
import {
  IsIn,
  IsNotEmpty,
  IsOptional,
  IsString,
  MaxLength,
  ValidateIf,
} from "class-validator";
import { AccountDeletionStatus } from "../legal.types";

export class UpdateDeletionRequestDto {
  @IsIn(["processing", "completed", "rejected", "cancelled"])
  status: Exclude<AccountDeletionStatus, "pending">;

  @ValidateIf((dto: UpdateDeletionRequestDto) =>
    ["completed", "rejected"].includes(dto.status),
  )
  @IsString()
  @IsNotEmpty()
  @MaxLength(2000)
  @Transform(({ value }) => (typeof value === "string" ? value.trim() : value))
  resolutionNote?: string;
}
