import { validate } from "class-validator";
import { UpdateStaffDto } from "./update-staff.dto";

describe("UpdateStaffDto", () => {
  it.each(["Ответственный", "director"])(
    "accepts an unchanged imported/current display role: %s",
    async (role) => {
      const dto = Object.assign(new UpdateStaffDto(), { role });
      await expect(validate(dto)).resolves.toHaveLength(0);
    },
  );

  it("still validates the display role as a bounded string", async () => {
    const dto = Object.assign(new UpdateStaffDto(), { role: "x".repeat(81) });
    const errors = await validate(dto);
    expect(errors.some((error) => error.property === "role")).toBe(true);
  });
});
