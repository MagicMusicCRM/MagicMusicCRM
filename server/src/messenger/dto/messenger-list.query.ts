import { Transform, Type } from "class-transformer";
import {
  IsBoolean,
  IsDateString,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  Max,
  Min,
} from "class-validator";

export class MessengerListQuery {
  @IsOptional()
  @IsDateString()
  before?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number;

  // Strict branch inbox: chats without a resolved branch are hidden whenever
  // a branchId filter is active.
  @IsOptional()
  @IsUUID()
  branchId?: string;

  // Contract 3 (правки №2): archived=true returns ONLY the actor's archived
  // chats; default (false / omitted) hides them from the list.
  @IsOptional()
  @Transform(({ value }) => value === true || value === "true")
  @IsBoolean()
  archived?: boolean;

  // Stable chat-list pagination. Unlike `before`, this cursor also carries the
  // chat id, so chats with the same updated_at value cannot be skipped.
  @IsOptional()
  @IsString()
  @MaxLength(512)
  cursor?: string;

  // Server-side staff inbox classification. `all` keeps groups/direct chats;
  // leads/students return administration chats backed by active CRM rows.
  @IsOptional()
  @IsIn(["all", "leads", "students"])
  folder?: "all" | "leads" | "students";
}
