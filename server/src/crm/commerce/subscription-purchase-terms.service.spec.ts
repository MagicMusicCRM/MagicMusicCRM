import { SubscriptionPurchaseTermsService } from "./subscription-purchase-terms.service";
import { PurchaseSubscriptionPreviewDto } from "../dto/issue-subscription.dto";

describe("Subscription purchase validity", () => {
  const terms = new SubscriptionPurchaseTermsService();
  const purchase: PurchaseSubscriptionPreviewDto = {
    packageId: "11111111-1111-4111-8111-111111111111",
    payerStudentId: "22222222-2222-4222-8222-222222222222",
    fundingMode: "personal_account",
    startsAt: "2026-09-01",
  };

  it("sells without expiration when no end date is selected", () => {
    expect(terms.normalizeDates(purchase)).toEqual({
      startsAt: "2026-09-01", expiresAt: null,
    });
  });

  it("keeps an explicitly selected inclusive end date", () => {
    expect(terms.normalizeDates({ ...purchase, expiresAt: "2026-12-01" }))
      .toEqual({ startsAt: "2026-09-01", expiresAt: "2026-12-01" });
    expect(() => terms.normalizeDates({ ...purchase, expiresAt: "2026-08-31" }))
      .toThrow();
  });
});
