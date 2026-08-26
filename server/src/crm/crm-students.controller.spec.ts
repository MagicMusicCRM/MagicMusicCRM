import { BlacklistService } from "./blacklist.service";
import { CrmStudentsController } from "./crm-students.controller";
import { CrmService } from "./crm.service";
import { FinanceService } from "./finance.service";
import { SubscriptionsService } from "./subscriptions.service";
import { ClientCardReadService } from "./clients/client-card-read.service";
import { ClientWriteValidator } from "./clients/client-write.validator";
import { ActualPaymentService } from "./commerce/actual-payment.service";

describe("CrmStudentsController", () => {
  it("delegates student boundary methods without copying request values", async () => {
    const response = { id: "response-a" };
    const crm = {
      getMySummary: jest.fn().mockResolvedValue(response),
      listStudents: jest.fn().mockResolvedValue(response),
      searchStudents: jest.fn().mockResolvedValue(response),
      getStudent: jest.fn().mockResolvedValue(response),
      listStudentGroups: jest.fn().mockResolvedValue(response),
      inviteStudent: jest.fn().mockResolvedValue(response),
      deleteStudent: jest.fn().mockResolvedValue(response),
      returnStudentToLead: jest.fn().mockResolvedValue(response),
    };
    const controller = new CrmStudentsController(
      crm as unknown as CrmService,
      {} as FinanceService,
      {} as SubscriptionsService,
      {} as BlacklistService,
      {} as ClientCardReadService,
      {} as ClientWriteValidator,
      {} as ActualPaymentService,
    );
    const actor = { userId: "admin-a", role: "admin" as const };
    const id = "student-a";
    const listQuery = { limit: 10 };
    const searchQuery = { q: "Алина", limit: 10 };

    const cases = [
      {
        invoke: () => controller.getMe(actor),
        method: crm.getMySummary,
        expected: [actor],
      },
      {
        invoke: () => controller.listStudents(actor, listQuery),
        method: crm.listStudents,
        expected: [actor, listQuery],
      },
      {
        invoke: () => controller.searchStudents(actor, searchQuery),
        method: crm.searchStudents,
        expected: [actor, searchQuery],
      },
      {
        invoke: () => controller.getStudent(actor, id),
        method: crm.getStudent,
        expected: [actor, id],
      },
      {
        invoke: () => controller.listStudentGroups(actor, id, listQuery),
        method: crm.listStudentGroups,
        expected: [actor, id, listQuery],
      },
      {
        invoke: () => controller.inviteStudent(actor, id),
        method: crm.inviteStudent,
        expected: [actor, id],
      },
      {
        invoke: () => controller.deleteStudent(actor, id),
        method: crm.deleteStudent,
        expected: [actor, id],
      },
      {
        invoke: () => controller.returnStudentToLead(actor, id),
        method: crm.returnStudentToLead,
        expected: [actor, id],
      },
    ];

    for (const testCase of cases) {
      await expect(testCase.invoke()).resolves.toBe(response);
      const received = testCase.method.mock.calls[0];
      expect(received).toHaveLength(testCase.expected.length);
      testCase.expected.forEach((argument, index) => {
        expect(received?.[index]).toBe(argument);
      });
    }
  });

  it("validates ordinary student creation before delegating", async () => {
    const crm = {
      createStudent: jest.fn().mockResolvedValue({ id: "student-a" }),
    };
    const clientWrites = {
      validateStudentCreate: jest.fn().mockResolvedValue({
        firstName: "Анна",
        lastName: "Иванова",
        phone: "+79990000000",
        branchId: "branch-a",
        status: "active",
        customFields: [],
        warnings: [],
      }),
    };
    const controller = new CrmStudentsController(
      crm as unknown as CrmService,
      {} as FinanceService,
      {} as SubscriptionsService,
      {} as BlacklistService,
      {} as ClientCardReadService,
      clientWrites as unknown as ClientWriteValidator,
      {} as ActualPaymentService,
    );
    const actor = { userId: "admin-a", role: "admin" as const };
    const dto = {
      firstName: "Анна",
      lastName: "Иванова",
      phone: "+79990000000",
      branchId: "branch-a",
      status: "active",
    };

    await expect(controller.createStudent(actor, dto)).resolves.toEqual({
      id: "student-a",
    });
    expect(clientWrites.validateStudentCreate).toHaveBeenCalledWith(dto);
    expect(crm.createStudent).toHaveBeenCalledWith(
      actor,
      {
        firstName: "Анна",
        lastName: "Иванова",
        phone: "+79990000000",
        status: "active",
        customDataPatch: { branchId: "branch-a" },
      },
      expect.objectContaining({ branchId: "branch-a" }),
    );
  });

  it("validates typed fields before an existing Student update", async () => {
    const crm = {
      updateStudent: jest.fn().mockResolvedValue({ id: "student-a" }),
    };
    const validated = { values: [{ definitionId: "field-a" }], warnings: [] };
    const clientWrites = {
      validateCustomFields: jest.fn().mockResolvedValue(validated),
    };
    const controller = new CrmStudentsController(
      crm as unknown as CrmService,
      {} as FinanceService,
      {} as SubscriptionsService,
      {} as BlacklistService,
      {} as ClientCardReadService,
      clientWrites as unknown as ClientWriteValidator,
      {} as ActualPaymentService,
    );
    const actor = { userId: "admin-a", role: "admin" as const };
    const dto = {
      firstName: "Анна",
      customFields: [{ definitionId: "field-a", value: 12 }],
    };

    await controller.updateStudent(actor, "student-a", dto);

    expect(clientWrites.validateCustomFields).toHaveBeenCalledWith(
      "student",
      dto.customFields,
    );
    expect(crm.updateStudent).toHaveBeenCalledWith(
      actor,
      "student-a",
      dto,
      validated,
    );
  });
});
