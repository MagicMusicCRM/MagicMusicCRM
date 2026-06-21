import { IsIn, IsOptional, IsUUID } from "class-validator";

export class AddHomeworkAttachmentDto {
  @IsUUID()
  fileId: string;

  @IsOptional()
  @IsIn(["assignment", "submission"])
  kind?: string;
}
