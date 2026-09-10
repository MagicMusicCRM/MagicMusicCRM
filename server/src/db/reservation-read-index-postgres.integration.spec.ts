import { Pool } from 'pg';
import { readFileSync } from 'node:fs';

const url=process.env.V4_PLATFORM_TEST_DATABASE_URL;
(url?describe:describe.skip)('reservation read index migration',()=>{
  it('preserves reserved-first ordering, timestamp ties and historical-only reads through up/down',async()=>{
    const target=new URL(url!);
    if(!['localhost','127.0.0.1'].includes(target.hostname)||!target.pathname.includes('audit_fix')) throw new Error('Isolated database required');
    const pool=new Pool({connectionString:url});
    const c=await pool.connect();
    try {
      await c.query('begin');
      await c.query('create temp table reservation_index_test(like app.lesson_reservations including defaults including constraints) on commit drop');
      await c.query(`insert into reservation_index_test(id,lesson_id,subscription_id,units,state,version,origin,created_at,updated_at,terminal_at)
        select ('00000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
          md5(case when i<=3 then 'with-reserved' else 'history-only' end)::uuid,
          md5('subscription')::uuid,1,case when i=1 then 'reserved' else 'released' end,1,'runtime',
          '2026-01-01'::timestamptz,'2026-01-01'::timestamptz + case when i=1 then interval '0 days' else interval '1 day' end,
          case when i<>1 then now() end from generate_series(1,5) i`);
      const sql=`select distinct on (lesson_id) lesson_id,id,state from reservation_index_test
        order by lesson_id,(state='reserved') desc,updated_at desc,id desc`;
      const before=(await c.query(sql)).rows;
      const up=readFileSync('db/migrations/0153_lesson_reservation_read_index.up.sql','utf8')
        .replace('on app.lesson_reservations','on pg_temp.reservation_index_test');
      await c.query(up);
      expect((await c.query(sql)).rows).toEqual(before);
      expect(before.map(row=>row.id).sort()).toEqual([
        '00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000005']);
      const down=readFileSync('db/migrations/0153_lesson_reservation_read_index.down.sql','utf8')
        .replace('app.lesson_reservations_current_read_idx','pg_temp.lesson_reservations_current_read_idx');
      await c.query(down);
      expect((await c.query(sql)).rows).toEqual(before);
    } finally {await c.query('rollback');c.release();await pool.end();}
  });
});
