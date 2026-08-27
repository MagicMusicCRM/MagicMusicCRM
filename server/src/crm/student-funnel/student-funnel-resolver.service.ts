import { Injectable, NotFoundException } from "@nestjs/common";
import { ClientPipelineStageDto, ClientPipelineType } from "../dto/student-funnel.dto";
import { applyPatch, normalizeStages } from "./student-funnel.definition";
import { StudentFunnelRepository } from "./student-funnel.repository";
import {
  FunnelPatch,
  FunnelQueryable,
  FunnelSnapshot,
  ResolvedFunnel,
} from "./student-funnel.types";

@Injectable()
export class StudentFunnelResolverService {
  constructor(private readonly repository: StudentFunnelRepository) {}

  async resolveEffective(
    queryable: FunnelQueryable,
    branchId: string | undefined,
    clientType: ClientPipelineType,
  ): Promise<ResolvedFunnel> {
    if (branchId) await this.repository.assertBranch(queryable, branchId);
    const school = await this.repository.latestRevision(
      queryable,
      null,
      clientType,
      false,
    );
    if (!school) {
      if (branchId) {
        throw new NotFoundException("Сначала настройте школьную воронку.");
      }
      return {
        stages: [] as ClientPipelineStageDto[],
        schoolVersion: 0,
        branchVersion: 0,
      };
    }
    const schoolStages = normalizeStages(school.effective_snapshot.stages);
    if (!branchId) {
      return {
        stages: schoolStages,
        schoolVersion: Number(school.version),
        branchVersion: 0,
      };
    }
    const branch = await this.repository.latestRevision(
      queryable,
      branchId,
      clientType,
      false,
    );
    return {
      stages: branch
        ? applyPatch(schoolStages, branch.patch as FunnelPatch)
        : schoolStages,
      schoolVersion: Number(school.version),
      branchVersion: Number(branch?.version ?? 0),
    };
  }

  async resolveSchool(
    queryable: FunnelQueryable,
    clientType: ClientPipelineType,
  ): Promise<FunnelSnapshot> {
    const revision = await this.repository.latestRevision(
      queryable,
      null,
      clientType,
      false,
    );
    if (!revision) {
      throw new NotFoundException("Школьная воронка не настроена.");
    }
    return { stages: normalizeStages(revision.effective_snapshot.stages) };
  }
}
