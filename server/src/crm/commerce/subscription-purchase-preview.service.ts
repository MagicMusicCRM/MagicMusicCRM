import {
  ConflictException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import { fingerprintPayload } from "../../platform/platform-integrity.util";
import { CrmPolicy } from "../crm.policy";
import {
  PurchaseSubscriptionCommandDto,
  PurchaseSubscriptionPreviewDto,
} from "../dto/issue-subscription.dto";
import { SubscriptionCommercialTermsService } from "./subscription-commercial-terms.service";
import {
  NormalizedPurchase,
  UnsignedPurchaseTokenPayload,
} from "./subscription-issue.contracts";
import {
  IssuePackageRow,
  PurchaseContext,
  PurchaseStudentRow,
  SubscriptionIssueRepository,
} from "./subscription-issue.repository";
import { SubscriptionPurchasePreviewTokenPayload } from "./subscription-preview-token";
import { SubscriptionPreviewTokenService } from "./subscription-preview-token.service";

@Injectable()
export class SubscriptionPurchasePreviewService {
  constructor(
    private readonly repository: SubscriptionIssueRepository,
    private readonly policy: CrmPolicy,
    private readonly terms: SubscriptionCommercialTermsService,
    private readonly previewTokens: SubscriptionPreviewTokenService,
  ) {}

  async previewPurchase(
    actor: ActorContext,
    recipientStudentId: string,
    dto: PurchaseSubscriptionPreviewDto,
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.terms.assertPaymentMethod(dto.paymentMethod);
    const context = await this.repository.readPurchasePreviewContext(
      actor,
      recipientStudentId,
      dto.payerStudentId,
      dto.packageId,
    );
    return this.previewFromContext(actor, recipientStudentId, dto, context);
  }

  previewFromContext(
    actor: ActorContext,
    recipientStudentId: string,
    dto: PurchaseSubscriptionPreviewDto,
    context: PurchaseContext,
    legacyLeadAutoPayment = false,
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.terms.assertPaymentMethod(dto.paymentMethod);
    const issuedAt = new Date(Math.floor(Date.now() / 1_000) * 1_000);
    const boundDto = this.terms.bindPurchaseDefaults(
      dto,
      issuedAt,
      legacyLeadAutoPayment,
    );
    const normalized = this.terms.normalizePurchase(
      recipientStudentId,
      boundDto,
      this.assertPurchaseContext(
        context,
        recipientStudentId,
        dto.payerStudentId,
      ),
      legacyLeadAutoPayment,
    );
    const signed = this.previewTokens.issuePurchase(
      this.createTokenPayload(
        actor,
        recipientStudentId,
        boundDto,
        context,
        normalized,
      ),
      issuedAt,
    );
    const shortageMinor = this.shortageMinor(
      normalized.finalPriceMinor,
      normalized.payment.amountMinor,
    );
    const balanceAfterMinor =
      BigInt(normalized.payment.amountMinor) -
      BigInt(normalized.finalPriceMinor);
    return {
      recipientStudentId,
      payerStudentId: dto.payerStudentId,
      packageId: dto.packageId,
      packageVersion: Number(context.package!.version),
      fundingMode: dto.fundingMode,
      currencyCode: context.package!.currency_code,
      finalPriceMinor: normalized.finalPriceMinor,
      payerBalanceMinor: context.payerBalanceMinor,
      paidNowMinor: normalized.payment.amountMinor,
      balanceAfterMinor: balanceAfterMinor.toString(),
      canCommit: true,
      shortageMinor: shortageMinor > 0n ? shortageMinor.toString() : "0",
      debtMinor: balanceAfterMinor < 0n ? (-balanceAfterMinor).toString() : "0",
      overpaymentMinor:
        balanceAfterMinor > 0n ? balanceAfterMinor.toString() : "0",
      installments: normalized.snapshot.installments ?? [],
      previewToken: signed.token,
      previewExpiresAt: signed.expiresAt,
    };
  }

  decodeBoundToken(
    actor: ActorContext,
    recipientStudentId: string,
    dto: PurchaseSubscriptionCommandDto,
  ): SubscriptionPurchasePreviewTokenPayload {
    const payload = this.previewTokens.verifyPurchase(dto.previewToken);
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
    return payload;
  }

  assertPurchaseContext(
    context: PurchaseContext,
    recipientStudentId: string,
    payerStudentId: string,
  ): IssuePackageRow {
    const expected = new Set([recipientStudentId, payerStudentId]);
    const found = new Set(context.students.map((student) => student.id));
    if (
      found.size !== expected.size ||
      [...expected].some((id) => !found.has(id))
    ) {
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
    const recipient = this.purchaseStudent(
      context.students,
      recipientStudentId,
    );
    if (
      packageRow.branch_id !== null &&
      packageRow.branch_id !== recipient.branch_id
    ) {
      throw new NotFoundException("Абонемент недоступен в филиале получателя.");
    }
    return packageRow;
  }

  createTokenPayload(
    actor: ActorContext,
    recipientStudentId: string,
    dto: PurchaseSubscriptionPreviewDto,
    context: PurchaseContext,
    normalized: NormalizedPurchase,
  ): UnsignedPurchaseTokenPayload {
    const recipient = this.purchaseStudent(
      context.students,
      recipientStudentId,
    );
    const payer = this.purchaseStudent(context.students, dto.payerStudentId);
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
        startsAt: normalized.startsAt,
        expiresAt: normalized.expiresAt,
        paymentAmountMinor: normalized.payment.amountMinor,
        paymentOccurredAt: normalized.payment.occurredAt?.toISOString() ?? null,
        paymentComment: normalized.payment.comment,
      }),
    };
  }

  assertStillCurrent(
    signed: SubscriptionPurchasePreviewTokenPayload,
    current: UnsignedPurchaseTokenPayload,
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

  private shortageMinor(
    finalPriceMinor: string,
    paidNowMinor: string,
  ): bigint {
    const shortage = BigInt(finalPriceMinor) - BigInt(paidNowMinor);
    return shortage > 0n ? shortage : 0n;
  }
}
