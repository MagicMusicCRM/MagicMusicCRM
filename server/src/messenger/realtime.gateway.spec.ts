// server/src/messenger/realtime.gateway.spec.ts
import { resolveRealtimeCorsOrigin } from './realtime.gateway';

describe('resolveRealtimeCorsOrigin', () => {
  it('parses comma-separated origins into a trimmed allowlist array', () => {
    expect(resolveRealtimeCorsOrigin('https://a.ru,https://b.ru')).toEqual([
      'https://a.ru',
      'https://b.ru'
    ]);
  });

  it('trims whitespace and drops empty entries', () => {
    expect(resolveRealtimeCorsOrigin(' https://a.ru , , https://b.ru ')).toEqual([
      'https://a.ru',
      'https://b.ru'
    ]);
  });

  it('returns false (closed) for empty/undefined config in production', () => {
    expect(resolveRealtimeCorsOrigin('', 'production')).toBe(false);
    expect(resolveRealtimeCorsOrigin(undefined, 'production')).toBe(false);
  });

  it('allows true in non-production (dev) when no origins configured', () => {
    expect(resolveRealtimeCorsOrigin('', 'development')).toBe(true);
    expect(resolveRealtimeCorsOrigin(undefined)).toBe(true);
  });
});
