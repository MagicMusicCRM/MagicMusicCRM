// server/src/crm/phone.util.ts
export type PhoneNormalizationReason = "ok" | "empty" | "too_short" | "non_ru";

export interface NormalizedPhone {
  canonical: string | null; // '+7XXXXXXXXXX' for valid RU numbers, else null
  reason: PhoneNormalizationReason;
}

// Single source of truth for Russian phone normalization (replaces the three
// historical variants in profile/crm/import). Returns the canonical +7 form or
// null + a reason so callers can route un-normalizable values to review.
export function normalizePhoneRu(raw: string | null | undefined): NormalizedPhone {
  const digits = (raw ?? "").replace(/\D/g, "");
  if (digits.length === 0) return { canonical: null, reason: "empty" };
  if (digits.length === 11 && (digits[0] === "7" || digits[0] === "8")) {
    return { canonical: `+7${digits.slice(1)}`, reason: "ok" };
  }
  if (digits.length === 10 && digits[0] === "9") {
    return { canonical: `+7${digits}`, reason: "ok" };
  }
  return { canonical: null, reason: digits.length < 10 ? "too_short" : "non_ru" };
}

// SQL expression producing the IDENTICAL canonical value for a phone column,
// for use in bulk backfill and join-on-phone queries. Keep in lockstep with
// normalizePhoneRu above.
export function normalizedPhoneExpr(column: string): string {
  const digits = `regexp_replace(coalesce(${column}, ''), '[^0-9]', '', 'g')`;
  return `
    case
      when length(${digits}) = 11 and left(${digits}, 1) in ('7', '8') then '+7' || right(${digits}, 10)
      when length(${digits}) = 10 and left(${digits}, 1) = '9' then '+7' || ${digits}
      else null
    end
  `;
}
