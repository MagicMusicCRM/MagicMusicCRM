import { IsDateString, IsOptional } from "class-validator";

export class ReportQuery {
  @IsOptional()
  @IsDateString()
  from?: string;

  @IsOptional()
  @IsDateString()
  to?: string;
}
