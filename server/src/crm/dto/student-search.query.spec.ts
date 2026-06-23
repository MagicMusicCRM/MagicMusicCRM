import "reflect-metadata";
import { plainToInstance } from "class-transformer";
import { validate } from "class-validator";
import { StudentSearchQuery } from "./student-search.query";

describe("StudentSearchQuery limit contract", () => {
  it("accepts limit up to 500 (board pulls a whole branch)", async () => {
    const dto = plainToInstance(StudentSearchQuery, { limit: "500" });
    const errors = await validate(dto);
    expect(errors).toHaveLength(0);
  });

  it("rejects limit above 500", async () => {
    const dto = plainToInstance(StudentSearchQuery, { limit: "501" });
    const errors = await validate(dto);
    expect(errors.some((e) => e.property === "limit")).toBe(true);
  });
});
