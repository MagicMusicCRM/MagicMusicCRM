import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { createHash } from "crypto";
import { ActorContext } from "../../common/security/actor-context";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { PlatformAuditInput } from "../../platform/platform-integrity.types";
import { CrmPolicy } from "../crm.policy";
import {
  IssueSubscriptionDiscountDto,
  IssueSubscriptionDto,
  IssueSubscriptionInstallmentDto,
} from "../dto/issue-subscription.dto";
import {
  IssuedCommercialSnapshot,
  IssuedDiscountSnapshot,
} from "./commerce-schema.types";
import {
  IssueDiscountColumns,
  IssuePackageRow,
  PlannedInstallment,
  SubscriptionIssueRepository,
} from "./subscription-issue.repository";
import { SubscriptionReservationService } from "./subscription-reservation.service";

export interface CommerceMutationMetadata {
  idempotencyKey: string;
  requestId: string;
}

interface IssueMutationResult extends Record<string, unknown> {
  entityId: string;
  version: number;
}

interface NormalizedDiscount {
  snapshot: IssuedDiscountSnapshot;
  columns: IssueDiscountColumns;
  finalPriceMinor: string;
}

@Injectable()
export class SubscriptionIssueService {
  constructor(
    private readonly repository: SubscriptionIssueRepository,
    private readonly policy: CrmPolicy,
    private readonly integrity: PlatformIntegrityService,
    private readonly reservations: SubscriptionReservationService,
  ) {}

  async issue(
    actor: ActorContext,
    studentId: string,
    dto: IssueSubscriptionDto,
    metadata: CommerceMutationMetadata,
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.assertMetadata(metadata);
    this.assertPaymentMethod(dto.paymentMethod);
    const subscriptionId = this.deterministicId(
      actor.userId,
      "crm.subscription.issue",
      metadata.idempotencyKey,
    );
    const audit: PlatformAuditInput = {
      action: "crm.subscription_issued",
      entityType: "subscription",
      entityId: subscriptionId,
      metadata: {
        studentId,
        packageId: dto.packageId,
        lifecycle: "issued",
      },
    };
    const result =
      await this.integrity.executeVersionedMutation<IssueMutationResult>({
        actorKey: actor.userId,
        actorUserId: actor.userId,
        operation: "crm.subscription.issue",
        idempotencyKey: metadata.idempotencyKey,
        requestId: metadata.requestId,
        aggregateType: "commerce:issued-subscription",
        aggregateId: subscriptionId,
        expectedVersion: 0,
        payload: { studentId, ...dto },
        audit,
        outbox: {
          type: "commerce.subscription.changed",
          payload: {
            entityId: subscriptionId,
            state: "active",
            invalidates: ["student-finance", "subscription"],
          },
        },
        mutate: async (client, nextVersion) => {
          if (!(await this.repository.lockStudent(client, studentId))) {
            throw new NotFoundException("Ученик не найден.");
          }
          const packageRow =
            await this.repository.findActivePackageForShare(
              client,
              dto.packageId,
            );
          if (!packageRow) {
            throw new NotFoundException(
              "Абонемент не найден или находится в архиве.",
            );
          }
          const discount = this.normalizeDiscount(
            dto.discount,
            packageRow.base_price_minor,
          );
          const installments = this.normalizeInstallments(
            dto.installments,
            discount.finalPriceMinor,
          );
          const snapshot = this.createSnapshot(
            packageRow,
            discount,
            installments,
            dto.paymentMethod ?? null,
          );
          const subscription =
            await this.repository.createIssuedSubscription(client, {
              id: subscriptionId,
              studentId,
              package: packageRow,
              snapshot,
              discount: discount.columns,
              finalPriceMinor: discount.finalPriceMinor,
              version: nextVersion,
            });
          await this.repository.createInstallments(client, {
            issuedSubscriptionId: subscription.id,
            currencyCode: packageRow.currency_code,
            installments,
          });
          await this.repository.createObligations(client, {
            studentId,
            issuedSubscriptionId: subscription.id,
            currencyCode: packageRow.currency_code,
            finalPriceMinor: discount.finalPriceMinor,
            installments,
          });
          await this.repository.createIssueLifecycle(client, {
            issuedSubscriptionId: subscription.id,
            actorUserId: actor.userId,
            version: nextVersion,
          });
          audit.afterRef = {
            subscriptionId: subscription.id,
            subscriptionVersion: nextVersion,
            packageId: packageRow.id,
            packageVersion: Number(packageRow.version),
          };
          return {
            entityId: subscription.id,
            version: nextVersion,
          };
        },
      });
    const response = await this.loadStableIssueResult(
      result.resultRef.entityId,
      result.resultRef.version,
    );
    if (!result.replayed) {
      await this.reservations.publishPostCommit({
        studentId,
        subscriptionId: result.resultRef.entityId,
      });
    }
    return response;
  }

  private normalizeDiscount(
    dto: IssueSubscriptionDiscountDto | undefined,
    rawBasePriceMinor: string,
  ): NormalizedDiscount {
    const basePriceMinor = BigInt(rawBasePriceMinor);
    if (!dto) {
      return {
        snapshot: { type: "none" },
        columns: {
          type: "none",
          percentBasisPoints: null,
          fixedMinor: null,
          reason: null,
        },
        finalPriceMinor: rawBasePriceMinor,
      };
    }
    const reason = dto.reason?.trim();
    if (!reason) {
      throw new UnprocessableEntityException({
        code: "DISCOUNT_REASON_REQUIRED",
        field: "discount.reason",
        message: "Для скидки обязательно укажите причину.",
      });
    }
    if (dto.type === "percent") {
      if (dto.percent === undefined || dto.fixedMinor !== undefined) {
        this.throwDiscountShape();
      }
      const percent = dto.percent!;
      const basisPoints = Math.round(percent * 100);
      if (
        !Number.isFinite(percent) ||
        percent <= 0 ||
        percent > 100 ||
        basisPoints < 1 ||
        basisPoints > 10_000 ||
        Math.abs(percent * 100 - basisPoints) > 1e-8
      ) {
        throw new UnprocessableEntityException({
          code: "DISCOUNT_PERCENT_INVALID",
          field: "discount.percent",
          message: "Процент скидки должен быть от 0,01 до 100.",
        });
      }
      const discountMinor =
        (basePriceMinor * BigInt(basisPoints) + 5_000n) / 10_000n;
      const finalPriceMinor = basePriceMinor - discountMinor;
      return {
        snapshot: {
          type: "percent",
          percentBasisPoints: basisPoints,
          reason,
        },
        columns: {
          type: "percent",
          percentBasisPoints: basisPoints,
          fixedMinor: null,
          reason,
        },
        finalPriceMinor: finalPriceMinor.toString(),
      };
    }
    if (
      dto.type !== "fixed" ||
      dto.fixedMinor === undefined ||
      dto.percent !== undefined ||
      !/^[1-9]\d*$/.test(dto.fixedMinor)
    ) {
      this.throwDiscountShape();
    }
    const fixedMinor = BigInt(dto.fixedMinor!);
    if (fixedMinor > basePriceMinor) {
      throw new UnprocessableEntityException({
        code: "DISCOUNT_EXCEEDS_BASE_PRICE",
        field: "discount.fixedMinor",
        message: "Фиксированная скидка не может превышать базовую стоимость.",
      });
    }
    return {
      snapshot: {
        type: "fixed",
        fixedMinor: fixedMinor.toString(),
        reason,
      },
      columns: {
        type: "fixed",
        percentBasisPoints: null,
        fixedMinor: fixedMinor.toString(),
        reason,
      },
      finalPriceMinor: (basePriceMinor - fixedMinor).toString(),
    };
  }

  private normalizeInstallments(
    dto: IssueSubscriptionInstallmentDto[] | undefined,
    finalPriceMinor: string,
  ): PlannedInstallment[] {
    if (dto === undefined) return [];
    if (dto.length < 2) {
      throw new UnprocessableEntityException({
        code: "INSTALLMENTS_MINIMUM_TWO",
        field: "installments",
        message: "Рассрочка должна содержать минимум две части.",
      });
    }
    let total = 0n;
    const installments = dto.map((item, index) => {
      if (!/^[1-9]\d*$/.test(item.amountMinor)) {
        throw new UnprocessableEntityException({
          code: "INSTALLMENT_AMOUNT_INVALID",
          field: `installments.${index}.amountMinor`,
          message: "Сумма части рассрочки должна быть положительной.",
        });
      }
      const dueAt = new Date(item.dueAt);
      if (Number.isNaN(dueAt.getTime())) {
        throw new UnprocessableEntityException({
          code: "INSTALLMENT_DATE_INVALID",
          field: `installments.${index}.dueAt`,
          message: "Укажите корректную дату части рассрочки.",
        });
      }
      const amountMinor = BigInt(item.amountMinor);
      total += amountMinor;
      return {
        installmentNumber: index + 1,
        dueAt,
        amountMinor: amountMinor.toString(),
      };
    });
    if (total !== BigInt(finalPriceMinor)) {
      throw new UnprocessableEntityException({
        code: "INSTALLMENT_SUM_MISMATCH",
        field: "installments",
        message:
          "Сумма частей рассрочки должна точно совпадать с итоговой стоимостью.",
        expectedMinor: finalPriceMinor,
        actualMinor: total.toString(),
      });
    }
    return installments;
  }

  private createSnapshot(
    packageRow: IssuePackageRow,
    discount: NormalizedDiscount,
    installments: PlannedInstallment[],
    paymentMethod: "cash" | "cashless" | null,
  ): IssuedCommercialSnapshot {
    return {
      snapshotVersion: 1,
      packageVersion: Number(packageRow.version),
      displayName: packageRow.name,
      unitCount: String(packageRow.lessons_total),
      validityDays: packageRow.validity_days,
      basePriceMinor: packageRow.base_price_minor,
      currencyCode: packageRow.currency_code,
      discount: discount.snapshot,
      finalPriceMinor: discount.finalPriceMinor,
      installments: installments.map((item) => ({
        installmentNumber: item.installmentNumber,
        dueAt: item.dueAt.toISOString(),
        amountMinor: item.amountMinor,
      })),
      paymentMethod,
      commercialRules: {},
    };
  }

  private async loadStableIssueResult(
    subscriptionId: string,
    subscriptionVersion: number,
  ) {
    const subscription =
      await this.repository.findIssuedSubscription(subscriptionId);
    if (!subscription) {
      throw new ConflictException({
        code: "ISSUE_RESULT_MISSING",
        message: "Зафиксированный результат выдачи не найден.",
        subscriptionId,
      });
    }
    const [installments, obligations] = await Promise.all([
      this.repository.listInstallments(subscriptionId),
      this.repository.listObligations(subscriptionId),
    ]);
    const finalPriceMinor =
      subscription.commercial_snapshot.finalPriceMinor;
    const netMinor =
      finalPriceMinor === "0" ? "0" : `-${finalPriceMinor}`;
    return {
      subscription: {
        id: subscription.id,
        studentId: subscription.student_id,
        packageId: subscription.package_id,
        unitCount: Number(subscription.lessons_total),
        unitsUsed: 0,
        startsAt: subscription.starts_at,
        expiresAt: subscription.expires_at,
        status: "active",
        version: subscriptionVersion,
        commercialSnapshot: subscription.commercial_snapshot,
        createdAt: subscription.created_at,
      },
      installments: installments.map((item) => ({
        id: item.id,
        installmentNumber: item.installment_number,
        dueAt: item.due_at,
        amountMinor: item.amount_minor,
        currencyCode: item.currency_code,
        status: "pending" as const,
        version: 1,
      })),
      obligations: obligations.map((item) => ({
        id: item.id,
        factType: item.fact_type,
        direction: item.direction,
        amountMinor: item.amount_minor,
        currencyCode: item.currency_code,
        sourceType: item.source_type,
        sourceRef: item.source_ref,
        occurredAt: item.occurred_at,
      })),
      balanceAtIssue: {
        currencyCode: subscription.commercial_snapshot.currencyCode,
        actualPaymentsMinor: "0",
        obligationsMinor: finalPriceMinor,
        netMinor,
      },
    };
  }

  private throwDiscountShape(): never {
    throw new UnprocessableEntityException({
      code: "DISCOUNT_SHAPE_INVALID",
      field: "discount",
      message:
        "Укажите либо процентную, либо фиксированную скидку, но не обе.",
    });
  }

  private assertPaymentMethod(
    value: string | undefined,
  ): asserts value is "cash" | "cashless" | undefined {
    if (
      value !== undefined &&
      value !== "cash" &&
      value !== "cashless"
    ) {
      throw new UnprocessableEntityException({
        code: "PAYMENT_METHOD_INVALID",
        field: "paymentMethod",
        message: "Способ оплаты должен быть cash или cashless.",
      });
    }
  }

  private assertMetadata(metadata: CommerceMutationMetadata): void {
    if (!/^[A-Za-z0-9._:-]{8,160}$/.test(metadata.idempotencyKey)) {
      throw new BadRequestException({
        code: "INVALID_IDEMPOTENCY_KEY",
        message: "Idempotency-Key должен содержать 8–160 безопасных символов.",
      });
    }
    if (
      !metadata.requestId ||
      metadata.requestId.length > 128 ||
      /[\r\n]/.test(metadata.requestId)
    ) {
      throw new BadRequestException({
        code: "INVALID_REQUEST_ID",
        message: "X-Request-Id обязателен и не должен превышать 128 символов.",
      });
    }
  }

  private deterministicId(
    actorUserId: string,
    operation: string,
    idempotencyKey: string,
  ): string {
    const hex = createHash("sha256")
      .update(`${actorUserId}\0${operation}\0${idempotencyKey}`)
      .digest("hex")
      .slice(0, 32)
      .split("");
    hex[12] = "4";
    hex[16] = ["8", "9", "a", "b"][parseInt(hex[16]!, 16) % 4]!;
    const value = hex.join("");
    return [
      value.slice(0, 8),
      value.slice(8, 12),
      value.slice(12, 16),
      value.slice(16, 20),
      value.slice(20),
    ].join("-");
  }
}
