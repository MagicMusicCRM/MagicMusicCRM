import { LeadDirectoryService } from "./lead-directory.service";

describe("LeadDirectoryService", () => {
  it("maps applications after operational-data authorization", async () => {
    const actor = { userId: "manager-a", role: "manager" as const };
    const query = jest.fn().mockResolvedValue({
      rows: [
        {
          id: "application-a",
          applied_at: "2026-08-25T10:00:00.000Z",
          channel: "site",
          office: null,
          discipline: "Вокал",
          status: "new",
          utm: { source: "search" },
        },
      ],
    });
    const policy = { assertCanReadOperationalData: jest.fn() };
    const service = new LeadDirectoryService(
      { query } as never,
      policy as never,
    );

    await expect(service.listApplications(actor, "lead-a")).resolves.toEqual({
      items: [
        expect.objectContaining({
          id: "application-a",
          appliedAt: "2026-08-25T10:00:00.000Z",
          discipline: "Вокал",
        }),
      ],
    });
    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
  });
});
