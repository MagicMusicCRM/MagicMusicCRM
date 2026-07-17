// server/src/migration/hollihop-mappers.spec.ts
import { disciplineEntries, contactEntries, primaryBranchId } from "./hollihop-mappers";

describe("disciplineEntries", () => {
  it("returns distinct names, first is primary, order preserved", () => {
    expect(
      disciplineEntries([{ Discipline: "Вокал" }, { Discipline: "Гитара" }, { Discipline: "вокал" }]),
    ).toEqual([
      { name: "Вокал", isPrimary: true },
      { name: "Гитара", isPrimary: false },
    ]);
  });
  it("accepts plain strings and skips empties", () => {
    expect(disciplineEntries(["Барабаны", "", "  "])).toEqual([{ name: "Барабаны", isPrimary: true }]);
  });
  it("returns [] for null/garbage", () => {
    expect(disciplineEntries(null)).toEqual([]);
    expect(disciplineEntries(42)).toEqual([]);
  });
});

describe("contactEntries", () => {
  const norm = (p: string | null | undefined) =>
    p && p.replace(/\D/g, "").length >= 10 ? `+7${p.replace(/\D/g, "").slice(-10)}` : null;
  it("maps agents with a normalizable phone or a name", () => {
    expect(
      contactEntries(
        [
          { Mobile: "8 909 123 45 67", FirstName: "Иван", LastName: "Иванов", Type: "parent" },
          { FirstName: "Без", LastName: "Телефона" },
          { Mobile: "junk" },
        ],
        norm,
      ),
    ).toEqual([
      { phoneNormalized: "+79091234567", name: "Иван Иванов", role: "parent" },
      { phoneNormalized: null, name: "Без Телефона", role: null },
    ]);
  });
  it("returns [] for null/garbage", () => {
    expect(contactEntries(null, norm)).toEqual([]);
  });
  it("uses Phone/Name/Role fallback keys and skips agents with neither phone nor name", () => {
    expect(
      contactEntries(
        [
          { Phone: "+7 916 000 11 22", Name: "Анна Петрова", Role: "guardian" },
          { Phone: "junk" }, // no phone, no name -> skipped
          {}, // empty -> skipped
        ],
        norm,
      ),
    ).toEqual([{ phoneNormalized: "+79160001122", name: "Анна Петрова", role: "guardian" }]);
  });
});

describe("primaryBranchId", () => {
  it("returns the first id or null", () => {
    expect(primaryBranchId(["b1", "b2"])).toBe("b1");
    expect(primaryBranchId([])).toBeNull();
    expect(primaryBranchId(null)).toBeNull();
  });
  it("returns null for undefined", () => {
    expect(primaryBranchId(undefined)).toBeNull();
  });
});
