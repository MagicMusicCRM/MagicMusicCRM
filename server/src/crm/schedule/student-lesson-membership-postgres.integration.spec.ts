import { Pool, PoolClient } from 'pg';
import { randomUUID } from 'node:crypto';
import { ScheduleReadService } from './schedule-read.service';
import { CrmPolicy } from '../crm.policy';
import { DatabaseService } from '../../db/database.service';

const url=process.env.V4_PLATFORM_TEST_DATABASE_URL;
(url?describe:describe.skip)('student lesson membership query parity',()=>{
  let pool:Pool, c:PoolClient, service:ScheduleReadService;
  const actor={userId:randomUUID(),role:'director' as const};
  const student=randomUUID(),other=randomUUID(),empty=randomUUID();
  const groups=[randomUUID(),randomUUID(),randomUUID()];
  const lessons=Array.from({length:6},()=>randomUUID());
  let captured:{sql:string;params:unknown[]};
  beforeAll(async()=>{
    const target=new URL(url!);
    if(!['localhost','127.0.0.1'].includes(target.hostname)||!target.pathname.includes('audit_fix')) throw new Error('Isolated database required');
    pool=new Pool({connectionString:url});c=await pool.connect();await c.query('begin');
    await c.query("insert into app.users(id,email,role) values($1,$2,'director')",[actor.userId,`${actor.userId}@example.test`]);
    await c.query('create temp table membership_lessons(like app.lessons including all) on commit drop');
    await c.query('create temp table membership_groups(like app.group_students including all) on commit drop');
    for(const [i,id] of lessons.entries()) {
      await c.query(`insert into membership_lessons(id,student_id,group_id,scheduled_at,duration_minutes,status,lifecycle_state)
        values($1,$2,$3,'2026-07-01'::timestamptz + $4*interval '1 hour',45,'planned',$5)`,
        [id,[0,5].includes(i)?student:i===3?other:null,i===1?groups[0]:i===2?groups[1]:i===4?groups[2]:null,i,i===5?'cancelled':'scheduled']);
    }
    await c.query(`insert into membership_groups(group_id,student_id,left_at) values
      ($1,$4,null),($2,$4,now()),($3,$5,null)`,[...groups,student,other]);
    service=new ScheduleReadService({query:async(sql:string,params:unknown[])=>{
      captured={sql:sql.replaceAll('app.lessons','pg_temp.membership_lessons').replaceAll('app.group_students','pg_temp.membership_groups'),params};
      return c.query(captured.sql,params);
    }} as unknown as DatabaseService,new CrmPolicy());
  });
  afterAll(async()=>{if(c){await c.query('rollback');c.release();}await pool?.end();});
  it.each([['active',student],['other',other],['empty',empty],['unfiltered',undefined]])(
    'matches complete original rows for %s membership',async(_,studentId)=>{
      const result=await service.listLessons(actor,{studentId,limit:100});
      const optimized=(await c.query(captured.sql,captured.params)).rows;
      const old=captured.sql.replace(
        /or l\.group_id = any\(array\(\s*select filter_gs\.group_id\s*from pg_temp\.membership_groups filter_gs\s*where filter_gs\.student_id = \$3\s*and filter_gs\.left_at is null\s*\)\)/,
        `or exists(select 1 from pg_temp.membership_groups filter_gs
          where filter_gs.group_id=l.group_id and filter_gs.student_id=$3 and filter_gs.left_at is null)`);
      expect(old).not.toBe(captured.sql);
      expect(optimized).toEqual((await c.query(old,captured.params)).rows);
      if(studentId===student) expect(result.items.map(item=>item.id)).toEqual([lessons[0],lessons[1]]);
      if(studentId===empty) expect(result.items).toHaveLength(0);
    });
  it('keeps the database role authoritative after a stale director token',async()=>{
    await c.query("update app.users set role='teacher' where id=$1",[actor.userId]);
    expect((await service.listLessons(actor,{studentId:student})).items).toHaveLength(0);
  });
});
