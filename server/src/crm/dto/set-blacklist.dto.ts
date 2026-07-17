import { IsBoolean, IsOptional, IsString, MaxLength } from "class-validator";

/**
 * Постановка клиента в чёрный список / снятие.
 *
 * Причина не обязательна, но именно она отличает бан от галочки: через месяц
 * «почему он в чёрном списке» больше спросить не у кого.
 */
export class SetBlacklistDto {
  @IsBoolean()
  blacklisted!: boolean;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  reason?: string;
}
