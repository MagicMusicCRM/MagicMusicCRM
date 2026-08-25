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
});
