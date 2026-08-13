import { plainToInstance } from "class-transformer";
import { validate } from "class-validator";
import { LinkUserToClientDto } from "./link-user-to-client.dto";

describe("LinkUserToClientDto", () => {
  it("accepts a UUID user id", async () => {
    const dto = plainToInstance(LinkUserToClientDto, {
      userId: "11111111-1111-4111-8111-111111111111",
    });

    await expect(validate(dto)).resolves.toHaveLength(0);
  });

  it("rejects malformed user ids before they reach PostgreSQL", async () => {
    const dto = plainToInstance(LinkUserToClientDto, { userId: "not-a-uuid" });

    const errors = await validate(dto);
    expect(errors).toEqual([
      expect.objectContaining({
        property: "userId",
        constraints: expect.objectContaining({ isUuid: expect.any(String) }),
      }),
    ]);
  });
});
