import { BadRequestException } from "@nestjs/common";
import { BlacklistService } from "./blacklist.service";
import { CrmStudentsController } from "./crm-students.controller";
import { CrmService } from "./crm.service";
import { FinanceService } from "./finance.service";
import { SubscriptionsService } from "./subscriptions.service";

describe("CrmStudentsController", () => {
  it("rejects direct lead conversion and points callers to subscription issuance", () => {
    const crm = { createStudent: jest.fn() };
    const controller = new CrmStudentsController(
      crm as unknown as CrmService,
      {} as FinanceService,
      {} as SubscriptionsService,
      {} as BlacklistService,
    );

    expect(() =>
      controller.createStudent(
        { userId: "admin-a", role: "admin" },
        { firstName: "Анна", leadId: "lead-a" },
      ),
    ).toThrow(BadRequestException);
    expect(crm.createStudent).not.toHaveBeenCalled();
  });

  it("keeps ordinary student creation on the existing service contract", () => {
    const crm = { createStudent: jest.fn().mockReturnValue({ id: "student-a" }) };
    const controller = new CrmStudentsController(
      crm as unknown as CrmService,
      {} as FinanceService,
      {} as SubscriptionsService,
      {} as BlacklistService,
    );
    const actor = { userId: "admin-a", role: "admin" as const };
    const dto = { firstName: "Анна" };

    expect(controller.createStudent(actor, dto)).toEqual({ id: "student-a" });
    expect(crm.createStudent).toHaveBeenCalledWith(actor, dto);
  });
});
