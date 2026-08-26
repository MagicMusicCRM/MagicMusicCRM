import { Injectable } from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import { SubscriptionCancelCommandDto } from "../dto/subscription-cancel.dto";
import {
  SubscriptionReplaceCommandDto,
  SubscriptionReplacePreviewDto,
} from "../dto/subscription-replace.dto";
import { SubscriptionCancellationService } from "./subscription-cancellation.service";
import { SubscriptionReplacementService } from "./subscription-replacement.service";
import { SubscriptionLifecycleMutationMetadata } from "./subscription-lifecycle.types";

export type {
  CancellationResultRef,
  ReplacementResultRef,
  SubscriptionLifecycleMutationMetadata,
} from "./subscription-lifecycle.types";

@Injectable()
export class SubscriptionLifecycleService {
  constructor(
    private readonly replacement: SubscriptionReplacementService,
    private readonly cancellation: SubscriptionCancellationService,
  ) {}

  previewReplacement(
    actor: ActorContext,
    studentId: string,
    issuedSubscriptionId: string,
    dto: SubscriptionReplacePreviewDto,
  ) {
    return this.replacement.preview(
      actor,
      studentId,
      issuedSubscriptionId,
      dto,
    );
  }

  replace(
    actor: ActorContext,
    studentId: string,
    issuedSubscriptionId: string,
    dto: SubscriptionReplaceCommandDto,
    metadata: SubscriptionLifecycleMutationMetadata,
  ) {
    return this.replacement.execute(
      actor,
      studentId,
      issuedSubscriptionId,
      dto,
      metadata,
    );
  }

  previewCancellation(
    actor: ActorContext,
    studentId: string,
    issuedSubscriptionId: string,
  ) {
    return this.cancellation.preview(actor, studentId, issuedSubscriptionId);
  }

  cancel(
    actor: ActorContext,
    studentId: string,
    issuedSubscriptionId: string,
    dto: SubscriptionCancelCommandDto,
    metadata: SubscriptionLifecycleMutationMetadata,
  ) {
    return this.cancellation.execute(
      actor,
      studentId,
      issuedSubscriptionId,
      dto,
      metadata,
    );
  }
}
