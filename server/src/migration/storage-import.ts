import { mkdirSync, writeFileSync } from 'node:fs';
import { createReadStream } from 'node:fs';
import { createInterface } from 'node:readline';
import { dirname, join, resolve } from 'node:path';
import { writeFile } from 'node:fs/promises';
import { Pool, PoolClient } from 'pg';
import { asString, deterministicUuid } from './v3-import-utils';
import {
  LegacyFileMapEntry,
  buildLegacyKeys,
  buildLegacyStorageKey,
  inferMimeType,
  inferPurpose,
  inferSizeBytes,
  sha256Buffer,
  sanitizePathSegment
} from './storage-import-utils';

interface StorageImportConfig {
  exportDir: string;
  supabaseUrl: string;
  serviceRoleKey: string;
  storageRoot: string;
  connectionString?: string;
  dryRun: boolean;
  limit?: number;
}

interface StorageObjectRow {
  id?: string;
  bucket_id?: string;
  name?: string;
  metadata?: unknown;
  owner?: string;
  created_at?: string;
  updated_at?: string;
}

interface StorageImportReport {
  importId: string;
  startedAt: string;
  finishedAt: string;
  mode: 'manifest-only' | 'dry-run' | 'live';
  source: {
    exportDir: string;
    supabaseUrl: string;
  };
  target: {
    storageRoot: string;
    database?: string;
  };
  totals: {
    sourceObjects: number;
    downloadedObjects: number;
    insertedOrSkippedRows: number;
    skippedObjects: number;
    bytesWritten: number;
    warnings: number;
  };
  files: LegacyFileMapEntry[];
  skipped: Array<{ bucketId?: string; name?: string; reason: string }>;
  warnings: string[];
}

class StorageImportPipeline {
  constructor(private readonly config: StorageImportConfig) {}

  async run(): Promise<StorageImportReport> {
    const startedAt = new Date().toISOString();
    const importId = `storage-import-${startedAt.replace(/[:.]/g, '-')}`;
    const objects = await this.readStorageObjects();
    const files: LegacyFileMapEntry[] = [];
    const skipped: StorageImportReport['skipped'] = [];
    const warnings: string[] = [];
    let bytesWritten = 0;

    const selected = this.config.limit ? objects.slice(0, this.config.limit) : objects;
    for (const object of selected) {
      const bucketId = asString(object.bucket_id);
      const name = asString(object.name);
      const objectId = asString(object.id) ?? (bucketId && name ? deterministicUuid('legacy-storage-object', `${bucketId}/${name}`) : undefined);
      if (!bucketId || !name || !objectId) {
        skipped.push({ bucketId, name, reason: 'Missing bucket_id, name or id.' });
        continue;
      }

      const downloaded = await this.downloadObject(bucketId, name);
      if (!downloaded) {
        skipped.push({ bucketId, name, reason: 'Download failed or object was unavailable.' });
        continue;
      }

      const mimeType = inferMimeType(object.metadata, name);
      const storageKey = buildLegacyStorageKey(bucketId, objectId, name);
      const targetPath = join(this.config.storageRoot, storageKey);
      mkdirSync(dirname(targetPath), { recursive: true });
      await writeFile(targetPath, downloaded);
      bytesWritten += downloaded.length;

      const entry: LegacyFileMapEntry = {
        id: objectId,
        bucketId,
        name,
        storageKey,
        purpose: inferPurpose(bucketId, name, mimeType),
        originalName: sanitizePathSegment(name),
        mimeType,
        sizeBytes: inferSizeBytes(object.metadata, downloaded.length),
        sha256: sha256Buffer(downloaded),
        legacyKeys: buildLegacyKeys(this.config.supabaseUrl, bucketId, name)
      };
      files.push(entry);
    }

    let insertedOrSkippedRows = 0;
    if (this.config.connectionString) {
      insertedOrSkippedRows = await this.insertFileRows(files);
    } else {
      warnings.push('TARGET_DATABASE_URL/DATABASE_URL is not set; file_objects insert was skipped and manifest-only output was generated.');
    }

    const report: StorageImportReport = {
      importId,
      startedAt,
      finishedAt: new Date().toISOString(),
      mode: this.config.connectionString ? (this.config.dryRun ? 'dry-run' : 'live') : 'manifest-only',
      source: {
        exportDir: this.config.exportDir,
        supabaseUrl: this.config.supabaseUrl.replace(/\/+$/, '')
      },
      target: {
        storageRoot: this.config.storageRoot,
        database: this.config.connectionString ? this.redactConnectionString(this.config.connectionString) : undefined
      },
      totals: {
        sourceObjects: objects.length,
        downloadedObjects: files.length,
        insertedOrSkippedRows,
        skippedObjects: skipped.length,
        bytesWritten,
        warnings: warnings.length
      },
      files,
      skipped,
      warnings
    };
    this.writeReport(report);
    return report;
  }

  private async readStorageObjects(): Promise<StorageObjectRow[]> {
    const file = join(this.config.exportDir, 'storage', 'objects.ndjson');
    const rows: StorageObjectRow[] = [];
    const reader = createInterface({
      input: createReadStream(file, { encoding: 'utf8' }),
      crlfDelay: Infinity
    });
    for await (const line of reader) {
      const trimmed = line.trim();
      if (!trimmed) continue;
      rows.push(JSON.parse(trimmed) as StorageObjectRow);
    }
    return rows;
  }

  private async downloadObject(bucketId: string, name: string): Promise<Buffer | undefined> {
    const encodedPath = name.split('/').map(encodeURIComponent).join('/');
    const url = `${this.config.supabaseUrl.replace(/\/+$/, '')}/storage/v1/object/${encodeURIComponent(bucketId)}/${encodedPath}`;
    const response = await fetch(url, {
      headers: {
        authorization: `Bearer ${this.config.serviceRoleKey}`,
        apikey: this.config.serviceRoleKey
      }
    });
    if (!response.ok) return undefined;
    return Buffer.from(await response.arrayBuffer());
  }

  private async insertFileRows(files: LegacyFileMapEntry[]): Promise<number> {
    const pool = new Pool({
      connectionString: this.config.connectionString,
      max: 2,
      connectionTimeoutMillis: 10_000,
      idleTimeoutMillis: 30_000
    });
    const client = await pool.connect();
    try {
      await client.query('begin');
      let insertedOrSkippedRows = 0;
      for (const file of files) {
        await this.insertFileRow(client, file);
        insertedOrSkippedRows += 1;
      }
      if (this.config.dryRun) await client.query('rollback');
      else await client.query('commit');
      return insertedOrSkippedRows;
    } catch (error) {
      await client.query('rollback');
      throw error;
    } finally {
      client.release();
      await pool.end();
    }
  }

  private async insertFileRow(client: PoolClient, file: LegacyFileMapEntry): Promise<void> {
    await client.query(
      `
        insert into app.file_objects (
          id, owner_user_id, owner_type, owner_id, purpose, original_name,
          mime_type, size_bytes, storage_key, sha256, created_by
        )
        values ($1, null, null, null, $2::app.file_purpose, $3, $4, $5, $6, $7, null)
        on conflict (id) do nothing
      `,
      [
        file.id,
        file.purpose,
        file.originalName,
        file.mimeType,
        file.sizeBytes,
        file.storageKey,
        file.sha256
      ]
    );
  }

  private writeReport(report: StorageImportReport): void {
    writeFileSync(
      join(this.config.exportDir, 'file-import-report.json'),
      `${JSON.stringify(report, null, 2)}\n`,
      'utf8'
    );
  }

  private redactConnectionString(connectionString: string): string {
    try {
      const url = new URL(connectionString);
      if (url.username) url.username = '***';
      if (url.password) url.password = '***';
      return url.toString();
    } catch {
      return '<redacted>';
    }
  }
}

function parseConfig(): StorageImportConfig {
  const supabaseUrl = process.env.SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl) throw new Error('SUPABASE_URL is required for storage import.');
  if (!serviceRoleKey) throw new Error('SUPABASE_SERVICE_ROLE_KEY is required for storage import.');
  const limit = process.env.STORAGE_IMPORT_LIMIT ? Number(process.env.STORAGE_IMPORT_LIMIT) : undefined;
  return {
    exportDir: resolve(process.env.SUPABASE_EXPORT_DIR ?? 'exports/supabase/latest'),
    supabaseUrl,
    serviceRoleKey,
    storageRoot: resolve(process.env.FILE_STORAGE_ROOT ?? 'storage'),
    connectionString: process.env.TARGET_DATABASE_URL ?? process.env.DATABASE_URL,
    dryRun: (process.env.MIGRATION_DRY_RUN ?? 'true').toLowerCase() !== 'false',
    limit: Number.isFinite(limit) && limit! > 0 ? limit : undefined
  };
}

if (require.main === module) {
  const config = parseConfig();
  const pipeline = new StorageImportPipeline(config);
  pipeline.run()
    .then((report) => {
      // eslint-disable-next-line no-console
      console.log(JSON.stringify({
        importId: report.importId,
        mode: report.mode,
        sourceObjects: report.totals.sourceObjects,
        downloadedObjects: report.totals.downloadedObjects,
        skippedObjects: report.totals.skippedObjects,
        bytesWritten: report.totals.bytesWritten,
        warnings: report.totals.warnings,
        report: join(config.exportDir, 'file-import-report.json')
      }, null, 2));
    })
    .catch((error: Error) => {
      // eslint-disable-next-line no-console
      console.error(error.message);
      process.exitCode = 1;
    });
}

export { StorageImportPipeline, parseConfig };
