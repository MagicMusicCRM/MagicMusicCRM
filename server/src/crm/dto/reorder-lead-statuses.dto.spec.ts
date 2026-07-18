import { validate } from "class-validator";
import { ReorderLeadStatusesDto } from "./reorder-lead-statuses.dto";

describe("ReorderLeadStatusesDto", () => {
  it("accepts real UUID columns together with the synthetic unassigned column", async () => {
    const dto = Object.assign(new ReorderLeadStatusesDto(), {
      statusIds: [
        "e222efc4-8566-4d7e-9b86-da83c625a4d0",
        "unassigned",
        "88ec9e28-7efb-4fcf-bf0e-e057b562a439",
      ],
    });
    await expect(validate(dto)).resolves.toHaveLength(0);
  });

  it("rejects arbitrary non-UUID column ids", async () => {
    const dto = Object.assign(new ReorderLeadStatusesDto(), {
      statusIds: ["status-a"],
    });
    const errors = await validate(dto);
    expect(errors.some((error) => error.property === "statusIds")).toBe(true);
  });
});
