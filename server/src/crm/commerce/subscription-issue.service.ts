import { Injectable } from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import {
  IssueSubscriptionDto,
  PurchaseSubscriptionCommandDto,
  PurchaseSubscriptionPreviewDto,
} from "../dto/issue-subscription.dto";
import { SubscriptionGrantCommandService } from "./subscription-grant-command.service";
import { CommerceMutationMetadata } from "./subscription-issue.contracts";
import { SubscriptionPurchaseCommandService } from "./subscription-purchase-command.service";
import { SubscriptionPurchasePreviewService } from "./subscription-purchase-preview.service";

export { CommerceMutationMetadata } from "./subscription-issue.contracts";

@Injectable()
export class SubscriptionIssueService {
  constructor(
    private readonly preview: SubscriptionPurchasePreviewService,
    private readonly purchaseCommand: SubscriptionPurchaseCommandService,
    private readonly grantCommand: SubscriptionGrantCommandService,
  ) {}

  previewPurchase(
    actor: ActorContext,
    recipientStudentId: string,
    dto: PurchaseSubscriptionPreviewDto,
  ) {
    return this.preview.previewPurchase(actor, recipientStudentId, dto);
  }

  purchase(
    actor: ActorContext,
    recipientStudentId: string,
    dto: PurchaseSubscriptionCommandDto,
    metadata: CommerceMutationMetadata,
  ) {
    return this.purchaseCommand.purchase(actor, recipientStudentId, dto, metadata);
  }

  issue(
    actor: ActorContext,
    studentId: string,
    dto: IssueSubscriptionDto,
    metadata: CommerceMutationMetadata,
  ) {
    return this.grantCommand.issue(actor, studentId, dto, metadata);
  }
}
