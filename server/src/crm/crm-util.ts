import { BadRequestException } from "@nestjs/common";

/**
 * Small shared CRM utilities (B4). Pure functions — no state, no DI. Extracted
 * so the domain services (students/teachers/staff/groups/…) stop each carrying
 * their own copy of the same trim / json-sanitize / duplicate-email helpers.
 */

/** Trim a required string; throw a 400 with `message` when blank/missing. */
export function requiredTrim(value: string | undefined, message: string): string {
  const trimmed = value?.trim();
  if (!trimmed) throw new BadRequestException(message);
  return trimmed;
}

/** Trim an optional string to a non-empty value, else null. */
export function trimOptional(value: string | undefined): string | null {
  if (value === undefined) return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

/**
 * Map the Postgres unique-violation (23505) raised on a duplicate person email
 * to a friendly 400; rethrow anything else unchanged.
 */
export function rethrowCreatePersonError(error: unknown): never {
  if (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    (error as { code?: string }).code === "23505"
  ) {
    throw new BadRequestException("Пользователь с таким email уже существует.");
  }
  throw error;
}

// Defense-in-depth on customData (JSONB): bound depth/breadth/string size so a
// pathological patch can't bloat the row or DoS queries (KVA).
function assertJsonWithinLimits(value: unknown, depth: number): void {
  const MAX_DEPTH = 6;
  const MAX_KEYS = 100;
  const MAX_STRING = 10_000;
  if (depth > MAX_DEPTH) {
    throw new BadRequestException("customData: слишком глубокая вложенность.");
  }
  if (typeof value === "string") {
    if (value.length > MAX_STRING) {
      throw new BadRequestException("customData: слишком длинное значение.");
    }
    return;
  }
  if (Array.isArray(value)) {
    if (value.length > MAX_KEYS) {
      throw new BadRequestException("customData: слишком большой массив.");
    }
    for (const item of value) assertJsonWithinLimits(item, depth + 1);
    return;
  }
  if (value && typeof value === "object") {
    const keys = Object.keys(value as Record<string, unknown>);
    if (keys.length > MAX_KEYS) {
      throw new BadRequestException("customData: слишком много полей.");
    }
    for (const key of keys) {
      assertJsonWithinLimits((value as Record<string, unknown>)[key], depth + 1);
    }
  }
}

/** Drop `undefined` entries from a customData patch after bounding its size. */
export function sanitizeJsonObject(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  assertJsonWithinLimits(value, 0);
  return Object.fromEntries(
    Object.entries(value as Record<string, unknown>).filter(
      ([, entryValue]) => entryValue !== undefined,
    ),
  );
}
