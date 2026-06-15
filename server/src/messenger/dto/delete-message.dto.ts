import { IsIn, IsOptional } from 'class-validator';

export class DeleteMessageDto {
  @IsOptional()
  @IsIn(['own', 'moderated'])
  mode?: string;
}
