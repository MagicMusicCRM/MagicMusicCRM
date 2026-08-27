import { Injectable } from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { CrmPolicy } from "../crm.policy";
import { ClientPipelineType } from "../dto/student-funnel.dto";
import { toFunnelRevisionDto } from "./student-funnel.definition";
import { StudentFunnelRepository } from "./student-funnel.repository";
import { StudentFunnelResolverService } from "./student-funnel-resolver.service";

@Injectable()
export class StudentFunnelQueryService {
  constructor(
    private readonly database: DatabaseService,
    private readonly policy: CrmPolicy,
    private readonly repository: StudentFunnelRepository,
    private readonly resolver: StudentFunnelResolverService,
  ) {}

  async getEffective(
    actor: ActorContext,
    branchId?: string,
    clientType: ClientPipelineType = "student",
  ) {
    this.policy.assertCanReadOperationalData(actor);
    const effective = await this.resolver.resolveEffective(
      this.database,
      branchId,
      clientType,
    );
    const keys = effective.stages.map((stage) => stage.key);
    const unknown =
      actor.role === "teacher"
        ? []
        : await this.repository.remediationRows(clientType, branchId, keys);
    return {
      clientType,
      branchId: branchId ?? null,
      source: effective.branchVersion > 0 ? "branch_override" : "school",
      schoolVersion: effective.schoolVersion,
      branchVersion: effective.branchVersion,
      stages: effective.stages,
      remediationStatuses: unknown.map((row) => ({
        key: row.status,
        count: Number(row.count),
      })),
    };
  }

  async listRevisions(
    actor: ActorContext,
    branchId?: string,
    clientType: ClientPipelineType = "student",
  ) {
    this.policy.assertCanManageClientConfiguration(actor);
    const result = await this.repository.listRevisions(branchId, clientType);
    return { items: result.rows.map(toFunnelRevisionDto) };
  }
}
