import { NotFoundException } from "@nestjs/common";
import { LeadCardService } from "./lead-card.service";

describe("LeadCardService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  it("authorizes before reading and reports a missing lead", async () => {
    const query = jest.fn().mockResolvedValue({ rows: [] });
    const policy = { assertCanWriteCrm: jest.fn() };
    const service = new LeadCardService(
      { query } as never,
      policy as never,
      {} as never,
      {} as never,
      {} as never,
      {} as never,
    );

    await expect(service.get(actor, "lead-a")).rejects.toBeInstanceOf(
      NotFoundException,
    );
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query).toHaveBeenCalledTimes(1);
  });
});
