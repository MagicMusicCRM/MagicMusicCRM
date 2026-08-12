import { Transform } from "class-transformer";
import {
  IsIn,
  IsNotEmpty,
  IsString,
  MaxLength,
  ValidateIf,
} from "class-validator";

export type PhoneReviewResolutionAction = "corrected" | "accepted_as_is";

export class ResolvePhoneReviewDto {
  @IsIn(["corrected", "accepted_as_is"])
  action: PhoneReviewResolutionAction;

  @ValidateIf((dto: ResolvePhoneReviewDto) => dto.action === "corrected")
  @Transform(({ value }) => (typeof value === "string" ? value.trim() : value))
  @IsString()
  @IsNotEmpty()
  @MaxLength(64)
  phone?: string;

  @Transform(({ value }) => (typeof value === "string" ? value.trim() : value))
  @IsString()
  @IsNotEmpty()
  @MaxLength(1000)
  resolutionNote: string;
}
