import {
  IsDateString,
  IsIn,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
} from "class-validator";
import { ClientStatusType } from "./client-status-filter.query";

export type ReportExportKey = "client_status" | "school_finance";
export type ReportExportFormat = "xlsx" | "csv";

export class ReportExportRequestDto {
  @IsIn(["client_status", "school_finance"])
  reportKey!: ReportExportKey;

  @IsIn(["xlsx", "csv"])
  format!: ReportExportFormat;

  @IsOptional()
  @IsIn(["lead", "student"])
  clientType?: ClientStatusType;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  status?: string;

  @IsOptional()
  @IsUUID()
  branchId?: string;

  @IsOptional()
  @IsDateString()
  from?: string;

  @IsOptional()
  @IsDateString()
  to?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  q?: string;
}
