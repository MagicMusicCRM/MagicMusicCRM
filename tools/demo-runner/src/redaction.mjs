const REDACTED = '<redacted>';

export class SecretVault {
  #values = new Set();

  add(value) {
    if (typeof value === 'string' && value.length > 0) {
      this.#values.add(value);
    }
  }

  delete(value) {
    if (typeof value === 'string') {
      this.#values.delete(value);
    }
  }

  redact(value) {
    let result = String(value ?? '');
    for (const secret of [...this.#values].sort((a, b) => b.length - a.length)) {
      result = result.split(secret).join(REDACTED);
    }
    return result
      .replace(/(password|passwd|token|secret)(\s*[=:]\s*)[^\s,;]+/gi, `$1$2${REDACTED}`)
      .replace(/(<node\b[^>]*\bpassword="true"[^>]*\btext=")[^"]*(")/gi, `$1${REDACTED}$2`);
  }

  assertSafe(value, label = 'value') {
    const raw = JSON.stringify(value);
    for (const secret of this.#values) {
      if (raw.includes(secret)) {
        throw new Error(`Refusing to persist ${label}: it contains a runtime credential.`);
      }
    }
  }
}

export function sanitizedChildEnvironment(environment = process.env) {
  const result = {};
  for (const [key, value] of Object.entries(environment)) {
    if (/^DEMO_.+_(PASSWORD|LOGIN|EMAIL|PHONE)$/i.test(key)) continue;
    if (key === 'APPIUM_HOME') continue;
    result[key] = value;
  }
  return result;
}
