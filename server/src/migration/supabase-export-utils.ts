import { createHash } from 'node:crypto';

export interface SourceColumn {
  name: string;
  ordinalPosition: number;
}

export function parseSchemaList(value?: string): string[] {
  const schemas = (value ?? 'public,auth,storage')
    .split(',')
    .map((schema) => schema.trim())
    .filter(Boolean);
  return [...new Set(schemas)];
}

export function quoteIdentifier(identifier: string): string {
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(identifier)) {
    throw new Error(`Unsafe SQL identifier: ${identifier}`);
  }
  return `"${identifier.replace(/"/g, '""')}"`;
}

export function qualifiedName(schema: string, table: string): string {
  return `${quoteIdentifier(schema)}.${quoteIdentifier(table)}`;
}

export function buildOrderClause(columns: SourceColumn[], primaryKeyColumns: string[]): string {
  const ordered = primaryKeyColumns.length > 0
    ? primaryKeyColumns
    : columns
      .slice()
      .sort((left, right) => left.ordinalPosition - right.ordinalPosition)
      .map((column) => column.name);
  if (ordered.length === 0) return '';
  return `order by ${ordered.map(quoteIdentifier).join(', ')}`;
}

export function normalizeForJson(value: unknown): unknown {
  if (value instanceof Date) return value.toISOString();
  if (Buffer.isBuffer(value)) {
    return { __type: 'Buffer', base64: value.toString('base64') };
  }
  if (Array.isArray(value)) return value.map((item) => normalizeForJson(item));
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, nested]) => [key, normalizeForJson(nested)])
    );
  }
  return value;
}

export function stableJsonLine(row: Record<string, unknown>): string {
  return `${JSON.stringify(normalizeForJson(row))}\n`;
}

export function sha256Hex(value: string | Buffer): string {
  return createHash('sha256').update(value).digest('hex');
}

export function redactConnectionString(connectionString: string): string {
  try {
    const url = new URL(connectionString);
    if (url.password) url.password = '***';
    if (url.username) url.username = '***';
    return url.toString();
  } catch {
    return '<redacted>';
  }
}

export function exportRelativePath(schema: string, table: string): string {
  return `data/${schema}.${table}.ndjson`;
}
