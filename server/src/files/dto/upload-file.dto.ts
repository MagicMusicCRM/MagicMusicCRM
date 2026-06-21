import { IsIn, IsOptional, IsUUID } from 'class-validator';

export type FilePurpose =
  | 'profile_avatar'
  | 'chat_attachment'
  | 'chat_voice'
  | 'legal_document'
  | 'crm_document'
  | 'homework_attachment';

export class UploadFileDto {
  @IsIn(['profile_avatar', 'chat_attachment', 'chat_voice', 'legal_document', 'crm_document', 'homework_attachment'])
  purpose: FilePurpose;

  @IsOptional()
  @IsIn(['profile', 'chat', 'student', 'teacher', 'lead', 'lesson', 'legal', 'homework'])
  ownerType?: string;

  @IsOptional()
  @IsUUID()
  ownerId?: string;
}
