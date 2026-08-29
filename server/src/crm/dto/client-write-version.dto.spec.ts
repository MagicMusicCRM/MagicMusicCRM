import "reflect-metadata";
import { plainToInstance } from "class-transformer";
import { validate } from "class-validator";
import { UpdateStudentDto } from "./update-student.dto";
import { UpdateLeadDto } from "./upsert-lead.dto";

describe("client write version DTOs", () => {
  it.each([
    ["lead", UpdateLeadDto],
    ["student", UpdateStudentDto],
  ] as const)("accepts legacy omission but validates explicit expectedVersion for PATCH %s", async (_, Dto) => {
    const missing = await validate(plainToInstance(Dto, {}));
    const zero = await validate(plainToInstance(Dto, { expectedVersion: 0 }));
    const valid = await validate(plainToInstance(Dto, { expectedVersion: 3 }));

    expect(missing.map((error) => error.property)).not.toContain("expectedVersion");
    expect(zero.map((error) => error.property)).toContain("expectedVersion");
    expect(valid.map((error) => error.property)).not.toContain("expectedVersion");
  });
});
