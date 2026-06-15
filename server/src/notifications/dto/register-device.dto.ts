import { IsIn, IsString, MaxLength, MinLength } from 'class-validator';

export class RegisterDeviceDto {
  @IsIn(['ios', 'android', 'web', 'windows', 'macos'])
  platform: 'ios' | 'android' | 'web' | 'windows' | 'macos';

  @IsString()
  @MinLength(20)
  @MaxLength(4096)
  token: string;
}
