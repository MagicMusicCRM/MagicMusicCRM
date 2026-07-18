import { DatabaseService } from "../db/database.service";
import { AdminStaffController } from "./admin-staff.controller";
import { CrmPolicy } from "./crm.policy";
import {
  ACTIVE_RESPONSIBLE_STAFF_STATUSES,
  RESPONSIBLE_AUTH_ROLES,
} from "./responsible-eligibility";

describe("AdminStaffController responsible picker", () => {
  it("keeps manager authorization and returns only strictly eligible user ids", async () => {
    const query = jest.fn().mockResolvedValue({
      rows: [
        {
          id: "11111111-1111-4111-8111-111111111111",
          display_name: "Мария Менеджер",
          role: "manager",
        },
      ],
    });
    const database = { query } as unknown as DatabaseService;
    const policy = { assertManagerOnly: jest.fn() } as unknown as CrmPolicy;
    const controller = new AdminStaffController(database, policy);
    const actor = { userId: "manager-a", role: "manager" as const };

    await expect(
      controller.listStaff(actor, { search: "Мария" }),
    ).resolves.toEqual([
      {
        id: "11111111-1111-4111-8111-111111111111",
        displayName: "Мария Менеджер",
        role: "manager",
      },
    ]);

    expect(policy.assertManagerOnly).toHaveBeenCalledWith(actor);
    expect(String(query.mock.calls[0][0])).toContain("from app.staff_members");
    expect(query.mock.calls[0][1]).toEqual([
      [...RESPONSIBLE_AUTH_ROLES],
      "Мария",
      [...ACTIVE_RESPONSIBLE_STAFF_STATUSES],
    ]);
  });
});
