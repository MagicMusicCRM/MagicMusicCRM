// server/src/migration/dump-edunits.ts
//
// Снимает `GetEdUnits` с живого API в файл — теми же параметрами, что и импорт.
//
// Зачем отдельно: сверять собранную базу с дампом недельной давности
// бессмысленно — данные за неделю расходятся, и любое расхождение списывается
// на «наверное, просто изменилось». Срез, снятый в тот же день, делает сверку
// доказательством, а не рассуждением.
//
// Usage:
//   HOLLIHOP_AUTH_KEY=... HOLLIHOP_DUMP_OUT=/path/edunits.json \
//     npx ts-node src/migration/dump-edunits.ts

import { writeFileSync } from "node:fs";

const BASE_URL =
  process.env.HOLLIHOP_BASE_URL?.trim() || "https://sokol.t8s.ru/Api/V2/";
const AUTH_KEY = process.env.HOLLIHOP_AUTH_KEY?.trim();
const OUT = process.env.HOLLIHOP_DUMP_OUT?.trim();
// Те же умолчания, что у импорта: срез обязан отвечать тому, что он зальёт.
const LESSON_FROM = process.env.HOLLIHOP_LESSON_FROM ?? "2023-01-01";
const LESSON_TO = process.env.HOLLIHOP_LESSON_TO ?? "2028-01-01";

async function main(): Promise<void> {
  if (!AUTH_KEY) throw new Error("HOLLIHOP_AUTH_KEY is required.");
  if (!OUT) throw new Error("HOLLIHOP_DUMP_OUT is required.");

  const url = new URL("GetEdUnits", BASE_URL);
  url.searchParams.set("authkey", AUTH_KEY);
  url.searchParams.set("dateFrom", LESSON_FROM);
  url.searchParams.set("dateTo", LESSON_TO);
  // queryDays=true — иначе юнит приедет без своих реальных занятий, а они здесь
  // и есть предмет.
  url.searchParams.set("queryDays", "true");

  const response = await fetch(url, { headers: { accept: "application/json" } });
  if (!response.ok) {
    throw new Error(`GetEdUnits → ${response.status} ${response.statusText}`);
  }
  const data = (await response.json()) as Record<string, unknown>;
  const units = Array.isArray(data.EdUnits) ? data.EdUnits : [];
  writeFileSync(OUT, JSON.stringify(units), "utf8");

  const days = (units as { Days?: unknown[] }[]).reduce(
    (n, u) => n + (u.Days?.length ?? 0),
    0,
  );
  console.log(`EdUnits: ${units.length} | Days: ${days} → ${OUT}`);
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
