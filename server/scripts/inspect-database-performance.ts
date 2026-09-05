import { Pool } from 'pg';

/** Metadata-only, read-only diagnostics. Never resets statistics or enables extensions. */
async function main() {
  const url = process.env.DATABASE_DIAGNOSTICS_URL;
  if (!url) throw new Error('Set DATABASE_DIAGNOSTICS_URL explicitly; no application URL fallback is used');
  const pool = new Pool({ connectionString: url, max: 1, connectionTimeoutMillis: 5000 });
  const client = await pool.connect();
  let committed = false;
  try {
    await client.query('begin read only');
    await client.query("set local statement_timeout='5s'");
    const settings = (await client.query(`select current_setting('server_version') version,
      current_setting('max_connections') max_connections,
      current_setting('shared_preload_libraries') preload,
      (select stats_reset from pg_stat_database where datname=current_database()) stats_reset`)).rows[0];
    const tables = (await client.query(`select relname, n_live_tup, n_dead_tup, seq_scan, idx_scan,
      last_analyze, last_autoanalyze, last_autovacuum,
      pg_total_relation_size(relid)::text total_bytes
      from pg_stat_user_tables where schemaname='app'
      order by pg_total_relation_size(relid) desc limit 20`)).rows;
    const indexes = (await client.query(`select relname,indexrelname,idx_scan,
      pg_relation_size(indexrelid)::text bytes from pg_stat_user_indexes
      where schemaname='app' order by pg_relation_size(indexrelid) desc limit 20`)).rows;
    const extension = (await client.query(`select n.nspname schema from pg_extension e
      join pg_namespace n on n.oid=e.extnamespace where e.extname='pg_stat_statements'`)).rows[0];
    let statements: unknown[] = [];
    const enabled = Boolean(extension && settings.preload.split(',').map((s: string)=>s.trim()).includes('pg_stat_statements'));
    if (enabled) {
      const schema = String(extension.schema).replaceAll('"','""');
      statements = (await client.query(`select queryid::text, calls::text, total_exec_time,
        mean_exec_time, rows::text, shared_blks_hit::text,shared_blks_read::text,
        temp_blks_read::text,temp_blks_written::text
        from "${schema}".pg_stat_statements where dbid=(select oid from pg_database where datname=current_database())
        order by total_exec_time desc limit 20`)).rows;
    }
    await client.query('commit');
    committed = true;
    console.log(JSON.stringify({ capturedAt: new Date().toISOString(), settings,
      pgStatStatements: enabled ? 'available' : 'not_enabled', tables,indexes,statements }, null, 2));
  } finally {
    if (!committed) await client.query('rollback');
    client.release();
    await pool.end();
  }
}
void main().catch(error => { console.error(error.message); process.exitCode=1; });
