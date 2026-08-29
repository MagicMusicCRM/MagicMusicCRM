import { LeadWriteRepository } from "./lead-write.repository";

describe("LeadWriteRepository", () => {
  it("creates the lead inside one transaction without a phantom transition", async () => {
    const inserted = {
      id: "lead-a",
      status_id: null,
      status_name: null,
      first_name: "Анна",
      last_name: null,
      phone: null,
      email: null,
      source: null,
      notes: null,
      assigned_to: null,
      custom_data: {},
      created_by: "manager-a",
      created_at: "2026-08-25T10:00:00.000Z",
      updated_at: "2026-08-25T10:00:00.000Z",
    };
    const client = {
      query: jest.fn().mockResolvedValue({ rows: [inserted] }),
    };
    const database = {
      query: jest.fn(),
      transaction: jest.fn(
        async (work: (value: typeof client) => Promise<unknown>) => work(client),
      ),
    };
    const pipelines = { assertLeadTransition: jest.fn() };
    const repository = new LeadWriteRepository(
      database as never,
      pipelines as never,
    );

    await expect(
      repository.create(
        { userId: "manager-a", role: "manager" },
        { firstName: "Анна" },
      ),
    ).resolves.toEqual({ lead: inserted, branchId: null });
    expect(database.transaction).toHaveBeenCalledTimes(1);
    expect(pipelines.assertLeadTransition).not.toHaveBeenCalled();
    expect(client.query.mock.calls[0]?.[0]).toContain("insert into app.leads");
  });

  it("rejects a stale autosave before changing the lead", async () => {
    const locked = {
      id: "lead-a",
      version: 3,
      status_id: null,
      status_name: null,
      first_name: "Анна",
      last_name: null,
      phone: null,
      email: null,
      source: null,
      source_id: null,
      notes: null,
      assigned_to: null,
      custom_data: {},
      created_by: "manager-a",
      created_at: "2026-08-25T10:00:00.000Z",
      updated_at: "2026-08-25T10:00:00.000Z",
      branch_id: null,
    };
    const client = {
      query: jest.fn().mockResolvedValue({ rows: [locked] }),
    };
    const database = {
      query: jest.fn(),
      transaction: jest.fn(
        async (work: (value: typeof client) => Promise<unknown>) => work(client),
      ),
    };
    const repository = new LeadWriteRepository(database as never, {
      assertLeadTransition: jest.fn(),
    } as never);

    await expect(
      repository.update(
        { userId: "manager-a", role: "manager" },
        "lead-a",
        { firstName: "Мария", expectedVersion: 2 },
      ),
    ).rejects.toMatchObject({
      response: expect.objectContaining({
        code: "CLIENT_VERSION_CONFLICT",
        entityType: "lead",
        expectedVersion: 2,
        currentVersion: 3,
      }),
    });
    expect(client.query).toHaveBeenCalledTimes(1);
    expect(String(client.query.mock.calls[0]?.[0])).toContain("for update");
  });

  it("keeps released clients compatible when expectedVersion is omitted", async () => {
    const locked = {
      id: "lead-a",
      version: 3,
      status_id: null,
      status_name: null,
      first_name: "Анна",
      last_name: null,
      phone: null,
      email: null,
      source: null,
      source_id: null,
      notes: null,
      assigned_to: null,
      custom_data: {},
      created_by: "manager-a",
      created_at: "2026-08-25T10:00:00.000Z",
      updated_at: "2026-08-25T10:00:00.000Z",
      branch_id: null,
    };
    const updated = { ...locked, version: 4, first_name: "Мария" };
    const client = {
      query: jest
        .fn()
        .mockResolvedValueOnce({ rows: [locked] })
        .mockResolvedValueOnce({ rows: [updated] }),
    };
    const database = {
      query: jest.fn(),
      transaction: jest.fn(
        async (work: (value: typeof client) => Promise<unknown>) => work(client),
      ),
    };
    const repository = new LeadWriteRepository(database as never, {
      assertLeadTransition: jest.fn(),
    } as never);

    await expect(
      repository.update(
        { userId: "manager-a", role: "manager" },
        "lead-a",
        { firstName: "Мария" },
      ),
    ).resolves.toMatchObject({ lead: updated });
    expect(String(client.query.mock.calls[1]?.[0])).toContain(
      "version = version + 1",
    );
  });
});
