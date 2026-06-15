import {
  buildOrderClause,
  exportRelativePath,
  parseSchemaList,
  qualifiedName,
  quoteIdentifier,
  redactConnectionString,
  stableJsonLine
} from './supabase-export-utils';

describe('supabase export utilities', () => {
  it('parses unique schema list', () => {
    expect(parseSchemaList('public, auth, public,storage')).toEqual([
      'public',
      'auth',
      'storage'
    ]);
  });

  it('quotes safe identifiers and rejects unsafe names', () => {
    expect(qualifiedName('public', 'profiles')).toBe('"public"."profiles"');
    expect(() => quoteIdentifier('public;drop schema app')).toThrow('Unsafe SQL identifier');
  });

  it('orders by primary key before falling back to ordinal columns', () => {
    const columns = [
      { name: 'email', ordinalPosition: 2 },
      { name: 'id', ordinalPosition: 1 }
    ];
    expect(buildOrderClause(columns, ['id'])).toBe('order by "id"');
    expect(buildOrderClause(columns, [])).toBe('order by "id", "email"');
  });

  it('creates stable json lines for checksum and ndjson', () => {
    expect(stableJsonLine({ b: 2, a: { d: 4, c: 3 } })).toBe(
      '{"a":{"c":3,"d":4},"b":2}\n'
    );
  });

  it('redacts connection string credentials', () => {
    expect(redactConnectionString('postgres://user:pass@example.com/db')).toBe(
      'postgres://***:***@example.com/db'
    );
  });

  it('builds deterministic relative export paths', () => {
    expect(exportRelativePath('public', 'profiles')).toBe('data/public.profiles.ndjson');
  });
});
