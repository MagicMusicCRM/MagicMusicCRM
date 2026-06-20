// server/src/crm/phone.util.spec.ts
import { normalizePhoneRu, normalizedPhoneExpr } from "./phone.util";

describe("normalizePhoneRu", () => {
  it("canonicalizes valid RU numbers to +7XXXXXXXXXX", () => {
    expect(normalizePhoneRu("+7 (909) 123-45-67").canonical).toBe("+79091234567");
    expect(normalizePhoneRu("89091234567").canonical).toBe("+79091234567");
    expect(normalizePhoneRu("9091234567").canonical).toBe("+79091234567");
    expect(normalizePhoneRu("+7 909 123 45 67").reason).toBe("ok");
  });

  it("routes empty / short / non-RU to null with a reason", () => {
    expect(normalizePhoneRu("")).toEqual({ canonical: null, reason: "empty" });
    expect(normalizePhoneRu(null)).toEqual({ canonical: null, reason: "empty" });
    expect(normalizePhoneRu("12345")).toEqual({ canonical: null, reason: "too_short" });
    // +1 202 555 0143 -> 11 digits starting with 1 -> not a RU number
    expect(normalizePhoneRu("+1 202 555 0143")).toEqual({ canonical: null, reason: "non_ru" });
  });

  it("emits a SQL expression that references the column", () => {
    const sql = normalizedPhoneExpr("l.phone");
    expect(sql).toContain("l.phone");
    expect(sql).toContain("'+7'");
  });
});
