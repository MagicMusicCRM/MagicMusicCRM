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
import { fingerprintPayload } from "../../platform/platform-integrity.util";
import { CrmPolicy } from "../crm.policy";
import {
  IssueSubscriptionDiscountDto,
  IssueSubscriptionDto,
  IssueSubscriptionInstallmentDto,
  IssueSubscriptionSurchargeDto,
  PurchaseSubscriptionCommandDto,
  PurchaseSubscriptionPreviewDto,
} from "../dto/issue-subscription.dto";
import {
  IssuedCommercialSnapshot,
  IssuedDiscountSnapshot,
  IssuedSurchargeSnapshot,
} from "./commerce-schema.types";
import {
  IssueDiscountColumns,
  IssuePackageRow,
  PlannedInstallment,
  PurchaseContext,
  PurchaseStudentRow,
  SubscriptionIssueRepository,
} from "./subscription-issue.repository";
import { SubscriptionPurchasePreviewTokenPayload } from "./subscription-preview-token";
import { SubscriptionPreviewTokenService } from "./subscription-preview-token.service";
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

interface NormalizedSurcharge {
  snapshot: IssuedSurchargeSnapshot;
  amountMinor: string;
}

interface NormalizedPurchase {
  discount: NormalizedDiscount;
  surcharge: NormalizedSurcharge;
  finalPriceMinor: string;
  installments: PlannedInstallment[];
  snapshot: IssuedCommercialSnapshot;
  purchaseReason: string | null;
}

@Injectable()
export class SubscriptionIssueService {
  constructor(
    private readonly repository: SubscriptionIssueRepository,
    private readonly policy: CrmPolicy,
    private readonly integrity: PlatformIntegrityService,
    private readonly reservations: SubscriptionReservationService,
    private readonly previewTokens: SubscriptionPreviewTokenService,
  ) {}

  async previewPurchase(
    actor: ActorContext,
    recipientStudentId: string,
    dto: PurchaseSubscriptionPreviewDto,
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.assertPaymentMethod(dto.paymentMethod);
    const context = await this.repository.readPurchasePreviewContext(
      actor,
      recipientStudentId,
      dto.payerStudentId,
      dto.packageId,
    );
    const normalized = this.normalizePurchase(
      recipientStudentId,
      dto,
      this.assertPurchaseContext(
        context,
        recipientStudentId,
        dto.payerStudentId,
      ),
    );
    const tokenPayload = this.createPurchaseTokenPayload(
      actor,
      recipientStudentId,
      dto,
      context,
      normalized,
    );
    const signed = this.previewTokens.issuePurchase(tokenPayload);
    const shortageMinor =
      dto.fundingMode === "personal_account"
        ? (
            BigInt(normalized.finalPriceMinor) -
            BigInt(context.payerBalanceMinor)
          )
        : 0n;
    return {
      recipientStudentId,
      payerStudentId: dto.payerStudentId,
      packageId: dto.packageId,
      packageVersion: Number(context.package!.version),
      fundingMode: dto.fundingMode,
      currencyCode: context.package!.currency_code,
      finalPriceMinor: normalized.finalPriceMinor,
      payerBalanceMinor: context.payerBalanceMinor,
      balanceAfterMinor: (
        BigInt(context.payerBalanceMinor) -
        BigInt(normalized.finalPriceMinor)
      ).toString(),
      canCommit: shortageMinor <= 0n,
      shortageMinor: shortageMinor > 0n ? shortageMinor.toString() : "0",
      installments: normalized.snapshot.installments ?? [],
      previewToken: signed.token,
      previewExpiresAt: signed.expiresAt,
    };
  }

  async purchase(
    actor: ActorContext,
    recipientStudentId: string,
    dto: PurchaseSubscriptionCommandDto,
    metadata: CommerceMutationMetadata,
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.assertMetadata(metadata);
    this.assertPaymentMethod(dto.paymentMethod);
    const subscriptionId = this.deterministicId(
      actor.userId,
      "crm.subscription.purchase",
      metadata.idempotencyKey,
    );
    const audit: PlatformAuditInput = {
      action: "crm.subscription_purchased",
      entityType: "subscription",
      entityId: subscriptionId,
      reason: "subscription_purchase",
      metadata: {
        recipientStudentId,
        payerStudentId: dto.payerStudentId,
        packageId: dto.packageId,
        fundingMode: dto.fundingMode,
      },
    };
    const result =
      await this.integrity.executeVersionedMutation<IssueMutationResult>({
        actorKey: actor.userId,
        actorUserId: actor.userId,
        authorization: {
          actor,
          capabilityKey: "commerce.client_finance.write",
        },
        operation: "crm.subscription.purchase",
        idempotencyKey: metadata.idempotencyKey,
        requestId: metadata.requestId,
        aggregateType: "commerce:issued-subscription",
        aggregateId: subscriptionId,
        expectedVersion: 0,
        payload: {
          recipientStudentId,
          payerStudentId: dto.payerStudentId,
          fundingMode: dto.fundingMode,
          commandFingerprint: fingerprintPayload(dto),
        },
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
          const signedPayload = this.previewTokens.verifyPurchase(
            dto.previewToken,
          );
          this.assertPurchaseTokenBinding(
            signedPayload,
            actor,
            recipientStudentId,
            dto,
          );
          const students = await this.repository.lockPurchaseStudents(
            client,
            actor,
            [recipientStudentId, dto.payerStudentId],
          );
          const packageRow =
            await this.repository.findActivePackageForShare(
              client,
              dto.packageId,
            );
          const context: PurchaseContext = {
            students,
            package: packageRow,
            payerBalanceMinor: packageRow
              ? await this.repository.readAccountBalance(
                  client,
                  dto.payerStudentId,
                  packageRow.currency_code,
                )
              : "0",
          };
          const activePackage = this.assertPurchaseContext(
            context,
            recipientStudentId,
            dto.payerStudentId,
          );
          const normalized = this.normalizePurchase(
            recipientStudentId,
            dto,
            activePackage,
          );
          audit.reasonText = this.auditReasonForPurchase(normalized);
          this.assertPurchasePreviewStillCurrent(
            signedPayload,
            this.createPurchaseTokenPayload(
              actor,
              recipientStudentId,
              dto,
              context,
              normalized,
            ),
          );
          if (
            dto.fundingMode === "personal_account" &&
            BigInt(context.payerBalanceMinor) <
              BigInt(normalized.finalPriceMinor)
          ) {
            throw new UnprocessableEntityException({
              code: "INSUFFICIENT_PERSONAL_ACCOUNT_BALANCE",
              message:
                "На личном счёте плательщика недостаточно средств для полной покупки.",
              availableMinor: context.payerBalanceMinor,
              requiredMinor: normalized.finalPriceMinor,
            });
          }
          const subscription =
            await this.repository.createIssuedSubscription(client, {
              id: subscriptionId,
              studentId: recipientStudentId,
              payerStudentId: dto.payerStudentId,
              fundingMode: dto.fundingMode,
              purchaseReason: normalized.purchaseReason,
              package: activePackage,
              snapshot: normalized.snapshot,
              discount: normalized.discount.columns,
              finalPriceMinor: normalized.finalPriceMinor,
              version: nextVersion,
            });
          await this.repository.createInstallments(client, {
            issuedSubscriptionId: subscription.id,
            currencyCode: activePackage.currency_code,
            installments: normalized.installments,
          });
          await this.repository.createObligations(client, {
            studentId: dto.payerStudentId,
            issuedSubscriptionId: subscription.id,
            currencyCode: activePackage.currency_code,
            finalPriceMinor: normalized.finalPriceMinor,
            installments: normalized.installments,
            singlePurchaseDebit: true,
          });
          await this.repository.createIssueLifecycle(client, {
            issuedSubscriptionId: subscription.id,
            actorUserId: actor.userId,
            version: nextVersion,
            reason:
              normalized.purchaseReason ?? "Покупка абонемента",
          });
          audit.afterRef = {
            subscriptionId: subscription.id,
            subscriptionVersion: nextVersion,
            recipientStudentId,
            payerStudentId: dto.payerStudentId,
            packageId: activePackage.id,
            packageVersion: Number(activePackage.version),
          };
          return { entityId: subscription.id, version: nextVersion };
        },
      });
    const response = await this.loadStableIssueResult(
      result.resultRef.entityId,
      result.resultRef.version,
    );
    if (!result.replayed) {
      await this.reservations.publishPostCommit({
        studentId: recipientStudentId,
        payerStudentId: dto.payerStudentId,
        subscriptionId: result.resultRef.entityId,
      });
    }
    return response;
  }

  async issue(
    actor: ActorContext,
    studentId: string,
    dto: IssueSubscriptionDto,
    metadata: CommerceMutationMetadata,
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.assertMetadata(metadata);
    this.assertPaymentMethod(dto.paymentMethod);
    await this.repository.assertStudentsInScope(actor, [studentId]);
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
        authorization: {
          actor,
          capabilityKey: "commerce.subscription.issue",
        },
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
          if (
            (await this.repository.lockPurchaseStudents(
              client,
              actor,
              [studentId],
            )).length !== 1
          ) {
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
          const surcharge = this.normalizeSurcharge(dto.surcharge);
          const finalPriceMinor = (
            BigInt(discount.finalPriceMinor) + BigInt(surcharge.amountMinor)
          ).toString();
          const installments = this.normalizeInstallments(
            dto.installments,
            finalPriceMinor,
          );
          audit.reasonText =
            discount.columns.reason ??
            (surcharge.snapshot.type === "fixed"
              ? surcharge.snapshot.reason
              : null) ??
            "Выдача абонемента";
          const snapshot = this.createSnapshot(
            packageRow,
            discount,
            surcharge,
            finalPriceMinor,
            installments,
            dto.paymentMethod ?? null,
          );
          const subscription =
            await this.repository.createIssuedSubscription(client, {
              id: subscriptionId,
              studentId,
              payerStudentId: studentId,
              fundingMode: "legacy",
              purchaseReason: null,
              package: packageRow,
              snapshot,
              discount: discount.columns,
              finalPriceMinor,
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
            finalPriceMinor,
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

  private normalizePurchase(
    recipientStudentId: string,
    dto: PurchaseSubscriptionPreviewDto,
    packageRow: IssuePackageRow,
  ): NormalizedPurchase {
    const purchaseReason = dto.purchaseReason?.trim() || null;
    if (purchaseReason && purchaseReason.length > 500) {
      throw new UnprocessableEntityException({
        code: "PURCHASE_REASON_TOO_LONG",
        field: "purchaseReason",
        message: "Причина покупки не должна превышать 500 символов.",
      });
    }
    if (
      dto.payerStudentId !== recipientStudentId &&
      purchaseReason === null
    ) {
      throw new UnprocessableEntityException({
        code: "PURCHASE_REASON_REQUIRED",
        field: "purchaseReason",
        message:
          "При оплате со счёта другого клиента обязательно укажите причину.",
      });
    }
    if (
      dto.fundingMode !== "personal_account" &&
      dto.fundingMode !== "installment"
    ) {
      throw new UnprocessableEntityException({
        code: "FUNDING_MODE_INVALID",
        field: "fundingMode",
        message: "Выберите личный счёт или рассрочку.",
      });
    }
    if (
      dto.fundingMode === "personal_account" &&
      dto.installments !== undefined
    ) {
      throw new UnprocessableEntityException({
        code: "PERSONAL_ACCOUNT_INSTALLMENTS_FORBIDDEN",
        field: "installments",
        message: "При покупке с личного счёта рассрочка не применяется.",
      });
    }
    if (
      dto.fundingMode === "installment" &&
      dto.installments === undefined
    ) {
      throw new UnprocessableEntityException({
        code: "INSTALLMENTS_REQUIRED",
        field: "installments",
        message: "Для рассрочки укажите график платежей.",
      });
    }
    const discount = this.normalizeDiscount(
      dto.discount,
      packageRow.base_price_minor,
    );
    const surcharge = this.normalizeSurcharge(dto.surcharge);
    const finalPriceMinor = (
      BigInt(discount.finalPriceMinor) + BigInt(surcharge.amountMinor)
    ).toString();
    const installments = this.normalizeInstallments(
      dto.installments,
      finalPriceMinor,
    );
    const snapshot = this.createSnapshot(
      packageRow,
      discount,
      surcharge,
      finalPriceMinor,
      installments,
      dto.paymentMethod ?? null,
    );
    snapshot.commercialRules = {
      fundingMode: dto.fundingMode,
      payerStudentId: dto.payerStudentId,
    };
    return {
      discount,
      surcharge,
      finalPriceMinor,
      installments,
      snapshot,
      purchaseReason,
    };
  }

  private auditReasonForPurchase(normalized: NormalizedPurchase): string {
    return (
      normalized.purchaseReason ??
      normalized.discount.columns.reason ??
      (normalized.surcharge.snapshot.type === "fixed"
        ? normalized.surcharge.snapshot.reason
        : "Покупка абонемента")
    );
  }

  private assertPurchaseContext(
    context: PurchaseContext,
    recipientStudentId: string,
    payerStudentId: string,
  ): IssuePackageRow {
    const expected = new Set([recipientStudentId, payerStudentId]);
    const found = new Set(context.students.map((student) => student.id));
    if (found.size !== expected.size || [...expected].some((id) => !found.has(id))) {
      throw new NotFoundException(
        "Получатель или плательщик не найден в доступной области.",
      );
    }
    const packageRow = context.package;
    if (!packageRow) {
      throw new NotFoundException(
        "Абонемент не найден или находится в архиве.",
      );
    }
    const recipient = this.purchaseStudent(context.students, recipientStudentId);
    if (
      packageRow.branch_id !== null &&
      packageRow.branch_id !== recipient.branch_id
    ) {
      throw new NotFoundException(
        "Абонемент недоступен в филиале получателя.",
      );
    }
    return packageRow;
  }

  private createPurchaseTokenPayload(
    actor: ActorContext,
    recipientStudentId: string,
    dto: PurchaseSubscriptionPreviewDto,
    context: PurchaseContext,
    normalized: NormalizedPurchase,
  ): Omit<
    SubscriptionPurchasePreviewTokenPayload,
    "issuedAtSeconds" | "expiresAtSeconds"
  > {
    const recipient = this.purchaseStudent(
      context.students,
      recipientStudentId,
    );
    const payer = this.purchaseStudent(
      context.students,
      dto.payerStudentId,
    );
    const packageRow = context.package!;
    return {
      kind: "subscription.purchase",
      actorUserId: actor.userId,
      recipientStudentId,
      payerStudentId: dto.payerStudentId,
      recipientVersion: Number(recipient.version),
      payerVersion: Number(payer.version),
      recipientBranchId: recipient.branch_id,
      payerBranchId: payer.branch_id,
      packageId: packageRow.id,
      packageVersion: Number(packageRow.version),
      currencyCode: packageRow.currency_code,
      finalPriceMinor: normalized.finalPriceMinor,
      payerBalanceMinor: context.payerBalanceMinor,
      fundingMode: dto.fundingMode,
      purchaseFingerprint: fingerprintPayload({
        recipientStudentId,
        payerStudentId: dto.payerStudentId,
        packageId: packageRow.id,
        packageVersion: Number(packageRow.version),
        fundingMode: dto.fundingMode,
        purchaseReason: normalized.purchaseReason,
        discount: normalized.discount.snapshot,
        surcharge: normalized.surcharge.snapshot,
        finalPriceMinor: normalized.finalPriceMinor,
        installments: normalized.installments,
        paymentMethod: dto.paymentMethod ?? null,
      }),
    };
  }

  private assertPurchaseTokenBinding(
    payload: SubscriptionPurchasePreviewTokenPayload,
    actor: ActorContext,
    recipientStudentId: string,
    dto: PurchaseSubscriptionPreviewDto,
  ): void {
    if (
      payload.actorUserId !== actor.userId ||
      payload.recipientStudentId !== recipientStudentId ||
      payload.payerStudentId !== dto.payerStudentId ||
      payload.packageId !== dto.packageId ||
      payload.fundingMode !== dto.fundingMode
    ) {
      throw new UnprocessableEntityException({
        code: "PREVIEW_TOKEN_SCOPE_MISMATCH",
        message: "Предпросмотр создан для другой покупки или сотрудника.",
      });
    }
  }

  private assertPurchasePreviewStillCurrent(
    signed: SubscriptionPurchasePreviewTokenPayload,
    current: Omit<
      SubscriptionPurchasePreviewTokenPayload,
      "issuedAtSeconds" | "expiresAtSeconds"
    >,
  ): void {
    const {
      issuedAtSeconds: _issuedAtSeconds,
      expiresAtSeconds: _expiresAtSeconds,
      ...signedFacts
    } = signed;
    if (fingerprintPayload(signedFacts) !== fingerprintPayload(current)) {
      throw new ConflictException({
        code: "PURCHASE_PREVIEW_STALE",
        message:
          "После предпросмотра изменились счёт, клиент, филиал или условия абонемента.",
      });
    }
  }

  private purchaseStudent(
    students: PurchaseStudentRow[],
    studentId: string,
  ): PurchaseStudentRow {
    const student = students.find((item) => item.id === studentId);
    if (!student) throw new NotFoundException("Клиент не найден.");
    return student;
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
    if (!reason || reason.length > 500) {
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

  private normalizeSurcharge(
    dto: IssueSubscriptionSurchargeDto | undefined,
  ): NormalizedSurcharge {
    if (!dto) return { snapshot: { type: "none" }, amountMinor: "0" };
    const reason = dto.reason?.trim();
    if (!reason || reason.length > 500) {
      throw new UnprocessableEntityException({
        code: "SURCHARGE_REASON_REQUIRED",
        field: "surcharge.reason",
        message: "Для доплаты обязательно укажите причину.",
      });
    }
    if (!/^[1-9]\d*$/.test(dto.amountMinor)) {
      throw new UnprocessableEntityException({
        code: "SURCHARGE_AMOUNT_INVALID",
        field: "surcharge.amountMinor",
        message: "Доплата должна быть положительной суммой.",
      });
    }
    const amount = BigInt(dto.amountMinor);
    if (amount > 999_999_999_999n) {
      throw new UnprocessableEntityException({
        code: "SURCHARGE_AMOUNT_OUT_OF_RANGE",
        field: "surcharge.amountMinor",
        message: "Доплата выходит за допустимый диапазон.",
      });
    }
    return {
      snapshot: { type: "fixed", amountMinor: amount.toString(), reason },
      amountMinor: amount.toString(),
    };
  }

  private createSnapshot(
    packageRow: IssuePackageRow,
    discount: NormalizedDiscount,
    surcharge: NormalizedSurcharge,
    finalPriceMinor: string,
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
      surcharge: surcharge.snapshot,
      finalPriceMinor,
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
        payerStudentId: subscription.payer_student_id,
        fundingMode: subscription.funding_mode,
        purchaseReason: subscription.purchase_reason,
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
