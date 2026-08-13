import { IsUUID } from "class-validator";

export class LinkUserToClientDto {
  @IsUUID()
  userId!: string;
}
