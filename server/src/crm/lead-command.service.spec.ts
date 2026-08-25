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
});
