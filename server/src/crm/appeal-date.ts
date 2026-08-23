// server/src/crm/appeal-date.ts
//
// «Дата обращения» — когда клиент впервые обратился в школу.
//
// ✔ Решение владельца 16.07.2026: если лид пришёл впервые ЧЕРЕЗ ПРИЛОЖЕНИЕ,
// датой обращения автоматически становится момент, когда он стал лидом здесь.
// Но при дедупе/слиянии по телефону побеждают данные HolliHop — там лежит
// настоящая, более ранняя дата.
//
// Отсюда порядок разрешения ниже. Он один на лидов и учеников, потому что
// вопрос один и тот же, и две копии этого правила разъехались бы.

/** Ключ, которым импорт HolliHop клал исходную дату обращения (`AddressDate`). */
const HOLLIHOP_APPEAL_KEY = "addressDate";

/** Явное поле «Дата обращения» — правка руками или перенос при конвертации. */
export const APPEAL_KEY = "appealAt";

const asIsoDate = (value: unknown): string | null => {
  if (value === null || value === undefined) return null;
  const text = value instanceof Date ? value.toISOString() : String(value).trim();
  if (!text) return null;
  const date = new Date(text);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
};

export interface AppealDate {
  value: string | null;
  /** Откуда взялась дата — нужно, чтобы слияние знало, что беречь. */
  source: "manual" | "hollihop" | "app";
}

/**
 * Разрешает дату обращения записи.
 *
 * Порядок намеренно такой:
 *  1. `appealAt` — кто-то проставил её осознанно (правка или конвертация лида).
 *     Осознанное действие человека не должен перебивать никакой автомат.
 *  2. `addressDate` — исходная дата из HolliHop. Побеждает дату появления
 *     записи у нас: там клиент обратился раньше, и это и есть та причина, по
 *     которой данные HolliHop важно получить.
 *  3. `created_at` — запись родилась в приложении, значит обратились тогда же.
 *
 * ⚠️ Схема настроек объявляет у лида поле `appealAt`, а импорт писал
 * `addressDate` — то есть объявленное поле для импортированных записей было
 * мертво. Этот резолвер читает оба, поэтому 5931 лид и 3105 учеников из
 * HolliHop наконец показывают свою настоящую дату обращения.
 */
export function resolveAppealDate(
  customData: Record<string, unknown> | null | undefined,
  createdAt: Date | string | null | undefined,
): AppealDate {
  const data = customData ?? {};

  const manual = asIsoDate(data[APPEAL_KEY]);
  if (manual) return { value: manual, source: "manual" };

  const hollihop = asIsoDate(data[HOLLIHOP_APPEAL_KEY]);
  if (hollihop) return { value: hollihop, source: "hollihop" };

  return { value: asIsoDate(createdAt), source: "app" };
}

/** True, если запись пришла из HolliHop (импорт всегда клал `hollihopId`). */
export function isHolliHopRecord(
  customData: Record<string, unknown> | null | undefined,
): boolean {
  const data = customData ?? {};
  return Boolean(data.hollihopId ?? data.hollihopClientId);
}

/**
 * Сливает `custom_data` проигравшей записи в победившую так, чтобы **данные
 * HolliHop уцелели** (✔ требование владельца: «при дедупе через телефон и тд
 * должны оставаться данные только из HolliHop»).
 *
 * Правила:
 *  - ключи, которых у победителя нет, добавляются всегда — терять данные при
 *    слиянии незачем;
 *  - если проигравший пришёл из HolliHop, а победитель нет, то по конфликтующим
 *    ключам выигрывает HolliHop: у него первоисточник, а у нас — то, что
 *    насочиняло приложение;
 *  - в обратную сторону (победитель из HolliHop) значения победителя не
 *    трогаются.
 */
export function mergeCustomData(
  winner: Record<string, unknown> | null | undefined,
  loser: Record<string, unknown> | null | undefined,
): Record<string, unknown> {
  const winnerData = { ...(winner ?? {}) };
  const loserData = loser ?? {};
  const loserWins = isHolliHopRecord(loserData) && !isHolliHopRecord(winnerData);

  for (const [key, value] of Object.entries(loserData)) {
    if (value === null || value === undefined) continue;
    const winnerValue = winnerData[key];
    const winnerHasValue = winnerValue !== null && winnerValue !== undefined;
    if (!winnerHasValue || loserWins) {
      winnerData[key] = value;
    }
  }
  return winnerData;
}
