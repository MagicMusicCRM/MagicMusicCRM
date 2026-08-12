import "reflect-metadata";
import { plainToInstance } from "class-transformer";
import { validate } from "class-validator";
import { LeadBoardQuery } from "./lead-board.query";

describe("LeadBoardQuery", () => {
  const statusId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  const cursor =
    "2026-07-18T10:11:12.123456Z|11111111-1111-4111-8111-111111111111";

  it("accepts a cursor scoped to one UUID status partition", async () => {
    const query = plainToInstance(LeadBoardQuery, { statusId, cursor });
    await expect(validate(query)).resolves.toHaveLength(0);
  });

  it("accepts explicit unassigned=true and transforms the query string", async () => {
    const query = plainToInstance(LeadBoardQuery, {
      unassigned: "true",
      cursor,
    });
    await expect(validate(query)).resolves.toHaveLength(0);
    expect(query.unassigned).toBe(true);
  });

  it("accepts the deprecated unscoped cursor for build-143 compatibility", async () => {
    const query = plainToInstance(LeadBoardQuery, { cursor });
    await expect(validate(query)).resolves.toHaveLength(0);
  });

  it("accepts the two deterministic lead-card sort orders", async () => {
    await expect(
      validate(plainToInstance(LeadBoardQuery, { sort: "newest" })),
    ).resolves.toHaveLength(0);
    await expect(
      validate(plainToInstance(LeadBoardQuery, { sort: "oldest" })),
    ).resolves.toHaveLength(0);
    const errors = await validate(
      plainToInstance(LeadBoardQuery, { sort: "name" }),
    );
    expect(errors.some((error) => error.property === "sort")).toBe(true);
  });

  it("rejects statusId together with unassigned=true", async () => {
    const errors = await validate(
      plainToInstance(LeadBoardQuery, { statusId, unassigned: "true" }),
    );
    expect(errors.some((error) => error.property === "statusId")).toBe(true);
  });

  it("rejects malformed cursors and non-boolean unassigned values", async () => {
    const malformed = await validate(
      plainToInstance(LeadBoardQuery, {
        unassigned: "yes",
        cursor: "2026-07-18T10:11:12.123Z|not-a-uuid",
      }),
    );
    expect(malformed.map((error) => error.property)).toEqual(
      expect.arrayContaining(["unassigned", "cursor"]),
    );
  });
});
