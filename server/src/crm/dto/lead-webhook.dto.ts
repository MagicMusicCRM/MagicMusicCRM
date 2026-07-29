import { IsEmail, IsOptional, IsString, MaxLength } from "class-validator";
import { StrictCreateLeadDto } from "./client-config.dto";

export class LeadWebhookDto extends StrictCreateLeadDto {
  @IsOptional()
  @IsEmail()
  email?: string;

  @IsOptional()
  @IsString()
  @MaxLength(160)
  discipline?: string;

  @IsOptional()
  @IsString()
  @MaxLength(3000)
  comment?: string;
}
