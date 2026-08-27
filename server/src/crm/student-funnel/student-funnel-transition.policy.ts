import { Injectable, UnprocessableEntityException } from "@nestjs/common";
import { PoolClient } from "pg";
import { StudentFunnelRepository } from "./student-funnel.repository";
import { StudentFunnelResolverService } from "./student-funnel-resolver.service";

@Injectable()
export class StudentFunnelTransitionPolicy {
  constructor(
    private readonly repository: StudentFunnelRepository,
    private readonly resolver: StudentFunnelResolverService,
  ) {}

  async assertCreateStatus(
    client: PoolClient,
    branchId: string | null,
    status: string,
  ): Promise<void> {
    const effective = await this.resolver.resolveEffective(
      client,
      branchId ?? undefined,
      "student",
    );
    const target = effective.stages.find((stage) => stage.key === status);
    if (!target?.active) {
      throw new UnprocessableEntityException({
        code: "STUDENT_FUNNEL_STAGE_UNAVAILABLE",
        field: "status",
        message: "Выбранная стадия ученика недоступна в этом филиале.",
      });
    }
  }

  async assertTransition(
    client: PoolClient,
    branchId: string | null,
    currentStatus: string | null,
    nextStatus: string,
  ): Promise<void> {
    const effective = await this.resolver.resolveEffective(
      client,
      branchId ?? undefined,
      "student",
    );
    const next = effective.stages.find((stage) => stage.key === nextStatus);
    if (!next?.active) {
      throw new UnprocessableEntityException({
        code: "STUDENT_FUNNEL_STAGE_UNAVAILABLE",
        field: "status",
        message: "Целевая стадия архивирована или не настроена.",
      });
    }
    if (currentStatus === nextStatus) return;
    const current = effective.stages.find(
      (stage) => stage.key === currentStatus,
    );
    // Unknown legacy values are an explicit remediation bucket. Moving out of
    // it into an active configured stage is the only permitted transition.
    if (!current) return;
    if (!current.allowedTransitions.includes(nextStatus)) {
      throw new UnprocessableEntityException({
        code: "STUDENT_FUNNEL_TRANSITION_DENIED",
        field: "status",
        message: `Переход «${current.label}» → «${next.label}» запрещён настройками воронки.`,
      });
    }
  }

  async assertLeadTransition(
    client: PoolClient,
    branchId: string | null,
    currentStatusId: string | null,
    nextStatusId: string,
    hasReason = false,
  ): Promise<void> {
    const statusIds = currentStatusId
      ? [currentStatusId, nextStatusId]
      : [nextStatusId];
    const keyById = await this.repository.leadStatusKeys(client, statusIds);
    const nextKey = keyById.get(nextStatusId);
    if (!nextKey) {
      throw new UnprocessableEntityException({
        code: "LEAD_PIPELINE_STAGE_UNAVAILABLE",
        field: "statusId",
        message: "Выбранная стадия лида не настроена.",
      });
    }
    const effective = await this.resolver.resolveEffective(
      client,
      branchId ?? undefined,
      "lead",
    );
    const next = effective.stages.find((stage) => stage.key === nextKey);
    if (!next?.active) {
      throw new UnprocessableEntityException({
        code: "LEAD_PIPELINE_STAGE_UNAVAILABLE",
        field: "statusId",
        message: "Целевая стадия лида архивирована или недоступна.",
      });
    }
    if (currentStatusId === null || currentStatusId === nextStatusId) return;
    const currentKey = keyById.get(currentStatusId);
    const current = effective.stages.find((stage) => stage.key === currentKey);
    if (current && !current.allowedTransitions.includes(nextKey)) {
      throw new UnprocessableEntityException({
        code: "LEAD_PIPELINE_TRANSITION_DENIED",
        field: "statusId",
        message: `Переход «${current.label}» → «${next.label}» запрещён настройками воронки.`,
      });
    }
    if (next.requiresReason && !hasReason) {
      throw new UnprocessableEntityException({
        code: "LEAD_PIPELINE_REASON_REQUIRED",
        field: "reasonId",
        message: `Для перехода на стадию «${next.label}» укажите причину.`,
      });
    }
  }
}
