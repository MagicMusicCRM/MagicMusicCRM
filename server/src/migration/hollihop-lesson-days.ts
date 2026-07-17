// server/src/migration/hollihop-lesson-days.ts
//
// Занятия из `EdUnits[].Days` — из того, что РЕАЛЬНО было, а не из шаблона.
//
// ЗАЧЕМ. Импортёр строил занятия, разворачивая `ScheduleItems` по дням недели, а
// `Days` использовал только для посещаемости. Но расписание — это намерение, а
// `Days` — факт: перенесли занятие на другой день, и оно в шаблон не попадает.
//
// Измерено на дампе 17.07:
//   • 4 975 реальных дней занятий (13% из 37 469) не порождали занятия ВООБЩЕ —
//     их просто не было в базе, вместе с 2 615 заметками админа к ним;
//   • и наоборот: 1 502 занятия в базе не соответствовали ни одному реальному
//     дню — их выдумал шаблон (расписание без EndDate разворачивалось до 2028).
//
// ЧЕМ DAYS ЛУЧШЕ. Каждый Day несёт всё нужное:
//   Date, Minutes (реальная длительность), Pass (посещаемость),
//   Description (заметка админа), ScheduleItemIds (какой слот он реализует).
// Через ScheduleItemIds берутся время, аудитория и педагог. Проверено: у ВСЕХ
// 37 469 дней ссылки разрешаются, промахов ноль.
//
// ⚠️ ОДИН DAY — НЕ ВСЕГДА ОДНО ЗАНЯТИЕ. У 1 280 дней слотов несколько, и они
// бывают двух родов:
//   • подряд (438): 11:00–12:00 + 12:00–13:00 — это ОДНО занятие на два часа,
//     и прежний импортёр их сливал (mergeContiguousScheduleItems);
//   • врозь (842): 13:00–14:00 и 17:00–18:00 — это ДВА разных занятия в один
//     день, и слить их значило бы выдумать одно четырёхчасовое.
// Отсюда правило: одно занятие на непрерывную цепочку слотов.

/** Слот расписания — то, что даёт занятию время. */
export interface ScheduleSlot {
  id: string;
  /** «HH:MM». */
  beginTime: string;
  /** «HH:MM». */
  endTime: string;
}

/** Занятие, восстановленное из дня: непрерывная цепочка слотов. */
export interface LessonRun {
  /**
   * Слот, от которого выводится id занятия, — первый в цепочке.
   *
   * Тот же, что брал прежний импортёр у слитого элемента, поэтому у занятий,
   * которые он находил и раньше, id не меняется: реимпорт не задваивает.
   */
  scheduleId: string;
  beginTime: string;
  endTime: string;
  /** Все слоты цепочки, по порядку. */
  scheduleIds: string[];
}

/**
 * Дни занятия → занятия.
 *
 * Слоты сортируются по времени начала и склеиваются, пока конец предыдущего
 * совпадает с началом следующего.
 *
 * Слот, которого нет среди `slotsById`, пропускается: на дампе таких нет (0 из
 * 37 469), но выдумывать время занятию, слота которого мы не знаем, нельзя.
 */
export function lessonRunsForDay(
  scheduleItemIds: string[],
  slotsById: Map<string, ScheduleSlot>,
): LessonRun[] {
  const slots = scheduleItemIds
    .map((id) => slotsById.get(id))
    .filter((slot): slot is ScheduleSlot => slot !== undefined && Boolean(slot.beginTime))
    .sort((a, b) => a.beginTime.localeCompare(b.beginTime));

  const runs: LessonRun[] = [];
  for (const slot of slots) {
    const current = runs[runs.length - 1];
    if (current && current.endTime && current.endTime === slot.beginTime) {
      current.endTime = slot.endTime;
      current.scheduleIds.push(slot.id);
      continue;
    }
    runs.push({
      scheduleId: slot.id,
      beginTime: slot.beginTime,
      endTime: slot.endTime,
      scheduleIds: [slot.id],
    });
  }
  return runs;
}
