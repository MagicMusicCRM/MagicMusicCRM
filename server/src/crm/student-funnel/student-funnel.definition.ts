import { UnprocessableEntityException } from "@nestjs/common";
import { ClientPipelineStageDto } from "../dto/student-funnel.dto";
import {
  FunnelPatch,
  FunnelRevisionDto,
  FunnelRevisionRow,
} from "./student-funnel.types";

const normalizeStage = (
  raw: ClientPipelineStageDto,
  keys: Set<string>,
  labels: Set<string>,
): ClientPipelineStageDto => {
  const key = raw.key?.trim().toLowerCase();
  const label = raw.label?.trim();
  if (!key || !/^[a-z][a-z0-9_-]{0,63}$/.test(key) || keys.has(key)) {
    throw new UnprocessableEntityException({
      code: "STUDENT_FUNNEL_STAGE_KEY_INVALID",
      field: "stages.key",
      message: "Ключи стадий должны быть уникальными.",
    });
  }
  if (!label || label.length > 80) {
    throw new UnprocessableEntityException({
      code: "STUDENT_FUNNEL_STAGE_LABEL_INVALID",
      field: "stages.label",
      message: "Укажите название стадии.",
    });
  }
  const normalizedLabel = label.toLocaleLowerCase("ru");
  if (labels.has(normalizedLabel)) {
    throw new UnprocessableEntityException({
      code: "CLIENT_PIPELINE_STAGE_LABEL_DUPLICATE",
      field: "stages.label",
      message: "Названия стадий должны быть уникальными.",
    });
  }
  keys.add(key);
  labels.add(normalizedLabel);
  return {
    key,
    label,
    style: raw.style,
    active: raw.active === true,
    terminal: raw.terminal === true,
    requiresReason: raw.requiresReason === true,
    allowedTransitions: [
      ...new Set(
        (raw.allowedTransitions ?? []).map((value) => value.trim()),
      ),
    ].filter((value) => value !== key),
  };
};

const assertTransitionTargets = (
  stages: ClientPipelineStageDto[],
  keys: Set<string>,
) => {
  for (const stage of stages) {
    for (const target of stage.allowedTransitions) {
      if (!keys.has(target)) {
        throw new UnprocessableEntityException({
          code: "STUDENT_FUNNEL_TRANSITION_TARGET_INVALID",
          field: "stages.allowedTransitions",
          message: `Стадия «${stage.label}» ссылается на неизвестный переход.`,
        });
      }
    }
  }
};

export const normalizeStages = (rawStages: ClientPipelineStageDto[]) => {
  if (!Array.isArray(rawStages) || rawStages.length === 0) {
    throw new UnprocessableEntityException("Добавьте хотя бы одну стадию.");
  }
  const keys = new Set<string>();
  const labels = new Set<string>();
  const stages = rawStages.map((raw) => normalizeStage(raw, keys, labels));
  if (!stages.some((stage) => stage.active)) {
    throw new UnprocessableEntityException(
      "В воронке должна остаться хотя бы одна активная стадия.",
    );
  }
  assertTransitionTargets(stages, keys);
  return stages;
};

export const assertStableKeys = (
  previous: ClientPipelineStageDto[],
  next: ClientPipelineStageDto[],
) => {
  const nextKeys = new Set(next.map((stage) => stage.key));
  const missing = previous.find((stage) => !nextKeys.has(stage.key));
  if (missing) {
    throw new UnprocessableEntityException({
      code: "CLIENT_PIPELINE_STAGE_DELETE_FORBIDDEN",
      field: "stages",
      message: `Стадию «${missing.label}» можно архивировать, но нельзя удалить из истории.`,
    });
  }
};

export const diffFromSchool = (
  school: ClientPipelineStageDto[],
  desired: ClientPipelineStageDto[],
): FunnelPatch => {
  const base = new Map(school.map((stage) => [stage.key, stage]));
  const stages: Record<string, ClientPipelineStageDto> = {};
  for (const stage of desired) {
    if (JSON.stringify(base.get(stage.key)) !== JSON.stringify(stage)) {
      stages[stage.key] = stage;
    }
  }
  const schoolOrder = school.map((stage) => stage.key);
  const desiredOrder = desired.map((stage) => stage.key);
  return {
    ...(JSON.stringify(schoolOrder) === JSON.stringify(desiredOrder)
      ? {}
      : { order: desiredOrder }),
    ...(Object.keys(stages).length === 0 ? {} : { stages }),
  };
};

export const applyPatch = (
  school: ClientPipelineStageDto[],
  patch: FunnelPatch,
): ClientPipelineStageDto[] => {
  const byKey = new Map(school.map((stage) => [stage.key, { ...stage }]));
  for (const [key, stage] of Object.entries(patch.stages ?? {})) {
    byKey.set(key, stage);
  }
  const order = patch.order ?? school.map((stage) => stage.key);
  const ordered = order
    .map((key) => byKey.get(key))
    .filter((stage): stage is ClientPipelineStageDto => stage !== undefined);
  for (const [key, stage] of byKey) {
    if (!order.includes(key)) ordered.push(stage);
  }
  return normalizeStages(ordered);
};

export const toFunnelRevisionDto = (
  row: FunnelRevisionRow,
): FunnelRevisionDto => ({
  id: row.id,
  clientType: row.client_type,
  branchId: row.branch_id,
  version: Number(row.version),
  reason: row.reason,
  rollbackFromVersion:
    row.rollback_from_version === null
      ? null
      : Number(row.rollback_from_version),
  createdBy: row.created_by,
  createdAt: row.created_at,
  stages: row.effective_snapshot.stages,
  patch: row.patch,
});
