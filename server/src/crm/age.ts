// server/src/crm/age.ts
//
// «Возраст» клиента.
//
// ✔ Решение владельца 17.07: возраст можно вписать руками, а можно поставить
// дату рождения — и тогда он считается сам и меняется по прошедшим годам.
//
// Раньше возраст был понятием только Flutter'а: `_ageLabel()` в карточке
// вычислял его из `custom_data.birthday` при отрисовке. Ни отдать возраст в
// отчёт, ни отфильтровать по нему, ни просто вписать «7 лет», не зная дня
// рождения, было нельзя. Отсюда этот резолвер — один на лидов и учеников,
// потому что вопрос один и тот же.

/** Дата рождения. Считает возраст сама и не устаревает. */
export const BIRTHDAY_KEY = "birthday";

/** Возраст, вписанный руками, — когда дня рождения не знают. */
export const AGE_KEY = "age";

export interface ResolvedAge {
  /** Полных лет. */
  years: number | null;
  /**
   * Полных месяцев сверх лет. Есть только у посчитанного возраста: у младенца
   * «0 лет» — это не ответ, а «8 месяцев» — ответ.
   */
  months: number | null;
  /** Откуда взялся возраст. `null`, если неизвестен. */
  source: "birthday" | "manual" | null;
}

const UNKNOWN: ResolvedAge = { years: null, months: null, source: null };

/**
 * Разбирает дату рождения. Принимает и ISO (`1998-04-12`), и русский формат
 * (`12.04.1998`): в `custom_data` лежат оба — ISO пишет пикер, «дд.мм.гггг»
 * приехало импортом HolliHop.
 */
export function parseBirthday(value: unknown): Date | null {
  if (value === null || value === undefined) return null;
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? null : value;
  }
  const text = String(value).trim();
  if (!text) return null;

  const ru = /^(\d{2})\.(\d{2})\.(\d{4})$/.exec(text);
  if (ru) {
    const [, day, month, year] = ru;
    const date = new Date(Date.UTC(+year, +month - 1, +day));
    // Date.UTC молча переносит 31.02 на 03.03 — такую дату мы не принимаем.
    if (
      date.getUTCFullYear() !== +year ||
      date.getUTCMonth() !== +month - 1 ||
      date.getUTCDate() !== +day
    ) {
      return null;
    }
    return date;
  }

  const iso = /^(\d{4})-(\d{2})-(\d{2})/.exec(text);
  if (!iso) return null;
  const date = new Date(text);
  return Number.isNaN(date.getTime()) ? null : date;
}

/**
 * Полных лет и месяцев между двумя датами. Считается по календарю, а не
 * делением на 365.25: иначе високосные годы уводят день рождения.
 *
 * Обе даты читаются в UTC — важно, что в одной зоне, а не в какой именно.
 * Плата за это: в день рождения возраст переключается в 00:00 UTC, то есть для
 * Москвы на три часа позже полуночи. Тянуть сюда таймзоны ради трёх часов раз
 * в год на подписи под именем не стоит.
 */
export function ageAt(birthday: Date, now: Date): { years: number; months: number } {
  let years = now.getUTCFullYear() - birthday.getUTCFullYear();
  let months = now.getUTCMonth() - birthday.getUTCMonth();
  // День рождения ещё не наступил в этом месяце — месяц не полный.
  if (now.getUTCDate() < birthday.getUTCDate()) months -= 1;
  if (months < 0) {
    years -= 1;
    months += 12;
  }
  return { years, months };
}

const asManualAge = (value: unknown): number | null => {
  if (value === null || value === undefined) return null;
  const text = String(value).trim();
  if (!text) return null;
  const years = Number(text);
  if (!Number.isFinite(years)) return null;
  const whole = Math.trunc(years);
  if (whole < 0 || whole > 120) return null;
  return whole;
};

/**
 * Разрешает возраст записи.
 *
 * ⚠️ Порядок здесь **обратный** тому, что в `appeal-date.ts`, и это осознанно.
 * Там ручное значение побеждает автоматику, потому что человек проставил дату
 * осознанно. Здесь наоборот: возраст, вписанный руками, — это снимок, который
 * протухает молча. «7», вписанное год назад, так и останется семёркой, хотя
 * ребёнку уже восемь. Дата рождения знает правду и не устаревает, поэтому если
 * она есть — считаем по ней.
 */
export function resolveAge(
  customData: Record<string, unknown> | null | undefined,
  now: Date = new Date(),
): ResolvedAge {
  const data = customData ?? {};

  const birthday = parseBirthday(data[BIRTHDAY_KEY]);
  if (birthday) {
    const { years, months } = ageAt(birthday, now);
    // Дата из будущего или опечатка в веке — не возраст. Молча показать «-3»
    // хуже, чем не показать ничего.
    if (years >= 0 && years <= 120) {
      return { years, months, source: "birthday" };
    }
  }

  const manual = asManualAge(data[AGE_KEY]);
  if (manual !== null) return { years: manual, months: null, source: "manual" };

  return UNKNOWN;
}
