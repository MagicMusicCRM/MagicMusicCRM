import { Type } from "class-transformer";
import {
  ArrayMaxSize,
  ArrayMinSize,
  ArrayUnique,
  IsArray,
  IsBoolean,
  IsIn,
  IsInt,
  IsString,
  Matches,
  MaxLength,
  Min,
  ValidateNested,
} from "class-validator";
import {
  CAPABILITY_DEFINITIONS,
  USER_ROLES,
  AccessRole,
  CapabilityEffect,
  CapabilityKey,
} from "../capability-registry";

const capabilityKeys = CAPABILITY_DEFINITIONS.map(
  (definition) => definition.key,
);

export class AssignAccessRoleDto {
  @IsIn(USER_ROLES)
  role: AccessRole;

  @IsInt()
  @Min(1)
  expectedVersion: number;

  @IsBoolean()
  resetOverridesConfirmed: boolean;

  @IsBoolean()
  emergencySurface: boolean;

  @IsString()
  @Matches(/^[A-Za-z0-9._:-]{1,120}$/)
  reasonCode: string;
}

export class RolePackageChangeDto {
  @IsIn(capabilityKeys)
  capabilityKey: CapabilityKey;

  @IsIn(["allow", "deny"])
  effect: CapabilityEffect;
}

export class ReplaceRolePackageDto {
  @IsInt()
  @Min(1)
  expectedVersion: number;

  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(CAPABILITY_DEFINITIONS.length)
  @ArrayUnique((change: RolePackageChangeDto) => change.capabilityKey)
  @ValidateNested({ each: true })
  @Type(() => RolePackageChangeDto)
  changes: RolePackageChangeDto[];

  @IsBoolean()
  emergencySurface: boolean;

  @IsString()
  @Matches(/^[A-Za-z0-9._:-]{1,120}$/)
  reasonCode: string;
}

export class SetUserOverrideDto {
  @IsIn(["allow", "deny"])
  effect: CapabilityEffect;

  @IsInt()
  @Min(1)
  expectedVersion: number;

  @IsBoolean()
  emergencySurface: boolean;

  @IsString()
  @MaxLength(120)
  @Matches(/^[A-Za-z0-9._:-]{1,120}$/)
  reasonCode: string;
}
