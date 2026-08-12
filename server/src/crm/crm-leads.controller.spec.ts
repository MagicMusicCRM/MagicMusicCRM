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

  it("delegates the additive lead subscription issue contract", async () => {
    const subscriptions = {
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

    await expect(
      controller.issueLeadSubscription(actor, "lead-a", {
        packageId: "package-a",
      }),
    ).resolves.toMatchObject({ converted: true });
    expect(subscriptions.issueLeadSubscription).toHaveBeenCalledWith(
      actor,
      "lead-a",
      { packageId: "package-a" },
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
