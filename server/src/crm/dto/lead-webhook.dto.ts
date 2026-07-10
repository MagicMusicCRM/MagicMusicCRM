import { IsEmail, IsNotEmpty, IsOptional, IsString, MaxLength } from "class-validator";

export class LeadWebhookDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(160)
  name!: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(40)
  phone!: string;

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

  @IsOptional()
  @IsString()
  @MaxLength(120)
  source?: string;
}
