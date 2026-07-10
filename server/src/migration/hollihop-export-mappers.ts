// server/src/migration/hollihop-export-mappers.ts
// Pure parsers/shapers for HolliHop manual XLSX/CSV exports (converted to JSON).

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : v == null ? "" : String(v).trim();
}

export function parseRuDate(raw: unknown): string | null {
  const s = str(raw);
  // Час бывает однозначным, разделитель — в т.ч. переносом строки («18.03.2026\n9:55»).
  const m = s.match(/^(\d{2})\.(\d{2})\.(\d{4})(?:\s+(\d{1,2}):(\d{2}))?$/);
  if (!m) return null;
  const [, dd, mm, yyyy, hh, mi] = m;
  const iso = `${yyyy}-${mm}-${dd}T${(hh ?? "0").padStart(2, "0")}:${mi ?? "00"}:00.000Z`;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  if (d.getUTCFullYear() !== Number(yyyy) || d.getUTCMonth() + 1 !== Number(mm) || d.getUTCDate() !== Number(dd)) return null;
  if (hh !== undefined && (d.getUTCHours() !== Number(hh) || d.getUTCMinutes() !== Number(mi))) return null;
  return d.toISOString();
}

export function taskTitle(description: string): string {
  const first = str(description).split(/\r?\n/).find((l) => l.trim().length) ?? "";
  const t = first.trim();
  if (!t) return "Задача (HolliHop)";
  return t.length > 120 ? t.slice(0, 120) : t;
}

export function cleanResponsible(raw: unknown): string | null {
  const s = str(raw);
  if (!s || /^\[.*\]$/.test(s)) return null; // "[Для всех]" and similar placeholders
  return s;
}

export function taskFromRow(row: Record<string, unknown>) {
  const description = str(row["Описание"]);
  const clientName = str(row["Клиент"]);
  if (!description && !clientName) return null;
  return {
    phoneRaw: str(row["Моб. телефон"]) || str(row["Телефон"]),
    clientName,
    description,
    dueRaw: str(row["Дата выполнения"]),
    responsible: str(row["Ответственный"]),
  };
}

export function studentNoteFromRow(row: Record<string, unknown>) {
  const note = str(row["Описание"]);
  if (!note) return null;
  return {
    phoneRaw: str(row["Моб. телефон"]) || str(row["Телефон"]),
    name: [str(row["Фамилия"]), str(row["Имя"])].filter(Boolean).join(" "),
    note,
  };
}

export function leadCommentFromRow(row: Record<string, unknown>) {
  const comment = str(row["Комментарий"]);
  if (!comment) return null;
  const extra = str(row["Пользовательские поля"]);
  return {
    phoneRaw: str(row["Моб. телефон"]) || str(row["Телефон"]),
    name: str(row["ФИО"]),
    body: extra ? `${comment}\n${extra}` : comment,
  };
}
