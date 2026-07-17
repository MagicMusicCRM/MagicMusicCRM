// server/src/migration/hollihop-lesson-days.spec.ts
//
// Случаи взяты из дампа 17.07 — вместе с номерами юнитов, чтобы их можно было
// найти в исходных данных.

import { lessonRunsForDay, type ScheduleSlot } from "./hollihop-lesson-days";

const slots = (...items: [string, string, string][]): Map<string, ScheduleSlot> =>
  new Map(items.map(([id, beginTime, endTime]) => [id, { id, beginTime, endTime }]));

describe("lessonRunsForDay", () => {
  it("один слот — одно занятие", () => {
    expect(lessonRunsForDay(["14"], slots(["14", "18:00", "19:00"]))).toEqual([
      { scheduleId: "14", beginTime: "18:00", endTime: "19:00", scheduleIds: ["14"] },
    ]);
  });

  /**
   * Юнит 24, 27.05.2023: 11:00–12:00 + 12:00–13:00, Minutes=120. Школа
   * поставила два часа подряд — это одно двухчасовое занятие, и прежний
   * импортёр их тоже сливал.
   */
  it("слоты подряд — ОДНО занятие на всю цепочку", () => {
    expect(
      lessonRunsForDay(["1", "2"], slots(["1", "11:00", "12:00"], ["2", "12:00", "13:00"])),
    ).toEqual([
      { scheduleId: "1", beginTime: "11:00", endTime: "13:00", scheduleIds: ["1", "2"] },
    ]);
  });

  /**
   * Юнит 46, 29.06.2023: 17:00–18:00 и 13:00–14:00, Minutes=120. Это ДВА разных
   * занятия в один день. Слей их — получилось бы одно четырёхчасовое с 13:00,
   * которого не было. Таких дней 842.
   */
  it("слоты врозь — РАЗНЫЕ занятия, а не одно длинное", () => {
    expect(
      lessonRunsForDay(["1", "2"], slots(["1", "17:00", "18:00"], ["2", "13:00", "14:00"])),
    ).toEqual([
      { scheduleId: "2", beginTime: "13:00", endTime: "14:00", scheduleIds: ["2"] },
      { scheduleId: "1", beginTime: "17:00", endTime: "18:00", scheduleIds: ["1"] },
    ]);
  });

  it("порядок в ScheduleItemIds не важен: сортируем по времени", () => {
    // В дампе они и приходят вперемешку — см. юнит 46 выше.
    const out = lessonRunsForDay(
      ["2", "1"],
      slots(["1", "11:00", "12:00"], ["2", "12:00", "13:00"]),
    );
    expect(out).toHaveLength(1);
    expect(out[0]).toMatchObject({ beginTime: "11:00", endTime: "13:00" });
  });

  it("три слота: два подряд и один отдельно", () => {
    const out = lessonRunsForDay(
      ["1", "2", "3"],
      slots(["1", "10:00", "11:00"], ["2", "11:00", "12:00"], ["3", "19:00", "20:00"]),
    );
    expect(out).toEqual([
      { scheduleId: "1", beginTime: "10:00", endTime: "12:00", scheduleIds: ["1", "2"] },
      { scheduleId: "3", beginTime: "19:00", endTime: "20:00", scheduleIds: ["3"] },
    ]);
  });

  /**
   * id занятия выводится из первого слота цепочки — того же, что брал прежний
   * импортёр у слитого элемента. Иначе реимпорт задвоил бы 32 494 занятия,
   * которые и так уже лежат правильно.
   */
  it("id цепочки — первый слот по времени, а не первый в списке", () => {
    const out = lessonRunsForDay(
      ["9", "5"],
      slots(["9", "12:00", "13:00"], ["5", "11:00", "12:00"]),
    );
    expect(out[0].scheduleId).toBe("5");
  });

  it("слота нет среди известных — пропускаем, а не выдумываем время", () => {
    expect(lessonRunsForDay(["1", "нет-такого"], slots(["1", "10:00", "11:00"]))).toEqual([
      { scheduleId: "1", beginTime: "10:00", endTime: "11:00", scheduleIds: ["1"] },
    ]);
  });

  it("слот без времени начала — не занятие", () => {
    expect(lessonRunsForDay(["1"], slots(["1", "", "11:00"]))).toEqual([]);
  });

  it("нет слотов — нет занятий", () => {
    expect(lessonRunsForDay([], slots(["1", "10:00", "11:00"]))).toEqual([]);
  });
});
