import { ForbiddenException, Injectable } from "@nestjs/common";
import {
  ActorClientProjectionFactory,
  ClientProjectionProfile,
} from "../../access-control/actor-client-projection.factory";
import { ActorContext } from "../../common/security/actor-context";
import {
  CommerceDiscountDto,
  CommerceProjectionScope,
  CommerceProjectionSource,
  CommerceSurchargeDto,
  CommerceStudentDto,
} from "./commerce-projection.types";

@Injectable()
export class CommerceProjectionFactory {
  constructor(
    private readonly clientProjection: ActorClientProjectionFactory,
  ) {}

  profileFor(actor: ActorContext): ClientProjectionProfile {
    return this.clientProjection.profileFor(actor.role);
  }

  cachePartitionKey(
    actor: ActorContext,
    scope: CommerceProjectionScope,
  ): string {
    this.assertReadable(actor);
    return this.clientProjection.cachePartitionKey({
      actor,
      accessVersion: scope.accessVersion,
      surface: "finance",
      scopeKey: scope.scopeKey,
    });
  }

  projectStudent(
    actor: ActorContext,
    source: CommerceProjectionSource,
  ): CommerceStudentDto {
    this.assertReadable(actor);
    const subscriptions = source.subscriptions.map((subscription) => ({
      id: subscription.id,
      status: subscription.status,
      startsAt: subscription.startsAt,
      expiresAt: subscription.expiresAt,
      units: {
        total: subscription.units.total,
        used: subscription.units.used,
        reserved: subscription.units.reserved,
        paid: subscription.units.paid,
        available: subscription.units.available,
        remaining: subscription.units.remaining,
      },
      financial: { ...subscription.financial },
      terms: {
        displayName: subscription.terms.displayName,
        validityDays: subscription.terms.validityDays,
        basePriceMinor: subscription.terms.basePriceMinor,
        finalPriceMinor: subscription.terms.finalPriceMinor,
        currencyCode: subscription.terms.currencyCode,
        discount: this.projectDiscount(
          actor,
          subscription.terms.discount,
        ),
        surcharge: this.projectSurcharge(
          actor,
          subscription.terms.surcharge ?? { type: "none" },
        ),
      },
      installments: subscription.installments.map((installment) => {
        return {
          installmentNumber: installment.installmentNumber,
          dueAt: installment.dueAt,
          amountMinor: installment.amountMinor,
          currencyCode: installment.currencyCode,
          status: installment.status,
        };
      }),
    }));

    return {
      studentId: source.studentId,
      accounts: source.accounts.map((account) => ({
        currencyCode: account.currencyCode,
        actualPaymentsMinor: account.actualPaymentsMinor,
        adjustmentsMinor: account.adjustmentsMinor,
        obligationDebitsMinor: account.obligationDebitsMinor,
        obligationCreditsMinor: account.obligationCreditsMinor,
        writeOffsMinor: account.writeOffsMinor,
        balanceMinor: account.balanceMinor,
        debtMinor: account.debtMinor,
        pendingMinor: account.pendingMinor,
        remainingObligationMinor: account.remainingObligationMinor,
      })),
      subscriptions,
      movements: source.movements.map((movement) => ({
        id: movement.id,
        kind: movement.kind,
        direction: movement.direction,
        amountMinor: movement.amountMinor,
        currencyCode: movement.currencyCode,
        occurredAt: movement.occurredAt,
        method: movement.method,
        factType: movement.factType,
        chargeType: movement.chargeType,
        branchId: movement.branchId ?? null,
        branchName: movement.branchName ?? null,
        comment: actor.role === "client" ? null : movement.comment ?? null,
        invoiceIdentifier: movement.invoiceIdentifier ?? null,
        status: movement.status ?? null,
        acceptedByName: movement.acceptedByName ?? null,
        issuedSubscriptionId: movement.issuedSubscriptionId ?? null,
        subscriptionName: movement.subscriptionName ?? null,
        sourcePaymentId: movement.sourcePaymentId ?? null,
        paymentRecordVersion: movement.paymentRecordVersion ?? null,
        installmentId: movement.installmentId ?? null,
        dueAt: movement.dueAt ?? null,
      })),
      technicalHistory:
        actor.role === "client"
          ? []
          : (source.technicalHistory ?? []).map((event) => ({ ...event })),
      lessonBalance: this.lessonBalance(subscriptions),
    };
  }

  private lessonBalance(
    subscriptions: CommerceStudentDto["subscriptions"],
  ): CommerceStudentDto["lessonBalance"] {
    const active = subscriptions.filter((item) => item.status === "active");
    const sumUnits = (
      field: "total" | "used" | "reserved" | "paid" | "available",
    ) => active.reduce((sum, item) => sum + Number(item.units[field]), 0).toString();
    const debts = new Map<string, bigint>();
    for (const item of active) {
      debts.set(
        item.terms.currencyCode,
        (debts.get(item.terms.currencyCode) ?? 0n) +
          BigInt(item.financial.debtMinor),
      );
    }
    const earliest = (values: (string | null)[]) =>
      values.filter((value): value is string => value !== null).sort()[0] ?? null;
    return {
      activeSubscriptionCount: active.length,
      total: sumUnits("total"),
      used: sumUnits("used"),
      reserved: sumUnits("reserved"),
      paid: sumUnits("paid"),
      available: sumUnits("available"),
      debts: [...debts]
        .filter(([, amount]) => amount > 0n)
        .map(([currencyCode, amount]) => ({
          currencyCode,
          amountMinor: amount.toString(),
        })),
      nextPaymentAt: earliest(
        active.map((item) => item.financial.nextPaymentAt),
      ),
      expiresAt: earliest(active.map((item) => item.expiresAt)),
    };
  }

  private projectDiscount(
    actor: ActorContext,
    discount: CommerceDiscountDto,
  ): CommerceDiscountDto {
    if (discount.type === "none") return { type: "none" };
    if (discount.type === "percent") {
      return actor.role === "client"
        ? {
            type: "percent",
            percentBasisPoints: discount.percentBasisPoints,
          }
        : {
            type: "percent",
            percentBasisPoints: discount.percentBasisPoints,
            ...(typeof discount.reason === "string"
              ? { reason: discount.reason }
              : {}),
          };
    }
    return actor.role === "client"
      ? { type: "fixed", fixedMinor: discount.fixedMinor }
      : {
          type: "fixed",
          fixedMinor: discount.fixedMinor,
          ...(typeof discount.reason === "string"
            ? { reason: discount.reason }
            : {}),
        };
  }

  private projectSurcharge(
    actor: ActorContext,
    surcharge: CommerceSurchargeDto,
  ): CommerceSurchargeDto {
    if (surcharge.type === "none") return { type: "none" };
    return actor.role === "client"
      ? { type: "fixed", amountMinor: surcharge.amountMinor }
      : {
          type: "fixed",
          amountMinor: surcharge.amountMinor,
          ...(typeof surcharge.reason === "string"
            ? { reason: surcharge.reason }
            : {}),
        };
  }

  private assertReadable(actor: ActorContext): void {
    if (actor.role === "teacher") {
      throw new ForbiddenException({
        code: "COMMERCE_PROJECTION_TEACHER_DENIED",
        message: "Teacher commerce projections are not available.",
      });
    }
  }
}
