import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { assertVersionedMutationMetadata } from "../../platform/versioned-mutation-metadata";
import { CrmPolicy } from "../crm.policy";
import { trimOptional } from "../crm-util";
import { CreateTeacherPayoutDto } from "../dto/create-teacher-payout.dto";
import {
  DeleteTeacherPayrollEntryDto,
  UpdateTeacherPayoutEntryDto,
  UpdateTeacherRateEntryDto,
} from "../dto/manage-teacher-payroll-entry.dto";
import { SetTeacherRateDto } from "../dto/set-teacher-rate.dto";
import { PayrollAccrualCalculator } from "./payroll-accrual-calculator";
import { PayrollReadRepository } from "./payroll-read.repository";
import { PayrollMutationMetadata } from "./payroll.types";

@Injectable()
export class TeacherPayrollCommandService {
  constructor(
    private readonly repository: PayrollReadRepository,
    private readonly policy: CrmPolicy,
    private readonly integrity: PlatformIntegrityService,
    private readonly calculator: PayrollAccrualCalculator,
  ) {}

  async createTeacherPayout(
    actor: ActorContext,
    teacherId: string,
    dto: CreateTeacherPayoutDto,
    metadata: PayrollMutationMetadata,
  ) {
    this.policy.assertCanReadPayroll(actor);
    assertVersionedMutationMetadata(metadata);
    const reasonText = dto.reasonText.trim();
    if (!reasonText) {
      throw new BadRequestException("Укажите причину операции.");
    }
    const result = await this.integrity.executeVersionedMutation({
      actorKey: actor.userId,
      actorUserId: actor.userId,
      operation: "crm.teacher-payout.create",
      idempotencyKey: metadata.idempotencyKey,
      payload: {
        teacherId,
        kind: dto.kind,
        amount: dto.amount,
        comment: trimOptional(dto.comment),
        paidAt: dto.paidAt ?? null,
        reasonText,
      },
      aggregateType: "teacher:payroll",
      aggregateId: teacherId,
      expectedVersion: dto.expectedVersion,
      requestId: metadata.requestId,
      authorization: {
        actor,
        capabilityKey: "commerce.teacher_payroll.write",
      },
      audit: {
        action: "crm.teacher_payout_created",
        entityType: "teacher",
        entityId: teacherId,
        reason: "TEACHER_PAYOUT",
        reasonText,
        metadata: { kind: dto.kind },
      },
      outbox: {
        type: "crm.teacher_payroll.changed",
        payload: { action: dto.kind, entityId: teacherId },
      },
      mutate: async (client) => {
        const teacher = await client.query<{ id: string }>(
          `select id from app.teachers where id = $1 and deleted_at is null`,
          [teacherId],
        );
        if (!teacher.rows[0]) {
          throw new NotFoundException("Преподаватель не найден.");
        }
        const inserted = await client.query<{ id: string }>(
          `
            insert into app.teacher_payouts
              (teacher_id, amount, kind, comment, paid_at, created_by)
            values ($1, $2, $3, $4, coalesce($5::timestamptz, now()), $6)
            returning id
          `,
          [
            teacherId,
            dto.amount,
            dto.kind,
            trimOptional(dto.comment),
            dto.paidAt ?? null,
            actor.userId,
          ],
        );
        return { payoutId: inserted.rows[0].id };
      },
    });
    const payout = await this.repository.findPayout(
      String(result.resultRef.payoutId),
    );
    if (!payout) {
      throw new NotFoundException("Выплата преподавателю не найдена.");
    }
    return {
      id: payout.id,
      teacherId: payout.teacher_id,
      kind: payout.kind,
      amount: Number(payout.amount),
      comment: payout.comment,
      paidAt: payout.paid_at,
      version: result.version,
      replayed: result.replayed,
    };
  }

  async setTeacherRate(
    actor: ActorContext,
    teacherId: string,
    dto: SetTeacherRateDto,
    metadata: PayrollMutationMetadata,
  ) {
    this.policy.assertCanManagePayrollHistory(actor);
    assertVersionedMutationMetadata(metadata);
    const reasonText = dto.reasonText.trim();
    if (!reasonText) {
      throw new BadRequestException("Укажите причину изменения ставки.");
    }
    const result = await this.integrity.executeVersionedMutation({
      actorKey: actor.userId,
      actorUserId: actor.userId,
      operation: "crm.teacher-rate.create",
      idempotencyKey: metadata.idempotencyKey,
      payload: {
        teacherId,
        rate: dto.rate,
        effectiveFrom: dto.effectiveFrom ?? null,
        reasonText,
      },
      aggregateType: "teacher:payroll",
      aggregateId: teacherId,
      expectedVersion: dto.expectedVersion,
      requestId: metadata.requestId,
      authorization: {
        actor,
        capabilityKey: "commerce.teacher_payroll.write",
      },
      audit: {
        action: "crm.teacher_rate_set",
        entityType: "teacher",
        entityId: teacherId,
        reason: "TEACHER_RATE_CHANGE",
        reasonText,
      },
      outbox: {
        type: "crm.teacher_payroll.changed",
        payload: { action: "rate_changed", entityId: teacherId },
      },
      mutate: async (client) => {
        const teacher = await client.query<{ id: string }>(
          `select id from app.teachers where id = $1 and deleted_at is null`,
          [teacherId],
        );
        if (!teacher.rows[0]) {
          throw new NotFoundException("Преподаватель не найден.");
        }
        const inserted = await client.query<{ id: string }>(
          `
            insert into app.teacher_rates (
              teacher_id, rate, effective_from, created_by, created_at
            )
            values (
              $1, $2, coalesce($3::date, current_date), $4, clock_timestamp()
            )
            returning id
          `,
          [teacherId, dto.rate, dto.effectiveFrom ?? null, actor.userId],
        );
        return { entryId: inserted.rows[0].id };
      },
    });
    const rate = await this.repository.findRate(String(result.resultRef.entryId));
    if (!rate) {
      throw new NotFoundException("Запись ставки преподавателя не найдена.");
    }
    return {
      id: rate.id,
      teacherId: rate.teacher_id,
      rate: Number(rate.rate),
      effectiveFrom: this.calculator.toDateOnly(rate.effective_from),
      version: result.version,
      replayed: result.replayed,
    };
  }

  async updateTeacherRate(
    actor: ActorContext,
    teacherId: string,
    entryId: string,
    dto: UpdateTeacherRateEntryDto,
    metadata: PayrollMutationMetadata,
  ) {
    this.policy.assertCanManagePayrollHistory(actor);
    assertVersionedMutationMetadata(metadata);
    const reasonText = dto.reasonText.trim();
    if (!reasonText) {
      throw new BadRequestException("Укажите причину исправления ставки.");
    }
    const result = await this.integrity.executeVersionedMutation({
      actorKey: actor.userId,
      actorUserId: actor.userId,
      operation: "crm.teacher-rate.update",
      idempotencyKey: metadata.idempotencyKey,
      payload: {
        teacherId,
        entryId,
        rate: dto.rate,
        effectiveFrom: dto.effectiveFrom,
        reasonText,
      },
      aggregateType: "teacher:payroll",
      aggregateId: teacherId,
      expectedVersion: dto.expectedVersion,
      requestId: metadata.requestId,
      authorization: {
        actor,
        capabilityKey: "commerce.teacher_payroll.write",
      },
      audit: {
        action: "crm.teacher_rate_updated",
        entityType: "teacher",
        entityId: teacherId,
        reason: "TEACHER_RATE_CORRECTION",
        reasonText,
        beforeRef: { entryId },
      },
      outbox: {
        type: "crm.teacher_payroll.changed",
        payload: { action: "rate_updated", entityId: teacherId, entryId },
      },
      mutate: async (client) => {
        const updated = await client.query<{ id: string }>(
          `update app.teacher_rates
           set rate = $3, effective_from = $4::date,
             updated_at = clock_timestamp(), updated_by = $5
           where id = $1 and teacher_id = $2 and deleted_at is null
           returning id`,
          [entryId, teacherId, dto.rate, dto.effectiveFrom, actor.userId],
        );
        if (!updated.rows[0]) {
          throw new NotFoundException("Запись ставки преподавателя не найдена.");
        }
        return { entryId };
      },
    });
    return {
      id: entryId,
      teacherId,
      rate: dto.rate,
      effectiveFrom: dto.effectiveFrom,
      version: result.version,
      replayed: result.replayed,
    };
  }

  async deleteTeacherRate(
    actor: ActorContext,
    teacherId: string,
    entryId: string,
    dto: DeleteTeacherPayrollEntryDto,
    metadata: PayrollMutationMetadata,
  ) {
    this.policy.assertCanManagePayrollHistory(actor);
    return this.voidPayrollEntry(
      actor,
      teacherId,
      entryId,
      dto,
      metadata,
      "rate",
    );
  }

  async updateTeacherPayout(
    actor: ActorContext,
    teacherId: string,
    entryId: string,
    dto: UpdateTeacherPayoutEntryDto,
    metadata: PayrollMutationMetadata,
  ) {
    this.policy.assertCanManagePayrollHistory(actor);
    assertVersionedMutationMetadata(metadata);
    const reasonText = dto.reasonText.trim();
    if (!reasonText) {
      throw new BadRequestException("Укажите причину исправления выплаты.");
    }
    const result = await this.integrity.executeVersionedMutation({
      actorKey: actor.userId,
      actorUserId: actor.userId,
      operation: "crm.teacher-payout.update",
      idempotencyKey: metadata.idempotencyKey,
      payload: {
        teacherId,
        entryId,
        kind: dto.kind,
        amount: dto.amount,
        comment: trimOptional(dto.comment),
        paidAt: dto.paidAt,
        reasonText,
      },
      aggregateType: "teacher:payroll",
      aggregateId: teacherId,
      expectedVersion: dto.expectedVersion,
      requestId: metadata.requestId,
      authorization: {
        actor,
        capabilityKey: "commerce.teacher_payroll.write",
      },
      audit: {
        action: "crm.teacher_payout_updated",
        entityType: "teacher",
        entityId: teacherId,
        reason: "TEACHER_PAYOUT_CORRECTION",
        reasonText,
        beforeRef: { entryId },
      },
      outbox: {
        type: "crm.teacher_payroll.changed",
        payload: { action: "payout_updated", entityId: teacherId, entryId },
      },
      mutate: async (client) => {
        const updated = await client.query<{ id: string }>(
          `update app.teacher_payouts
           set kind = $3, amount = $4, comment = $5,
             paid_at = $6::timestamptz, updated_at = clock_timestamp(),
             updated_by = $7
           where id = $1 and teacher_id = $2 and deleted_at is null
           returning id`,
          [
            entryId,
            teacherId,
            dto.kind,
            dto.amount,
            trimOptional(dto.comment),
            dto.paidAt,
            actor.userId,
          ],
        );
        if (!updated.rows[0]) {
          throw new NotFoundException("Выплата преподавателю не найдена.");
        }
        return { entryId };
      },
    });
    return {
      id: entryId,
      teacherId,
      kind: dto.kind,
      amount: dto.amount,
      comment: trimOptional(dto.comment),
      paidAt: dto.paidAt,
      version: result.version,
      replayed: result.replayed,
    };
  }

  async deleteTeacherPayout(
    actor: ActorContext,
    teacherId: string,
    entryId: string,
    dto: DeleteTeacherPayrollEntryDto,
    metadata: PayrollMutationMetadata,
  ) {
    this.policy.assertCanManagePayrollHistory(actor);
    return this.voidPayrollEntry(
      actor,
      teacherId,
      entryId,
      dto,
      metadata,
      "payout",
    );
  }

  private async voidPayrollEntry(
    actor: ActorContext,
    teacherId: string,
    entryId: string,
    dto: DeleteTeacherPayrollEntryDto,
    metadata: PayrollMutationMetadata,
    kind: "rate" | "payout",
  ) {
    assertVersionedMutationMetadata(metadata);
    const reasonText = dto.reasonText.trim();
    if (!reasonText) {
      throw new BadRequestException("Укажите причину удаления записи.");
    }
    const table = kind === "rate" ? "teacher_rates" : "teacher_payouts";
    const result = await this.integrity.executeVersionedMutation({
      actorKey: actor.userId,
      actorUserId: actor.userId,
      operation: `crm.teacher-${kind}.delete`,
      idempotencyKey: metadata.idempotencyKey,
      payload: { teacherId, entryId, reasonText },
      aggregateType: "teacher:payroll",
      aggregateId: teacherId,
      expectedVersion: dto.expectedVersion,
      requestId: metadata.requestId,
      authorization: {
        actor,
        capabilityKey: "commerce.teacher_payroll.write",
      },
      audit: {
        action: `crm.teacher_${kind}_deleted`,
        entityType: "teacher",
        entityId: teacherId,
        reason:
          kind === "rate" ? "TEACHER_RATE_DELETE" : "TEACHER_PAYOUT_DELETE",
        reasonText,
        beforeRef: { entryId },
      },
      outbox: {
        type: "crm.teacher_payroll.changed",
        payload: { action: `${kind}_deleted`, entityId: teacherId, entryId },
      },
      mutate: async (client) => {
        const deleted = await client.query<{ id: string }>(
          `update app.${table}
           set deleted_at = clock_timestamp(), deleted_by = $3,
             updated_at = clock_timestamp(), updated_by = $3
           where id = $1 and teacher_id = $2 and deleted_at is null
           returning id`,
          [entryId, teacherId, actor.userId],
        );
        if (!deleted.rows[0]) {
          throw new NotFoundException(
            kind === "rate"
              ? "Запись ставки преподавателя не найдена."
              : "Выплата преподавателю не найдена.",
          );
        }
        return { entryId };
      },
    });
    return {
      id: entryId,
      teacherId,
      deleted: true,
      version: result.version,
      replayed: result.replayed,
    };
  }
}
