import { IsBoolean, IsIn, IsOptional, IsUUID } from "class-validator";

export class AddFamilyMemberDto {
  @IsIn(["student", "lead", "profile"])
  entityType!: "student" | "lead" | "profile";

  @IsUUID()
  entityId!: string;

  @IsIn(["parent", "child", "partner", "sibling", "guardian", "payer"])
  role!: "parent" | "child" | "partner" | "sibling" | "guardian" | "payer";

  @IsOptional()
  @IsBoolean()
  isPrimaryContact?: boolean;
}
