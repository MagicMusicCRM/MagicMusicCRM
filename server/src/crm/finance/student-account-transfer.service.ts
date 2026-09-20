import {
  BadRequestException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { createHash } from "node:crypto";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import {
  assertVersionedMutationMetadata,
  VersionedMutationMetadata,
} from "../../platform/versioned-mutation-metadata";
import {
  branchIdExpr,
  currentActorRoleSql,
  managerBranchScopeSql,
} from "../branch-scope";
import { CrmPolicy } from "../crm.policy";
import { CreateTransferDto } from "../dto/create-transfer.dto";

@Injectable()
export class StudentAccountTransferService {
  constructor(
    private readonly database: DatabaseService,
    private readonly integrity: PlatformIntegrityService,
    private readonly policy: CrmPolicy,
  ) {}

  async createAccountTransfer(
    actor: ActorContext,
    fromStudentId: string,
    dto: CreateTransferDto,
    metadata: VersionedMutationMetadata = { idempotencyKey: "", requestId: "" },
  ) {
    this.policy.assertManagerOnly(actor);
    if (fromStudentId === dto.toStudentId)
      throw new BadRequestException("Нельзя перевести деньги самому себе.");
    assertVersionedMutationMetadata(metadata);
    const minor = Math.round(dto.amount * 100);
    if (
      !Number.isSafeInteger(minor) ||
      minor <= 0 ||
      minor > 999999999999 ||
      Math.abs(dto.amount * 100 - minor) > 0.0001
    ) {
      throw new BadRequestException(
        "Сумма должна быть положительной, с точностью до копейки.",
      );
    }
    const currency = dto.currencyCode ?? "RUB";
    if (!/^[A-Z]{3}$/.test(currency))
      throw new BadRequestException("Некорректная валюта перевода.");
    const stableId = (leg: string) => {
      const h = createHash("sha256")
        .update(
          [actor.userId, "account-transfer", metadata.idempotencyKey, leg].join(
            ":",
          ),
        )
        .digest("hex");
      return [
        h.slice(0, 8),
        h.slice(8, 12),
        "4" + h.slice(13, 16),
        "a" + h.slice(17, 20),
        h.slice(20, 32),
      ].join("-");
    };
    const outId = stableId("out"),
      inId = stableId("in");
    const result = await this.integrity.executeVersionedMutation({
      actorKey: actor.userId,
      actorUserId: actor.userId,
      authorization: { actor, capabilityKey: "commerce.client_finance.write" },
      operation: "crm.account-transfer.create",
      idempotencyKey: metadata.idempotencyKey,
      requestId: metadata.requestId,
      aggregateType: "commerce:payment-adjustment",
      aggregateId: outId,
      expectedVersion: 0,
      payload: {
        fromStudentId,
        toStudentId: dto.toStudentId,
        amountMinor: minor,
        currencyCode: currency,
        description: dto.description ?? null,
        occurredAt: dto.occurredAt ?? null,
      },
      audit: {
        action: "crm.account_transfer_created",
        entityType: "account_adjustment",
        entityId: outId,
        reason: "account_transfer",
        reasonText: dto.description,
        afterRef: { outId, inId },
      },
      outbox: {
        type: "commerce.payment-transfer.changed",
        payload: {
          entityId: outId,
          action: "created",
          invalidates: ["student-finance"],
        },
      },
      mutate: async (client) => {
        // The same student rows serialize purchases/refunds and opposing transfers.
        // Role is resolved in SQL; a stale JWT must never widen branch scope.
        const locked = await client.query<{ id: string; branch_id: string }>(
          `select student.id, ${branchIdExpr("student")} as branch_id
          from app.students student where student.id=any($1::uuid[]) and student.deleted_at is null
          and ${currentActorRoleSql("$2")} = any(array['admin','manager','director','system_admin'])
          and ${managerBranchScopeSql({ roleExpression: currentActorRoleSql("$2"), userIdExpression: "$2", branchExpression: branchIdExpr("student") })}
          order by student.id for update of student`,
          [[fromStudentId, dto.toStudentId].sort(), actor.userId],
        );
        if (locked.rows.length !== 2)
          throw new NotFoundException("Ученик не найден или недоступен.");
        const balance = await client.query<{ balance_minor: string }>(
          `select balance_minor::text from app.commerce_student_account_projection
          where student_id=$1 and currency_code=$2`,
          [fromStudentId, currency],
        );
        if (BigInt(balance.rows[0]?.balance_minor ?? "0") < BigInt(minor))
          throw new UnprocessableEntityException({
            code: "TRANSFER_INSUFFICIENT_BALANCE",
            field: "amount",
            message: "Сумма перевода превышает доступный остаток.",
          });
        for (const [id, peerId, studentId, counterparty, kind, signed] of [
          [outId, inId, fromStudentId, dto.toStudentId, "transfer_out", -minor],
          [inId, outId, dto.toStudentId, fromStudentId, "transfer_in", minor],
        ] as const) {
          await client.query(
            `insert into app.account_adjustments
            (id,transfer_peer_id,student_id,branch_id,kind,amount,amount_minor,currency_code,description,counterparty_student_id,occurred_at,created_by)
            values($1,$2,$3,$4,$5,$6::numeric/100,$6,$7,$8,$9,coalesce($10::timestamptz,now()),$11)`,
            [
              id,
              peerId,
              studentId,
              locked.rows.find((s) => s.id === studentId)!.branch_id,
              kind,
              signed,
              currency,
              dto.description ?? null,
              counterparty,
              dto.occurredAt ?? null,
              actor.userId,
            ],
          );
        }
        return { fromAdjustmentId: outId, toAdjustmentId: inId };
      },
    });
    return {
      ...result.resultRef,
      amount: minor / 100,
      currencyCode: currency,
      version: result.version,
      replayed: result.replayed,
    };
  }
}
