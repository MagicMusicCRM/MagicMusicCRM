import { ConflictException } from "@nestjs/common";
import { LeadCommandService } from "./lead-command.service";

describe("LeadCommandService", () => {
  it("keeps direct deletion blocked after authorization", () => {
    const actor = { userId: "manager-a", role: "manager" as const };
    const policy = { assertCanWriteCrm: jest.fn() };
    const service = new LeadCommandService(
      {} as never,
      {} as never,
      policy as never,
      {} as never,
      {} as never,
    );

    expect(() => service.delete(actor, "lead-a")).toThrow(ConflictException);
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
  });

  it("records a merged safe semantic change payload before audit persistence", async () => {
    const actor = { userId: "manager-a", role: "manager" as const };
    const oldUuid = "11111111-1111-4111-8111-111111111111";
    const newUuid = "22222222-2222-4222-8222-222222222222";
    const contactPhone = "+79991234567";
    const before = {
      id: "lead-a",
      version: 1,
      status_id: null,
      status_name: null,
      first_name: "Анна",
      last_name: "Иванова",
      phone: "+70000000000",
      email: "old@example.com",
      source: "Сайт",
      notes: null,
      assigned_to: oldUuid,
      custom_data: { level: "PIANO", contactPersons: [] },
      created_by: "manager-a",
      created_at: "2026-08-01T00:00:00.000Z",
      updated_at: "2026-08-01T00:00:00.000Z",
      branch_id: null,
    };
    const lead = {
      ...before,
      version: 2,
      phone: "+71111111111",
      email: "new@example.com",
      assigned_to: newUuid,
      custom_data: {
        level: "DRUMS",
        contactPersons: [{ name: "Анна", phone: contactPhone }],
      },
      updated_at: "2026-08-31T00:00:00.000Z",
    };
    const audit = { record: jest.fn(async () => undefined) };
    const policy = { assertCanWriteCrm: jest.fn() };
    const realtime = { emitCrmChanged: jest.fn() };
    const writes = {
      update: jest.fn(async () => ({ before, lead, branchId: null })),
    };
    const service = new LeadCommandService(
      {} as never,
      audit as never,
      policy as never,
      realtime as never,
      writes as never,
    );

    await service.update(actor, "lead-a", { assignedTo: newUuid });

    const metadata = (audit.record as jest.Mock).mock.calls[0]?.[0]?.metadata;
    expect(metadata).toEqual({
      changes: [
        {
          field: "phone",
          from: "+70000000000",
          to: "+71111111111",
          label: "Телефон",
          valueType: "text",
          displayMode: "values",
        },
        {
          field: "email",
          from: null,
          to: null,
          label: "Электронная почта",
          valueType: "text",
          displayMode: "values",
        },
        {
          field: "assigned_to",
          from: null,
          to: null,
          label: "Ответственный",
          valueType: "reference",
          displayMode: "changed_only",
        },
        {
          field: "custom_data.contactPersons",
          from: 0,
          to: 1,
          label: "Контактные лица",
          valueType: "contact_list",
          displayMode: "count",
        },
        {
          field: "custom_data.level",
          from: "PIANO",
          to: "DRUMS",
          label: "Уровень",
          valueType: "text",
          displayMode: "values",
        },
      ],
      customFieldDefinitionIds: [],
    });
    const storedChanges = JSON.stringify(metadata?.changes);
    expect(storedChanges).not.toContain(oldUuid);
    expect(storedChanges).not.toContain(newUuid);
    expect(storedChanges).not.toContain(contactPhone);
    expect(storedChanges).not.toContain("old@example.com");
    expect(storedChanges).not.toContain("new@example.com");
  });
});
