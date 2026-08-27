import { Injectable } from "@nestjs/common";
import { PoolClient } from "pg";
import { ActorContext } from "../common/security/actor-context";
import {
  ClientPipelineType,
  PreviewClientPipelineDto,
  PublishClientPipelineDto,
  PublishStudentFunnelDto,
  RollbackClientPipelineDto,
  RollbackStudentFunnelDto,
} from "./dto/student-funnel.dto";
import { StudentFunnelQueryService } from "./student-funnel/student-funnel-query.service";
import { StudentFunnelRevisionService } from "./student-funnel/student-funnel-revision.service";
import { StudentFunnelTransitionPolicy } from "./student-funnel/student-funnel-transition.policy";

export type { FunnelPatch, FunnelSnapshot } from "./student-funnel/student-funnel.types";

@Injectable()
export class StudentFunnelService {
  constructor(
    private readonly queries: StudentFunnelQueryService,
    private readonly revisions: StudentFunnelRevisionService,
    private readonly transitions: StudentFunnelTransitionPolicy,
  ) {}

  getEffective(
    actor: ActorContext,
    branchId?: string,
    clientType: ClientPipelineType = "student",
  ) {
    return this.queries.getEffective(actor, branchId, clientType);
  }

  listRevisions(
    actor: ActorContext,
    branchId?: string,
    clientType: ClientPipelineType = "student",
  ) {
    return this.queries.listRevisions(actor, branchId, clientType);
  }

  preview(actor: ActorContext, dto: PreviewClientPipelineDto) {
    return this.revisions.preview(actor, dto);
  }

  publish(
    actor: ActorContext,
    dto: PublishStudentFunnelDto | PublishClientPipelineDto,
  ) {
    return this.revisions.publish(actor, dto);
  }

  rollback(
    actor: ActorContext,
    dto: RollbackStudentFunnelDto | RollbackClientPipelineDto,
  ) {
    return this.revisions.rollback(actor, dto);
  }

  assertCreateStatus(
    client: PoolClient,
    branchId: string | null,
    status: string,
  ): Promise<void> {
    return this.transitions.assertCreateStatus(client, branchId, status);
  }

  assertTransition(
    client: PoolClient,
    branchId: string | null,
    currentStatus: string | null,
    nextStatus: string,
  ): Promise<void> {
    return this.transitions.assertTransition(
      client,
      branchId,
      currentStatus,
      nextStatus,
    );
  }

  assertLeadTransition(
    client: PoolClient,
    branchId: string | null,
    currentStatusId: string | null,
    nextStatusId: string,
    hasReason = false,
  ): Promise<void> {
    return this.transitions.assertLeadTransition(
      client,
      branchId,
      currentStatusId,
      nextStatusId,
      hasReason,
    );
  }
}
