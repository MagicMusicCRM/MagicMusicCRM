const sensitiveKeyPattern =
  /(authorization|cookie|password|token|secret|otp|api[_-]?key|refresh|access|private[_-]?url|signed[_-]?url)/i;

export function redactSensitive(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map((item) => redactSensitive(item));
  }

  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([key, entry]) => [
        key,
        sensitiveKeyPattern.test(key) ? '[REDACTED]' : redactSensitive(entry)
      ])
    );
  }

  if (typeof value === 'string') {
    return value.replace(/Bearer\s+[A-Za-z0-9._~+/=-]+/gi, 'Bearer [REDACTED]');
  }

  return value;
}
