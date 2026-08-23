import { resolveAppealDate } from "../crm/appeal-date";
import { resolveAge } from "../crm/age";
import { SubscriptionPreviewTokenService } from "../crm/commerce/subscription-preview-token.service";
import { UpsertExpenseDto } from "../crm/dto/upsert-expense.dto";
import { ClientPipelineQuery } from "../crm/dto/student-funnel.dto";
import { LeadsService } from "../crm/leads.service";
import { toLessonDto } from "../crm/crm-mappers";
import { UpdateNotificationPreferenceDto } from "../notifications/dto/update-notification-preference.dto";
import { resolveV4DomainRollout } from "../platform/rollout/v4/domain-flags";

describe("cleanup export surface", () => {
  it("keeps required neighboring module exports available", () => {
    expect(typeof toLessonDto).toBe("function");
    expect(typeof LeadsService).toBe("function");
    expect(typeof UpsertExpenseDto).toBe("function");
    expect(typeof ClientPipelineQuery).toBe("function");
    expect(typeof UpdateNotificationPreferenceDto).toBe("function");
    expect(typeof resolveAge).toBe("function");
    expect(typeof resolveAppealDate).toBe("function");
    expect(typeof SubscriptionPreviewTokenService).toBe("function");
    expect(typeof resolveV4DomainRollout).toBe("function");
  });
});
