const sensitiveKeyPattern =
  /(authorization|cookie|password|token|secret|otp|api[_-]?key|refresh|access|private[_-]?url|signed[_-]?url)/i;

// PII keys (152-ФЗ): masked so profile/lead/student DTOs don't leak contacts
// into stdout/docker logs (KVA). Contact fields → [PII].
const piiKeyPattern =
  /(e-?mail|phone|\btel\b|first[_-]?name|last[_-]?name|full[_-]?name|middle[_-]?name|patronymic|\bfio\b|\bdob\b|birth|address|passport)/i;

// Email values embedded in free-text strings. (Phone-in-text is intentionally
// not regex-masked to avoid false positives on dates/ids; phone *fields* are
// covered by piiKeyPattern above.)
const emailValuePattern = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g;

export function redactSensitive(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map((item) => redactSensitive(item));
  }

  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([key, entry]) => {
        if (sensitiveKeyPattern.test(key)) return [key, '[REDACTED]'];
        if (piiKeyPattern.test(key)) return [key, '[PII]'];
        return [key, redactSensitive(entry)];
      })
    );
  }

  if (typeof value === 'string') {
    return value
      .replace(/Bearer\s+[A-Za-z0-9._~+/=-]+/gi, 'Bearer [REDACTED]')
      .replace(emailValuePattern, '[EMAIL]');
  }

  return value;
}
