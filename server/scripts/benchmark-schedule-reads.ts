import { Pool } from 'pg';
import { createHash, randomUUID } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { ScheduleReadService } from '../src/crm/schedule/schedule-read.service';
import { CrmPolicy } from '../src/crm/crm.policy';
import { DatabaseService } from '../src/db/database.service';

async function main() {
  const url = process.env.V4_PLATFORM_TEST_DATABASE_URL;
  if (!url) throw new Error('V4_PLATFORM_TEST_DATABASE_URL is required');
  const target = new URL(url);
  if (!['127.0.0.1', 'localhost'].includes(target.hostname) || !target.pathname.includes('audit_fix')) {
    throw new Error('Requires the isolated local audit database');
  }
  const pool = new Pool({ connectionString: url });
  const client = await pool.connect();
  try {
    await client.query('begin');
    await client.query("set local statement_timeout = '60s'");
    const actor = { userId: randomUUID(), role: 'director' as const };
    await client.query("insert into app.users(id,email,role) values($1,$2,'director')", [actor.userId, `${actor.userId}@example.test`]);
    await client.query('create temp table perf_lessons (like app.lessons including all) on commit drop');
    await client.query('create temp table perf_reservations (like app.lesson_reservations including all) on commit drop');
    // LIKE copies indexes. Remove only the new access path from this TEMP table
    // so the baseline remains reproducible after the real migration is applied.
    const copied = await client.query(`select indexrelid::regclass::text name from pg_index
      where indrelid='pg_temp.perf_reservations'::regclass
        and pg_get_indexdef(indexrelid) like '%updated_at DESC%'`);
    for (const row of copied.rows) {
      const name = String(row.name).split('.').at(-1)!.replaceAll('"', '');
      await client.query(`drop index pg_temp."${name.replaceAll('"', '""')}"`);
    }
    await client.query(`insert into perf_lessons(id,student_id,teacher_id,room_id,scheduled_at,duration_minutes,status,lifecycle_state)
      select md5('lesson-'||i)::uuid,md5('student-'||(i%500))::uuid,md5('teacher-'||(i%40))::uuid,
        md5('room-'||(i%40))::uuid,'2026-01-01'::timestamptz + (i%365)*interval '1 day' + (i%12)*interval '1 hour',
        45, case when i%10=0 then 'cancelled' else 'planned' end,
        case when i%10=0 then 'cancelled' else 'scheduled' end
      from generate_series(1,60000) i`);
    await client.query(`insert into perf_reservations(id,lesson_id,subscription_id,units,state,version,origin,created_at,updated_at,terminal_at)
      select md5('reservation-'||i||'-'||revision)::uuid,md5('lesson-'||i)::uuid,md5('subscription-'||i)::uuid,
        1,case when revision=4 then 'reserved' else 'released' end,1,'runtime',
        '2026-01-01'::timestamptz + revision*interval '1 second',
        '2026-01-01'::timestamptz + revision*interval '1 second',
        case when revision<>4 then '2026-01-02'::timestamptz end
      from generate_series(1,60000) i cross join generate_series(1,4) revision`);
    await client.query('analyze perf_lessons');
    await client.query('analyze perf_reservations');
    const captured: { sql: string; params: unknown[] }[] = [];
    const schedule = new ScheduleReadService({ query: async (sql: string, params: unknown[]) => {
      captured.push({ sql: sql.replaceAll('app.lessons', 'pg_temp.perf_lessons').replaceAll('app.lesson_reservations', 'pg_temp.perf_reservations'), params });
      return { rows: [] };
    }} as unknown as DatabaseService, new CrmPolicy());
    await schedule.getScheduleMatrix(actor, { from: '2026-05-01T00:00:00Z', to: '2026-05-08T00:00:00Z', limit: 300 });
    await schedule.listLessons(actor, { studentId: (await client.query("select md5('student-1')::uuid id")).rows[0].id, limit: 100 });
    const evidence: Record<string, unknown> = { fixture: { lessons: 60000, reservations: 240000 }, samples: [] };
    // Keep the original correlated predicate as an explicit benchmark variant.
    // Production SQL is always obtained from the live service above.
    const optimizedStudentSql = captured[1].sql;
    const originalStudentSql = optimizedStudentSql.replace(
      /or l\.group_id = any\(array\(\s*select filter_gs\.group_id\s*from app\.group_students filter_gs\s*where filter_gs\.student_id = \$3\s*and filter_gs\.left_at is null\s*\)\)/,
      `or exists (select 1 from app.group_students filter_gs where filter_gs.group_id=l.group_id
        and filter_gs.student_id=$3 and filter_gs.left_at is null)`);
    if (originalStudentSql === optimizedStudentSql) throw new Error('Original predicate benchmark no longer matches live SQL');
    captured[1].sql = originalStudentSql;
    const sample = async (label: string) => {
      for (const [index, item] of captured.entries()) {
        const plan = (await client.query('explain (analyze,buffers,format json) '+item.sql, item.params)).rows[0]['QUERY PLAN'][0];
        const rows = (await client.query(item.sql, item.params)).rows;
        const digest = createHash('sha256').update(JSON.stringify(rows)).digest('hex');
        (evidence.samples as unknown[]).push({ label, scenario: index===0?'matrix':'studentLessons', digest, plan });
        console.log(JSON.stringify({ label, scenario:index===0?'matrix':'studentLessons', executionMs:plan['Execution Time'], planningMs:plan['Planning Time'], buffers:plan.Plan['Shared Hit Blocks']+plan.Plan['Local Hit Blocks'] }));
      }
    };
    await sample('baseline-warmup');
    for (let i=0;i<5;i++) await sample('baseline');
    const migration = readFileSync('db/migrations/0153_lesson_reservation_read_index.up.sql','utf8')
      .replace('on app.lesson_reservations', 'on pg_temp.perf_reservations');
    await client.query(migration);
    await sample('indexed-warmup');
    for (let i=0;i<5;i++) await sample('indexed');
    captured[1].sql = optimizedStudentSql;
    await sample('optimized-warmup');
    for (let i=0;i<5;i++) await sample('optimized');
    for (const scenario of ['matrix', 'studentLessons']) {
      const digests = new Set((evidence.samples as {scenario:string;digest:string}[])
        .filter(row=>row.scenario===scenario).map(row=>row.digest));
      if (digests.size!==1) throw new Error(`Result parity failed: ${scenario}`);
    }
    writeFileSync('../outputs/application-audit-2026-09-05/database-schedule-plans.json', JSON.stringify(evidence, null, 2));
  } finally {
    await client.query('rollback');
    client.release();
    await pool.end();
  }
}
void main().catch(error => { console.error(error.message); process.exitCode=1; });
