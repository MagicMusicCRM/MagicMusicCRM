import { BlacklistService } from "./blacklist.service";
import { CrmLeadsController } from "./crm-leads.controller";
import { DuplicatesService } from "./duplicates.service";
import { LeadsService } from "./leads.service";
import { MergeService } from "./merge.service";
import { PhoneReviewService } from "./phone-review.service";
import { SubscriptionsService } from "./subscriptions.service";

describe("CrmLeadsController", () => {
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
});
