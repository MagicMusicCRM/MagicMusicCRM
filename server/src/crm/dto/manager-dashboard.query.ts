import { IsDateString, IsOptional, IsUUID } from "class-validator";

export class ManagerDashboardQuery {
  @IsOptional()
  @IsDateString()
  from?: string;

  @IsOptional()
  @IsDateString()
  to?: string;

  @IsOptional()
  @IsUUID()
  branchId?: string;
}
