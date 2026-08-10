const MOSCOW_OFFSET_MS = 3 * 60 * 60 * 1_000;

export function moscowTodayStartMs(nowMs: number): number {
  const moscowNow = new Date(nowMs + MOSCOW_OFFSET_MS);
  return (
    Date.UTC(
      moscowNow.getUTCFullYear(),
      moscowNow.getUTCMonth(),
      moscowNow.getUTCDate(),
    ) - MOSCOW_OFFSET_MS
  );
}

export function isTaskOverdue(
  input: {
    state: string;
    startAt: Date | string | null;
    allDay: boolean;
  },
  nowMs = Date.now(),
): boolean {
  if (input.state !== "open" || input.startAt === null) return false;
  const dueMs = new Date(input.startAt).getTime();
  if (!Number.isFinite(dueMs)) return false;
  return dueMs < (input.allDay ? moscowTodayStartMs(nowMs) : nowMs);
}
