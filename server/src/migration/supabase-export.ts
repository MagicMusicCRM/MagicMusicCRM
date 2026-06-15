import { createHash } from 'node:crypto';
import { createWriteStream, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { Pool } from 'pg';
import {
  buildOrderClause,
  exportRelativePath,
  parseSchemaList,
  qualifiedName,
  redactConnectionString,
  stableJsonLine
} from './supabase-export-utils';

interface SourceTable {
  schema: string;
  table: string;
}

interface SourceColumn {
  name: string;
  dataType: string;
  udtName: string;
  isNullable: boolean;
  ordinalPosition: number;
}

interface TableExportReport {
  schema: string;
  table: string;
  columns: SourceColumn[];
  primaryKeyColumns: string[];
  rowCount: number;
  checksumSha256: string;
  file: string;
}

interface StorageManifestReport {
  available: boolean;
  objectCount: number;
  checksumSha256?: string;
  file?: string;
  buckets: Array<{ bucketId: string; objectCount: number }>;
}

interface ExportReport {
  exportId: string;
  startedAt: string;
  finishedAt: string;
  source: {
    connectionString: string;
    schemas: string[];
  };
  tables: TableExportReport[];
  storage: StorageManifestReport;
  warnings: string[];
}

interface ExportConfig {
  connectionString: string;
  outputDir: string;
  schemas: string[];
  pageSize: number;
}

class SupabaseExportPipeline {
  private readonly pool: Pool;
  private readonly warnings: string[] = [];

  constructor(private readonly config: ExportConfig) {
    this.pool = new Pool({
      connectionString: config.connectionString,
      max: 3,
      connectionTimeoutMillis: 10_000,
      idleTimeoutMillis: 30_000
    });
  }

  async run(): Promise<ExportReport> {
    const startedAt = new Date().toISOString();
    const exportId = `supabase-export-${startedAt.replace(/[:.]/g, '-')}`;
    mkdirSync(this.config.outputDir, { recursive: true });
    mkdirSync(join(this.config.outputDir, 'data'), { recursive: true });
    mkdirSync(join(this.config.outputDir, 'schema'), { recursive: true });
    mkdirSync(join(this.config.outputDir, 'storage'), { recursive: true });

    try {
      const tables = await this.listTables();
      const tableReports: TableExportReport[] = [];
      const schemaSnapshot: Array<SourceTable & { columns: SourceColumn[]; primaryKeyColumns: string[] }> = [];

      for (const table of tables) {
        const columns = await this.listColumns(table);
        const primaryKeyColumns = await this.listPrimaryKeyColumns(table);
        schemaSnapshot.push({ ...table, columns, primaryKeyColumns });
        tableReports.push(await this.exportTable(table, columns, primaryKeyColumns));
      }

      writeFileSync(
        join(this.config.outputDir, 'schema', 'tables.json'),
        `${JSON.stringify(schemaSnapshot, null, 2)}\n`,
        'utf8'
      );

      const storage = await this.exportStorageManifest();
      const report: ExportReport = {
        exportId,
        startedAt,
        finishedAt: new Date().toISOString(),
        source: {
          connectionString: redactConnectionString(this.config.connectionString),
          schemas: this.config.schemas
        },
        tables: tableReports,
        storage,
        warnings: this.warnings
      };

      writeFileSync(
        join(this.config.outputDir, 'export-report.json'),
        `${JSON.stringify(report, null, 2)}\n`,
        'utf8'
      );
      return report;
    } finally {
      await this.pool.end();
    }
  }

  private async listTables(): Promise<SourceTable[]> {
    const result = await this.pool.query<{
      table_schema: string;
      table_name: string;
    }>(
      `
        select table_schema, table_name
        from information_schema.tables
        where table_type = 'BASE TABLE'
          and table_schema = any($1::text[])
        order by table_schema, table_name
      `,
      [this.config.schemas]
    );
    if (result.rows.length === 0) {
      this.warnings.push('No source tables found for selected schemas.');
    }
    return result.rows.map((row) => ({
      schema: row.table_schema,
      table: row.table_name
    }));
  }

  private async listColumns(table: SourceTable): Promise<SourceColumn[]> {
    const result = await this.pool.query<{
      column_name: string;
      data_type: string;
      udt_name: string;
      is_nullable: string;
      ordinal_position: number;
    }>(
      `
        select column_name, data_type, udt_name, is_nullable, ordinal_position
        from information_schema.columns
        where table_schema = $1 and table_name = $2
        order by ordinal_position
      `,
      [table.schema, table.table]
    );
    return result.rows.map((row) => ({
      name: row.column_name,
      dataType: row.data_type,
      udtName: row.udt_name,
      isNullable: row.is_nullable === 'YES',
      ordinalPosition: Number(row.ordinal_position)
    }));
  }

  private async listPrimaryKeyColumns(table: SourceTable): Promise<string[]> {
    const result = await this.pool.query<{ column_name: string }>(
      `
        select kcu.column_name
        from information_schema.table_constraints tc
        join information_schema.key_column_usage kcu
          on kcu.constraint_schema = tc.constraint_schema
         and kcu.constraint_name = tc.constraint_name
         and kcu.table_schema = tc.table_schema
         and kcu.table_name = tc.table_name
        where tc.constraint_type = 'PRIMARY KEY'
          and tc.table_schema = $1
          and tc.table_name = $2
        order by kcu.ordinal_position
      `,
      [table.schema, table.table]
    );
    return result.rows.map((row) => row.column_name);
  }

  private async exportTable(
    table: SourceTable,
    columns: SourceColumn[],
    primaryKeyColumns: string[]
  ): Promise<TableExportReport> {
    const relativePath = exportRelativePath(table.schema, table.table);
    const outputPath = join(this.config.outputDir, relativePath);
    mkdirSync(dirname(outputPath), { recursive: true });
    const stream = createWriteStream(outputPath, { encoding: 'utf8' });
    const hash = createHash('sha256');
    const orderClause = buildOrderClause(columns, primaryKeyColumns);
    let offset = 0;
    let rowCount = 0;

    try {
      while (true) {
        const result = await this.pool.query<Record<string, unknown>>(
          `
            select *
            from ${qualifiedName(table.schema, table.table)}
            ${orderClause}
            limit $1 offset $2
          `,
          [this.config.pageSize, offset]
        );
        if (result.rows.length === 0) break;
        for (const row of result.rows) {
          const line = stableJsonLine(row);
          hash.update(line);
          stream.write(line);
          rowCount += 1;
        }
        offset += result.rows.length;
      }
    } finally {
      await new Promise<void>((resolveStream, rejectStream) => {
        stream.end((error?: Error | null) => {
          if (error) rejectStream(error);
          else resolveStream();
        });
      });
    }

    return {
      schema: table.schema,
      table: table.table,
      columns,
      primaryKeyColumns,
      rowCount,
      checksumSha256: hash.digest('hex'),
      file: relativePath
    };
  }

  private async exportStorageManifest(): Promise<StorageManifestReport> {
    const exists = await this.pool.query<{ exists: boolean }>(
      "select to_regclass('storage.objects') is not null as exists"
    );
    if (!exists.rows[0]?.exists) {
      this.warnings.push('storage.objects table is unavailable; storage manifest was skipped.');
      return { available: false, objectCount: 0, buckets: [] };
    }

    const relativePath = 'storage/objects.ndjson';
    const outputPath = join(this.config.outputDir, relativePath);
    const stream = createWriteStream(outputPath, { encoding: 'utf8' });
    const hash = createHash('sha256');
    let offset = 0;
    let objectCount = 0;
    const bucketCounts = new Map<string, number>();

    try {
      while (true) {
        const result = await this.pool.query<Record<string, unknown> & { bucket_id: string }>(
          `
            select id, bucket_id, name, owner, metadata, created_at, updated_at, last_accessed_at
            from storage.objects
            order by bucket_id, name, id
            limit $1 offset $2
          `,
          [this.config.pageSize, offset]
        );
        if (result.rows.length === 0) break;
        for (const row of result.rows) {
          const line = stableJsonLine(row);
          hash.update(line);
          stream.write(line);
          objectCount += 1;
          bucketCounts.set(row.bucket_id, (bucketCounts.get(row.bucket_id) ?? 0) + 1);
        }
        offset += result.rows.length;
      }
    } finally {
      await new Promise<void>((resolveStream, rejectStream) => {
        stream.end((error?: Error | null) => {
          if (error) rejectStream(error);
          else resolveStream();
        });
      });
    }

    return {
      available: true,
      objectCount,
      checksumSha256: hash.digest('hex'),
      file: relativePath,
      buckets: [...bucketCounts.entries()]
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([bucketId, count]) => ({ bucketId, objectCount: count }))
    };
  }
}

function loadConfig(): ExportConfig {
  const connectionString = process.env.SUPABASE_DB_URL;
  if (!connectionString) {
    throw new Error('SUPABASE_DB_URL is required for Supabase export.');
  }
  return {
    connectionString,
    outputDir: resolve(process.env.SUPABASE_EXPORT_DIR ?? 'exports/supabase/latest'),
    schemas: parseSchemaList(process.env.SUPABASE_EXPORT_SCHEMAS),
    pageSize: Number(process.env.SUPABASE_EXPORT_PAGE_SIZE ?? '1000')
  };
}

async function main(): Promise<void> {
  const config = loadConfig();
  const pipeline = new SupabaseExportPipeline(config);
  const report = await pipeline.run();
  console.log(
    `Supabase export complete: ${report.tables.length} tables, ${report.storage.objectCount} storage objects -> ${config.outputDir}`
  );
  if (report.warnings.length > 0) {
    for (const warning of report.warnings) console.warn(`warning: ${warning}`);
  }
}

if (require.main === module) {
  main().catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  });
}
