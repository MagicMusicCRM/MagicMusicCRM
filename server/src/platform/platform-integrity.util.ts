import { createHash } from "crypto";
import { redactSensitive } from "../common/logging/redact.util";

const privateReferenceKeyPattern =
  /(amount|price|balance|revenue|expense|salary|rate|currency|phone|e-?mail|address|name|comment|body|message|note|description|text|content|passport|birth|\bdob\b|\bip\b|user[_-]?agent)/i;
const secretReferenceKeyPattern =
  /(authorization|cookie|password|token|secret|otp|api[_-]?key|refresh|access(?!version)|private[_-]?url|signed[_-]?url)/i;

const safeOutboxKeys = new Set([
  "accessVersion",
  "aggregateId",
  "changedFields",
  "entityId",
  "invalidates",
  "reasonCode",
  "scope",
  "state",
  "status",
  "version",
]);

function canonicalize(value: unknown): unknown {
  if (value instanceof Date) {
    return value.toISOString();
  }
  if (Array.isArray(value)) {
    return value.map((item) => canonicalize(item));
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, entry]) => [key, canonicalize(entry)]),
    );
  }
  if (typeof value === "number" && !Number.isFinite(value)) {
    throw new TypeError("Fingerprint payload contains a non-finite number.");
  }
  if (
    typeof value === "bigint" ||
    typeof value === "function" ||
    typeof value === "symbol" ||
    typeof value === "undefined"
  ) {
    throw new TypeError(
      `Fingerprint payload contains unsupported ${typeof value}.`,
    );
  }
  return value;
}

function maskPrivateReferenceFields(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map((item) => maskPrivateReferenceFields(item));
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>).map(([key, entry]) => [
        key,
        secretReferenceKeyPattern.test(key)
          ? "[REDACTED]"
          : privateReferenceKeyPattern.test(key)
            ? "[PRIVATE]"
            : maskPrivateReferenceFields(entry),
      ]),
    );
  }
  return redactSensitive(value);
}

export function fingerprintPayload(payload: unknown): string {
  const canonical = JSON.stringify(canonicalize(payload));
  if (canonical === undefined) {
    throw new TypeError("Fingerprint payload must be JSON-serializable.");
  }
  return createHash("sha256").update(canonical).digest("hex");
}

export function safeReference<T extends Record<string, unknown>>(
  value: T,
): T {
  return maskPrivateReferenceFields(value) as T;
}

export function safeOutboxPayload(
  value: Record<string, unknown> = {},
): Record<string, unknown> {
  const allowed = Object.fromEntries(
    Object.entries(value).filter(([key]) => safeOutboxKeys.has(key)),
  );
  return maskPrivateReferenceFields(redactSensitive(allowed)) as Record<
    string,
    unknown
  >;
}

export function safeAuditReason(reason: string | undefined): string | null {
  if (reason === undefined) return null;
  if (!/^[A-Za-z0-9._:-]{1,120}$/.test(reason)) {
    throw new TypeError("Audit reason must be a non-sensitive reason code.");
  }
  return reason;
}

export function safeAuditReasonText(
  reasonText: string | undefined,
): string | null {
  if (reasonText === undefined) return null;
  const value = reasonText.trim();
  if (!value || value.length > 500 || value.includes("\0")) {
    throw new TypeError("Audit reason text must contain 1..500 safe characters.");
  }
  return value;
}

export function safeFailureName(error: unknown): string {
  const raw =
    error instanceof Error
      ? error.name || "Error"
      : typeof error === "string"
        ? error
        : "UnknownError";
  return raw.replace(/[^\w.-]/g, "_").slice(0, 120) || "UnknownError";
}

export function computeOutboxBackoffSeconds(
  attempts: number,
  baseSeconds = 5,
  capSeconds = 300,
): number {
  const safeAttempts = Math.max(1, Math.floor(attempts));
  const safeBase = Math.max(1, Math.floor(baseSeconds));
  const safeCap = Math.max(safeBase, Math.floor(capSeconds));
  return Math.min(safeCap, safeBase * 2 ** (safeAttempts - 1));
}
