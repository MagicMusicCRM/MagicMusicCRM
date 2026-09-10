import { BadRequestException } from "@nestjs/common";

export interface FinanceListCursor {
  at: string;
  id: string;
}

export function decodeFinanceCursor(value?: string): FinanceListCursor | null {
  if (value === undefined) return null;
  try {
    if (!value || value.length > 512 || !/^[A-Za-z0-9_-]+$/.test(value))
      throw new Error();
    const cursor = JSON.parse(Buffer.from(value, "base64url").toString("utf8"));
    if (
      typeof cursor?.at !== "string" ||
      !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/.test(cursor.at) ||
      !Number.isFinite(Date.parse(cursor.at)) ||
      new Date(cursor.at).toISOString().slice(0, 19) !==
        cursor.at.slice(0, 19) ||
      typeof cursor.id !== "string" ||
      !/^[\da-f]{8}(?:-[\da-f]{4}){3}-[\da-f]{12}$/i.test(cursor.id)
    )
      throw new Error();
    return { at: cursor.at, id: cursor.id };
  } catch {
    throw new BadRequestException(
      "Некорректная страница финансового списка. Обновите список.",
    );
  }
}

export function encodeFinanceCursor(row: {
  id: string;
  cursor_at: string;
}): string {
  // Preserve PostgreSQL microseconds; conversion through JavaScript Date loses precision.
  return Buffer.from(
    JSON.stringify({ at: row.cursor_at, id: row.id }),
  ).toString("base64url");
}
