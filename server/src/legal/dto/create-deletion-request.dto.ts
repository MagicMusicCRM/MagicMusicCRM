import { Equals, IsBoolean, IsOptional, IsString, MaxLength } from 'class-validator';

export class CreateDeletionRequestDto {
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  reason?: string;

  @IsBoolean()
  @Equals(true)
  acknowledgement: boolean;
}
