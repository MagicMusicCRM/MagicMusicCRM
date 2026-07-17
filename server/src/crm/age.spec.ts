import { ageAt, parseBirthday, resolveAge } from "./age";

describe("resolveAge", () => {
  const NOW = new Date("2026-07-17T12:00:00.000Z");

  it("computes the age from the birthday", () => {
    expect(resolveAge({ birthday: "1998-04-12" }, NOW)).toEqual({
      years: 28,
      months: 3,
      source: "birthday",
    });
  });

  it("takes a hand-typed age when the birthday is unknown", () => {
    // ✔ «Можно просто вписать его возраст».
    expect(resolveAge({ age: 7 }, NOW)).toEqual({
      years: 7,
      months: null,
      source: "manual",
    });
  });

  it("lets the birthday win over a hand-typed age", () => {
    // Возраст, вписанный руками, — снимок, который протухает молча. Дата
    // рождения не устаревает, поэтому при наличии обоих считаем по ней:
    // ребёнку, записанному семилетним в прошлом году, сейчас восемь.
    expect(resolveAge({ birthday: "2018-01-01", age: 7 }, NOW)).toEqual({
      years: 8,
      months: 6,
      source: "birthday",
    });
  });

  it("reports nothing when neither field is filled", () => {
    expect(resolveAge({}, NOW)).toEqual({
      years: null,
      months: null,
      source: null,
    });
    expect(resolveAge(null, NOW).source).toBeNull();
  });

  describe("ageing over the calendar", () => {
    it("does not count the birthday until the day arrives", () => {
      const eve = resolveAge({ birthday: "2000-07-18" }, NOW);
      expect(eve.years).toBe(25);
      const day = resolveAge(
        { birthday: "2000-07-17" },
        new Date("2026-07-17T12:00:00.000Z"),
      );
      expect(day.years).toBe(26);
    });

    it("keeps a leap-day birthday on the calendar, not on 365.25 days", () => {
      // 2000-02-29 → в 2026 году 29 февраля нет. К 1 марта человеку 26.
      expect(
        resolveAge({ birthday: "2000-02-29" }, new Date("2026-03-01T00:00:00Z"))
          .years,
      ).toBe(26);
      expect(
        resolveAge({ birthday: "2000-02-29" }, new Date("2026-02-28T00:00:00Z"))
          .years,
      ).toBe(25);
    });

    it("answers in months for a baby, because «0 лет» is not an answer", () => {
      expect(resolveAge({ birthday: "2026-03-17" }, NOW)).toEqual({
        years: 0,
        months: 4,
        source: "birthday",
      });
    });
  });

  describe("junk in custom_data", () => {
    it("reads the HolliHop date format as well as the picker's ISO", () => {
      // Импорт клал «дд.мм.гггг», пикер кладёт ISO — в базе лежат оба.
      expect(resolveAge({ birthday: "12.04.1998" }, NOW).years).toBe(28);
    });

    it("rejects a date that does not exist", () => {
      expect(parseBirthday("31.02.1998")).toBeNull();
      expect(resolveAge({ birthday: "31.02.1998" }, NOW).source).toBeNull();
    });

    it("ignores a birthday from the future instead of showing a negative age", () => {
      expect(resolveAge({ birthday: "2030-01-01" }, NOW).source).toBeNull();
    });

    it("falls back to the manual age when the birthday is unparseable", () => {
      expect(resolveAge({ birthday: "не указано", age: 9 }, NOW)).toEqual({
        years: 9,
        months: null,
        source: "manual",
      });
    });

    it("ignores a manual age that cannot be a human age", () => {
      expect(resolveAge({ age: -1 }, NOW).source).toBeNull();
      expect(resolveAge({ age: 500 }, NOW).source).toBeNull();
      expect(resolveAge({ age: "" }, NOW).source).toBeNull();
      expect(resolveAge({ age: "восемь" }, NOW).source).toBeNull();
    });

    it("accepts a manual age typed as a string, because a text field sends one", () => {
      expect(resolveAge({ age: "7" }, NOW).years).toBe(7);
      expect(resolveAge({ age: " 7 " }, NOW).years).toBe(7);
    });
  });

  describe("ageAt", () => {
    it("borrows a month when the day has not come round yet", () => {
      expect(
        ageAt(new Date("2000-01-31T00:00:00Z"), new Date("2000-03-01T00:00:00Z")),
      ).toEqual({ years: 0, months: 1 });
    });
  });
});
