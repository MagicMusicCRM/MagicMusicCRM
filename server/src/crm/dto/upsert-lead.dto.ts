import {
  IsBoolean,
  IsEmail,
  IsObject,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
} from "class-validator";

export class UpsertLeadDto {
  // Contract 6: NOT @IsUUID on purpose. The client historically sends status
  // NAMES (and a legacy 'new' fallback) here; the server resolves UUID-shaped
  // values as ids, other values as status names, and silently ignores what it
  // cannot resolve — a bad status must never fail the whole card save.
  @IsOptional()
  @IsString()
  @MaxLength(120)
  statusId?: string;

  // Explicitly un-assign the lead's status (move to "Без статуса"). Distinct
  // from omitting statusId, which preserves the current value.
  @IsOptional()
  @IsBoolean()
  clearStatus?: boolean;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  firstName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  lastName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  phone?: string;

  @IsOptional()
  @IsEmail()
  email?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  source?: string;

  @IsOptional()
  @IsString()
  @MaxLength(3000)
  notes?: string;

  @IsOptional()
  @IsUUID()
  assignedTo?: string;

  // Explicitly clear ownership. Omission preserves the existing assignee;
  // this keeps older partial-update clients backwards compatible.
  @IsOptional()
  @IsBoolean()
  clearAssignedTo?: boolean;

  @IsOptional()
  @IsObject()
  customDataPatch?: Record<string, unknown>;

  @IsOptional()
  @IsUUID()
  reasonId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  statusComment?: string;
}
