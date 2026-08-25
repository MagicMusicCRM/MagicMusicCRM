import { toLeadDto, toNumericStat } from "./lead-model";

describe("lead model", () => {
  it("maps canonical lead fields and safe numeric statistics", () => {
    const result = toLeadDto({
      id: "lead-a",
      status_id: null,
      status_name: null,
      first_name: "Анна",
      last_name: null,
      phone: "+79990000000",
      email: "anna@example.com",
      source: "Сайт",
      notes: null,
      assigned_to: null,
      custom_data: {},
      created_by: "manager-a",
      created_at: "2026-08-25T10:00:00.000Z",
      updated_at: "2026-08-25T10:00:00.000Z",
      blacklisted: true,
      blacklist_reason: "spam",
    });

    expect(result).toEqual(
      expect.objectContaining({
        id: "lead-a",
        email: "anna@example.com",
        blacklisted: true,
        blacklistReason: "spam",
      }),
    );
    expect(toNumericStat("12")).toBe(12);
    expect(toNumericStat("not-a-number")).toBe(0);
  });
});
