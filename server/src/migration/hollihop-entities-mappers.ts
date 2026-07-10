// server/src/migration/hollihop-entities-mappers.ts
// Pure shapers for the KVA-233 entity importer (StudyRequests, EdUnitLeads,
// Prices from the API dump + Коммуникации from the manual XLSX export).

const MOSCOW_OFFSET = "+03:00";

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : v == null ? "" : String(v).trim();
}

// HolliHop API datetimes are naive Moscow local time ("2024-11-26T15:13:18").
export function hhDateTimeToIso(raw: unknown): string | null {
  const s = str(raw);
  if (!/^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}(:\d{2})?)?$/.test(s)) return null;
  const withTime = s.includes("T") ? s : `${s}T00:00`;
  const padded = withTime.length === 16 ? `${withTime}:00` : withTime;
  const iso = `${padded}${MOSCOW_OFFSET}`;
  return Number.isNaN(new Date(iso).getTime()) ? null : iso;
}

export function durationFromTimes(begin: unknown, end: unknown): number {
  const m = (t: string) => {
    const mm = t.match(/^(\d{1,2}):(\d{2})$/);
    return mm ? Number(mm[1]) * 60 + Number(mm[2]) : null;
  };
  const b = m(str(begin));
  const e = m(str(end));
  if (b === null || e === null || e <= b) return 60;
  return e - b;
}

export function studyRequestFromRow(row: Record<string, unknown>) {
  const idRaw = str(row.Id);
  if (!idRaw) return null;
  const utm = row.Utm && typeof row.Utm === "object" ? (row.Utm as object) : null;
  const referrer = str(row.Referrer);
  return {
    idRaw,
    leadIdRaw: str(row.LeadId),
    appliedAt: hhDateTimeToIso(row.Created),
    channel: str(row.Type) || null,
    office: str(row.Office) || null,
    discipline: str(row.Discipline) || null,
    status: str(row.Status) || null,
    utm: utm || referrer ? { ...(utm ?? {}), ...(referrer ? { Referrer: referrer } : {}) } : null,
  };
}

export function edUnitLeadFromRow(row: Record<string, unknown>) {
  const edUnitIdRaw = str(row.EdUnitId);
  const leadIdRaw = str(row.LeadId);
  const date = str(row.Date);
  if (!edUnitIdRaw || !leadIdRaw || !/^\d{4}-\d{2}-\d{2}$/.test(date)) return null;
  return {
    edUnitIdRaw,
    leadIdRaw,
    date,
    scheduledAt: `${date}T${str(row.BeginTime) || "00:00"}:00${MOSCOW_OFFSET}`,
    durationMinutes: durationFromTimes(row.BeginTime, row.EndTime),
    visited: row.Visited === true,
    officeIdRaw: str(row.EdUnitOfficeOrCompanyId),
    name: str(row.EdUnitName) || null,
    discipline: str(row.EdUnitDiscipline) || null,
  };
}

export function priceFromRow(row: Record<string, unknown>, index: number) {
  const idRaw = str(row.Id);
  const name = str(row.Name);
  const price = Number(row.ValueQuantity);
  const minutes = Number(row.UnitsQuantity);
  if (!idRaw || !name || !Number.isFinite(price) || price < 0) return null;
  // UnitsType "Minutes" → академические часы каталога считаем в часах (0047).
  if (str(row.UnitsType) !== "Minutes" || !Number.isFinite(minutes) || minutes <= 0) return null;
  const offices = Array.isArray(row.Offices) ? (row.Offices as Record<string, unknown>[]) : [];
  return {
    idRaw,
    name,
    price,
    hours: Math.round((minutes / 60) * 100) / 100,
    sortOrder: index,
    // Пакет действует в одном филиале → привязываем; в нескольких → общий.
    soleOfficeIdRaw: offices.length === 1 ? str(offices[0]?.Id) : null,
  };
}

export function communicationFromRow(row: Record<string, unknown>) {
  const body = str(row["Описание"]);
  if (!body) return null;
  const way = str(row["Способ"]);
  const direction = str(row["Направление"]);
  const prefix = way ? `${way}${direction ? ` · ${direction}` : ""}: ` : "";
  return {
    dateRaw: str(row["Дата"]),
    studentIdRaw: str(row["ИД ученика"]),
    name: str(row["Ученик"]),
    body: `${prefix}${body}`,
    rawBody: body,
  };
}
