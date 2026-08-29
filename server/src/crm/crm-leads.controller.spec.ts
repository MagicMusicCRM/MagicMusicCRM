import { BlacklistService } from "./blacklist.service";
import { CrmLeadsController } from "./crm-leads.controller";
import { DuplicatesService } from "./duplicates.service";
import { LeadsService } from "./leads.service";
import { MergeService } from "./merge.service";
import { PhoneReviewService } from "./phone-review.service";
import { SubscriptionsService } from "./subscriptions.service";
import { ClientWriteValidator } from "./clients/client-write.validator";

describe("CrmLeadsController", () => {
  it("validates manual Lead creation before the legacy write service", async () => {
    const leads = {
      createLead: jest.fn().mockResolvedValue({ id: "lead-a" }),
    };
    const clientWrites = {
      validateLeadCreate: jest.fn().mockResolvedValue({
        firstName: "Анна",
        lastName: "Иванова",
        phone: "+79990000000",
        sourceId: "source-a",
        sourceCanonicalName: "site",
        sourceDisplayName: "Сайт",
        branchId: "branch-a",
        status: "new",
        customFields: [],
        warnings: [],
      }),
    };
    const controller = new CrmLeadsController(
      {} as BlacklistService,
      {} as DuplicatesService,
      leads as unknown as LeadsService,
      {} as MergeService,
      {} as PhoneReviewService,
      {} as SubscriptionsService,
      clientWrites as unknown as ClientWriteValidator,
    );
    const actor = { userId: "admin-a", role: "admin" as const };
    const dto = {
      firstName: "Анна",
      lastName: "Иванова",
      phone: "+79990000000",
      sourceId: "source-a",
      branchId: "branch-a",
      status: "new",
    };

    await expect(controller.createLead(actor, dto)).resolves.toEqual({
      id: "lead-a",
    });
    expect(clientWrites.validateLeadCreate).toHaveBeenCalledWith(dto);
    expect(leads.createLead).toHaveBeenCalledWith(
      actor,
      {
        firstName: "Анна",
        lastName: "Иванова",
        phone: "+79990000000",
        source: "Сайт",
        statusId: "new",
        customDataPatch: { branchId: "branch-a" },
      },
      expect.objectContaining({ sourceId: "source-a" }),
    );
  });

  it("delegates lead preview and idempotent purchase to the unified contract", async () => {
    const subscriptions = {
      previewLeadSubscriptionPurchase: jest.fn().mockResolvedValue({
        previewToken: "signed-preview",
      }),
      issueLeadSubscription: jest.fn().mockResolvedValue({
        student: { id: "student-a" },
        subscription: { id: "subscription-a" },
        payment: { id: "payment-a" },
        converted: true,
      }),
    };
    const controller = new CrmLeadsController(
      {} as BlacklistService,
      {} as DuplicatesService,
      {} as LeadsService,
      {} as MergeService,
      {} as PhoneReviewService,
      subscriptions as unknown as SubscriptionsService,
      {} as ClientWriteValidator,
    );
    const actor = { userId: "admin-a", role: "admin" as const };
    const previewDto = {
      packageId: "package-a",
      payerStudentId: "lead-a",
      fundingMode: "personal_account" as const,
      startsAt: "2026-08-29",
      expiresAt: "2026-09-29",
      paymentAmountMinor: "800000",
      paymentOccurredAt: "2026-08-29T12:00:00.000Z",
      paymentMethod: "cashless" as const,
    };

    await expect(
      controller.previewLeadSubscriptionPurchase(actor, "lead-a", previewDto),
    ).resolves.toMatchObject({ previewToken: "signed-preview" });
    await expect(
      controller.purchaseLeadSubscription(
        actor,
        "lead-a",
        "lead-purchase-key",
        "lead-purchase-request",
        {
          ...previewDto,
          previewToken: "signed-preview",
          confirm: true,
        },
      ),
    ).resolves.toMatchObject({ converted: true });
    expect(subscriptions.previewLeadSubscriptionPurchase).toHaveBeenCalledWith(
      actor,
      "lead-a",
      previewDto,
    );
    expect(subscriptions.issueLeadSubscription).toHaveBeenCalledWith(
      actor,
      "lead-a",
      { ...previewDto, previewToken: "signed-preview", confirm: true },
      {
        idempotencyKey: "lead-purchase-key",
        requestId: "lead-purchase-request",
      },
    );
  });

  it("adapts the legacy lead issue route to the canonical preview and purchase owner", async () => {
    const subscriptions = {
      previewLeadSubscriptionPurchase: jest
        .fn()
        .mockResolvedValueOnce({
          finalPriceMinor: "800000",
          paidNowMinor: "800000",
          previewToken: "legacy-preview-token",
        }),
      issueLeadSubscription: jest.fn().mockResolvedValue({
        subscription: { id: "subscription-a" },
      }),
    };
    const controller = new CrmLeadsController(
      {} as BlacklistService,
      {} as DuplicatesService,
      {} as LeadsService,
      {} as MergeService,
      {} as PhoneReviewService,
      subscriptions as unknown as SubscriptionsService,
      {} as ClientWriteValidator,
    );
    const actor = { userId: "admin-a", role: "admin" as const };
    const leadId = "11111111-1111-4111-8111-111111111111";
    const packageId = "22222222-2222-4222-8222-222222222222";
    const legacyDto = { packageId };

    await controller.issueLegacyLeadSubscription(
      actor,
      leadId,
      undefined,
      undefined,
      legacyDto,
    );

    const purchase = {
      ...legacyDto,
      payerStudentId: leadId,
      fundingMode: "personal_account",
    };
    expect(
      subscriptions.previewLeadSubscriptionPurchase,
    ).toHaveBeenNthCalledWith(
      1,
      actor,
      leadId,
      purchase,
      true,
    );
    expect(subscriptions.previewLeadSubscriptionPurchase).toHaveBeenCalledTimes(
      1,
    );
    expect(subscriptions.issueLeadSubscription).toHaveBeenCalledWith(
      actor,
      leadId,
      { ...purchase, previewToken: "legacy-preview-token", confirm: true },
      {
        idempotencyKey: `legacy-lead:${leadId}:${packageId}`,
        requestId: `legacy-lead:${leadId}`,
      },
      true,
    );
  });

  it("validates typed fields before an existing Lead update", async () => {
    const leads = { updateLead: jest.fn().mockResolvedValue({ id: "lead-a" }) };
    const validated = { values: [{ definitionId: "field-a" }], warnings: [] };
    const clientWrites = {
      validateCustomFields: jest.fn().mockResolvedValue(validated),
    };
    const controller = new CrmLeadsController(
      {} as BlacklistService,
      {} as DuplicatesService,
      leads as unknown as LeadsService,
      {} as MergeService,
      {} as PhoneReviewService,
      {} as SubscriptionsService,
      clientWrites as unknown as ClientWriteValidator,
    );
    const actor = { userId: "admin-a", role: "admin" as const };
    const dto = {
      expectedVersion: 1,
      firstName: "Анна",
      customFields: [{ definitionId: "field-a", value: "Вокал" }],
    };

    await controller.updateLead(actor, "lead-a", dto);

    expect(clientWrites.validateCustomFields).toHaveBeenCalledWith(
      "lead",
      dto.customFields,
    );
    expect(leads.updateLead).toHaveBeenCalledWith(
      actor,
      "lead-a",
      dto,
      validated,
    );
  });
});
