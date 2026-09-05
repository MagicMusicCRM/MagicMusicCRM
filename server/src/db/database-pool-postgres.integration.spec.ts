import { ConfigService } from '@nestjs/config';
import { DatabaseService } from './database.service';
import { newRequestPerformance, requestPerformance } from '../common/observability/request-performance';

const url=process.env.V4_PLATFORM_TEST_DATABASE_URL;
(url?describe:describe.skip)('configured database pool',()=>{
  it('limits six concurrent HTTP-context queries to two physical connections',async()=>{
    const target=new URL(url!);
    if(!['localhost','127.0.0.1'].includes(target.hostname)||!target.pathname.includes('audit_fix')) {
      throw new Error('Requires the isolated local audit database');
    }
    const db=new DatabaseService(new ConfigService({DATABASE_URL:url,DATABASE_POOL_MAX:2}));
    try {
      const rows=await Promise.all(Array.from({length:6},(_,i)=>requestPerformance.run(
        newRequestPerformance(`pool-${i}`),()=>db.query('select pg_backend_pid() pid,pg_sleep(0.02)'))));
      expect(new Set(rows.map(row=>row.rows[0].pid)).size).toBe(2);
      expect((await db.query('select 42 value')).rows[0].value).toBe(42);
    } finally {await db.onModuleDestroy();}
  });
});
