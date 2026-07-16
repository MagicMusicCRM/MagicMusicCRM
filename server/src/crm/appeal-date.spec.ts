import {
  isHolliHopRecord,
  mergeCustomData,
  resolveAppealDate,
} from "./appeal-date";

describe("resolveAppealDate", () => {
  const CREATED = "2026-07-16T10:00:00.000Z";

  it("uses the app's creation moment when the record was born here", () => {
    // ✔ «Если лид пришёл первый раз именно из приложения — проставляем дату,
    // когда он стал лидом через приложение».
    expect(resolveAppealDate({}, CREATED)).toEqual({
      value: CREATED,
      source: "app",
    });
  });

  it("prefers the HolliHop date over the app's creation moment", () => {
    // ✔ «При дедупе через телефон и тд должны оставаться данные только из
    // HolliHop» — там клиент обратился раньше, и это настоящая дата.
    expect(
      resolveAppealDate({ addressDate: "2023-03-01T00:00:00.000Z" }, CREATED),
    ).toEqual({ value: "2023-03-01T00:00:00.000Z", source: "hollihop" });
  });

  it("lets a deliberate value win over both", () => {
    expect(
      resolveAppealDate(
        {
          appealAt: "2024-01-01T00:00:00.000Z",
          addressDate: "2023-03-01T00:00:00.000Z",
        },
        CREATED,
      ),
    ).toEqual({ value: "2024-01-01T00:00:00.000Z", source: "manual" });
  });

  it("reads the key the import actually wrote, not just the declared one", () => {
    // The settings schema declares `appealAt` while the import wrote
    // `addressDate` — so the declared field was dead for every imported lead.
    expect(resolveAppealDate({ addressDate: "2023-03-01" }, null).source).toBe(
      "hollihop",
    );
  });

  it("ignores junk instead of producing an epoch date", () => {
    expect(resolveAppealDate({ addressDate: "не указано" }, CREATED)).toEqual({
      value: CREATED,
      source: "app",
    });
    expect(resolveAppealDate({ appealAt: "" }, CREATED).source).toBe("app");
  });

  it("returns null when there is nothing to go on", () => {
    expect(resolveAppealDate(null, null)).toEqual({ value: null, source: "app" });
  });
});

describe("isHolliHopRecord", () => {
  it("recognises an imported record by its marker", () => {
    expect(isHolliHopRecord({ hollihopId: "123" })).toBe(true);
    expect(isHolliHopRecord({ hollihopClientId: "456" })).toBe(true);
  });

  it("does not mistake an app-born record for an imported one", () => {
    expect(isHolliHopRecord({ level: "A1" })).toBe(false);
    expect(isHolliHopRecord(null)).toBe(false);
  });
});

describe("mergeCustomData", () => {
  it("keeps the HolliHop values when merging an import into an app record", () => {
    // The whole point: a phone-dedup must not let the app's guess overwrite the
    // real data from HolliHop.
    const winner = { appealAt: undefined, level: "не указан", source: "сайт" };
    const loser = {
      hollihopId: "42",
      level: "A2",
      source: "Яндекс",
      addressDate: "2023-03-01",
    };

    expect(mergeCustomData(winner, loser)).toEqual({
      hollihopId: "42",
      level: "A2",
      source: "Яндекс",
      addressDate: "2023-03-01",
      appealAt: undefined,
    });
  });

  it("does not let an app record overwrite an imported winner", () => {
    const winner = { hollihopId: "42", level: "A2" };
    const loser = { level: "не указан", note: "из формы" };

    expect(mergeCustomData(winner, loser)).toEqual({
      hollihopId: "42",
      level: "A2",
      // Keys the winner lacks are still worth keeping — merging should not
      // throw data away.
      note: "из формы",
    });
  });

  it("fills gaps in the winner from the loser regardless of origin", () => {
    expect(mergeCustomData({ level: "A1" }, { gender: "f" })).toEqual({
      level: "A1",
      gender: "f",
    });
  });

  it("never copies a null over a real value", () => {
    expect(mergeCustomData({ level: "A1" }, { level: null })).toEqual({
      level: "A1",
    });
  });

  it("survives both sides being empty", () => {
    expect(mergeCustomData(null, null)).toEqual({});
  });
});
