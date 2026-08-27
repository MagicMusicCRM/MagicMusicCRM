import type { PoolClient } from "pg";
import type { DatabaseService } from "../../db/database.service";
import type {
  ClientPipelineStageDto,
  ClientPipelineType,
} from "../dto/student-funnel.dto";

export interface FunnelSnapshot {
  stages: ClientPipelineStageDto[];
}

export interface FunnelPatch {
  order?: string[];
  stages?: Record<string, ClientPipelineStageDto>;
}

export interface FunnelRevisionRow {
  id: string;
  client_type: ClientPipelineType;
  branch_id: string | null;
  version: string | number;
  patch: FunnelPatch | FunnelSnapshot;
  effective_snapshot: FunnelSnapshot;
  reason: string;
  rollback_from_version: string | number | null;
  created_by: string | null;
  created_at: Date | string;
}

export interface FunnelRevisionDto {
  id: string;
  clientType: ClientPipelineType;
  branchId: string | null;
  version: number;
  reason: string;
  rollbackFromVersion: number | null;
  createdBy: string | null;
  createdAt: Date | string;
  stages: ClientPipelineStageDto[];
  patch: FunnelPatch | FunnelSnapshot;
}

export interface ResolvedFunnel {
  stages: ClientPipelineStageDto[];
  schoolVersion: number;
  branchVersion: number;
}

export interface FunnelRemediationRow {
  status: string;
  count: string | number;
}

export type FunnelQueryable = Pick<PoolClient, "query"> | DatabaseService;
