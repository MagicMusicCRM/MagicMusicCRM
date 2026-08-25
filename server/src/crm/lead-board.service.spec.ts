import { LeadBoardService } from "./lead-board.service";

describe("LeadBoardService", () => {
  it("authorizes before loading pipeline or board data", async () => {
    const actor = { userId: "teacher-a", role: "teacher" as const };
    const denied = new Error("forbidden");
    const policy = {
      assertCanWriteCrm: jest.fn(() => {
        throw denied;
      }),
    };
    const database = { query: jest.fn() };
    const pipelines = { getEffective: jest.fn() };
    const service = new LeadBoardService(
      database as never,
      policy as never,
      pipelines as never,
    );

    await expect(service.list(actor, {})).rejects.toBe(denied);
    expect(database.query).not.toHaveBeenCalled();
    expect(pipelines.getEffective).not.toHaveBeenCalled();
  });
});
