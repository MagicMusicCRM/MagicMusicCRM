import { IsUUID } from "class-validator";

export class IssueSubscriptionDto {
  @IsUUID()
  packageId: string;
}
