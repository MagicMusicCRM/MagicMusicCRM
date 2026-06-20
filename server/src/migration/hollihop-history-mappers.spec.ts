import { appendMoscowOffset, historyEntryFromRow } from "./hollihop-history-mappers";

describe("appendMoscowOffset", () => {
  it("appends +03:00 to a timezone-naive datetime", () => {
    expect(appendMoscowOffset("2025-03-14T11:20:00")).toBe("2025-03-14T11:20:00+03:00");
    expect(appendMoscowOffset("2025-03-14 11:20:00")).toBe("2025-03-14 11:20:00+03:00");
  });
  it("leaves an already-offset / UTC datetime untouched", () => {
    expect(appendMoscowOffset("2025-03-14T11:20:00Z")).toBe("2025-03-14T11:20:00Z");
    expect(appendMoscowOffset("2025-03-14T11:20:00+05:00")).toBe("2025-03-14T11:20:00+05:00");
  });
  it("passes through undefined", () => {
    expect(appendMoscowOffset(undefined)).toBeUndefined();
  });
});

describe("historyEntryFromRow", () => {
  it("extracts the four fields", () => {
    expect(
      historyEntryFromRow({
        LeadId: 12345,
        DateTime: "2025-03-14T11:20:00",
        AfterId: 7,
        AfterName: "Пробное назначено",
      }),
    ).toEqual({
      leadIdRaw: "12345",
      afterIdRaw: "7",
      afterName: "Пробное назначено",
      dateTimeRaw: "2025-03-14T11:20:00",
    });
  });
  it("keeps the row when AfterId/AfterName are absent (timestamp still useful)", () => {
    expect(
      historyEntryFromRow({ LeadId: "9", DateTime: "2025-01-02T00:00:00" }),
    ).toEqual({
      leadIdRaw: "9",
      afterIdRaw: null,
      afterName: null,
      dateTimeRaw: "2025-01-02T00:00:00",
    });
  });
  it("returns null when LeadId is missing", () => {
    expect(historyEntryFromRow({ DateTime: "2025-01-02T00:00:00", AfterId: 3 })).toBeNull();
  });
  it("returns null when DateTime is missing", () => {
    expect(historyEntryFromRow({ LeadId: 5, AfterId: 3 })).toBeNull();
  });
});
