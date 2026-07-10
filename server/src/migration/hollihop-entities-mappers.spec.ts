import {
  hhDateTimeToIso,
  durationFromTimes,
  studyRequestFromRow,
  edUnitLeadFromRow,
  priceFromRow,
  communicationFromRow,
} from "./hollihop-entities-mappers";

describe("hollihop-entities-mappers", () => {
  it("converts naive Moscow datetimes to ISO with offset", () => {
    expect(hhDateTimeToIso("2024-11-26T15:13:18")).toBe("2024-11-26T15:13:18+03:00");
    expect(hhDateTimeToIso("2023-03-19")).toBe("2023-03-19T00:00:00+03:00");
    expect(hhDateTimeToIso("не дата")).toBeNull();
  });

  it("computes duration with a 60-minute fallback", () => {
    expect(durationFromTimes("16:00", "17:30")).toBe(90);
    expect(durationFromTimes("16:00", "15:00")).toBe(60);
    expect(durationFromTimes("", "")).toBe(60);
  });

  it("maps a study request with UTM and referrer", () => {
    const mapped = studyRequestFromRow({
      Id: 17,
      Created: "2024-11-26T15:13:18",
      Status: 1,
      Office: "М. Спортивная",
      Name: "Владимир",
      Discipline: "Барабаны",
      Type: "Заявка на обучение",
      Utm: { Source: "yandex", Medium: "cpc" },
      Referrer: "https://ya.ru",
      LeadId: 42,
    });
    expect(mapped).toMatchObject({
      idRaw: "17",
      leadIdRaw: "42",
      appliedAt: "2024-11-26T15:13:18+03:00",
      channel: "Заявка на обучение",
      discipline: "Барабаны",
      status: "1",
      utm: { Source: "yandex", Medium: "cpc", Referrer: "https://ya.ru" },
    });
  });

  it("maps an ed-unit lead trial with visited flag and duration", () => {
    const mapped = edUnitLeadFromRow({
      EdUnitId: 12,
      LeadId: 6,
      Date: "2023-03-19",
      BeginTime: "16:00",
      EndTime: "17:00",
      Visited: false,
      EdUnitOfficeOrCompanyId: 1,
      EdUnitName: "Пробный барабаны А.",
      EdUnitDiscipline: "Барабаны",
    });
    expect(mapped).toMatchObject({
      edUnitIdRaw: "12",
      leadIdRaw: "6",
      scheduledAt: "2023-03-19T16:00:00+03:00",
      durationMinutes: 60,
      visited: false,
      officeIdRaw: "1",
    });
    expect(edUnitLeadFromRow({ EdUnitId: 1, LeadId: 2, Date: "мусор" })).toBeNull();
  });

  it("maps prices in minutes to catalog hours and skips non-minute units", () => {
    const mapped = priceFromRow(
      { Id: 203, Name: "Абонемент на 48 уроков", ValueQuantity: 115200, UnitsQuantity: 2880, UnitsType: "Minutes", Offices: [{ Id: 1 }, { Id: 2 }] },
      3,
    );
    expect(mapped).toMatchObject({ idRaw: "203", hours: 48, price: 115200, sortOrder: 3, soleOfficeIdRaw: null });
    const solo = priceFromRow(
      { Id: 1, Name: "X", ValueQuantity: 100, UnitsQuantity: 90, UnitsType: "Minutes", Offices: [{ Id: 2 }] },
      0,
    );
    expect(solo).toMatchObject({ hours: 1.5, soleOfficeIdRaw: "2" });
    expect(priceFromRow({ Id: 2, Name: "Y", ValueQuantity: 100, UnitsQuantity: 5, UnitsType: "Units" }, 0)).toBeNull();
  });

  it("maps communications with способ prefix and keeps raw body for dedup", () => {
    const mapped = communicationFromRow({
      "Дата": "05.10.2026",
      "Ученик": "Луканюк Вероника Викторовна",
      "Способ": "Звонок",
      "Направление": "Входящая",
      "Описание": "перезвонить в сентябре",
      "ИД ученика": 3976,
    });
    expect(mapped).toMatchObject({
      dateRaw: "05.10.2026",
      studentIdRaw: "3976",
      body: "Звонок · Входящая: перезвонить в сентябре",
      rawBody: "перезвонить в сентябре",
    });
    expect(communicationFromRow({ "Описание": "" })).toBeNull();
  });
});
