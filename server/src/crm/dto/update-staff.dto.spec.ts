import { validate } from "class-validator";
import { UpdateStaffDto } from "./update-staff.dto";

describe("UpdateStaffDto", () => {
  it("rejects role changes outside Settings -> Access", async () => {
    const dto = Object.assign(new UpdateStaffDto(), { role: "manager" });
    const errors = await validate(dto, {
      whitelist: true,
      forbidNonWhitelisted: true,
    });
    expect(
      errors.some(
        (error) =>
          error.property === "role" &&
          error.constraints?.whitelistValidation !== undefined,
      ),
    ).toBe(true);
  });
});
