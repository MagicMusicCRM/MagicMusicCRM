// Pure HolliHop GetHistoryModifyLeadStatus → normalized-row shaping. No DB / IO. Unit-tested.

function str(value: unknown): string | null {
  if (typeof value === "string") {
    const t = value.trim();
    return t.length ? t : null;
  }
  if (typeof value === "number" && Number.isFinite(value)) return String(value);
  return null;
}

// HolliHop datetimes are Moscow-local without an offset. Append +03:00 so a
// downstream `new Date(...)` parses the correct instant. Leave values that
// already carry a zone (`Z` or `±hh:mm`) untouched. Pass through undefined.
export function appendMoscowOffset(raw: string | undefined): string | undefined {
  if (raw === undefined) return undefined;
  if (/(?:Z|[+-]\d{2}:?\d{2})$/.test(raw)) return raw;
  return `${raw}+03:00`;
}

export interface HistoryEntry {
  leadIdRaw: string;
  afterIdRaw: string | null;
  afterName: string | null;
  dateTimeRaw: string;
}

export function historyEntryFromRow(
  row: Record<string, unknown>,
): HistoryEntry | null {
  const leadIdRaw = str(row.LeadId);
  const dateTimeRaw = str(row.DateTime);
  if (!leadIdRaw || !dateTimeRaw) return null;
  return {
    leadIdRaw,
    afterIdRaw: str(row.AfterId),
    afterName: str(row.AfterName),
    dateTimeRaw,
  };
}
