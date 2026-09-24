import { PGlite } from '@electric-sql/pglite';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';

describe('0161 notification preference repair', () => {
  it('restores missing rows and preserves operator settings on repeat', async () => {
    const db = new PGlite();
    try {
      await db.exec(`
        create schema app;
        create table app.notification_preferences (
          role text not null, event_type text not null,
          enabled boolean not null, channels text[] not null,
          unique (role, event_type)
        );
        insert into app.notification_preferences (role, event_type, enabled, channels)
        values ('manager', 'new_lead', false, array['in_app']);
      `);
      const sql = await readFile(
        resolve(process.cwd(), 'db/migrations/0161_restore_notification_preferences.up.sql'),
        'utf8'
      );
      await db.exec(sql);
      await db.exec(sql);
      const rows = (await db.query<{
        role: string; event_type: string; enabled: boolean; channels: string[]
      }>(`select role, event_type, enabled, channels
          from app.notification_preferences order by role, event_type`)).rows;
      expect(rows).toHaveLength(20);
      expect(rows.find((row) => row.role === 'manager' && row.event_type === 'new_lead'))
        .toEqual({ role: 'manager', event_type: 'new_lead', enabled: false, channels: ['in_app'] });
      expect(rows.find((row) => row.role === 'admin' && row.event_type === 'new_lead'))
        .toEqual({ role: 'admin', event_type: 'new_lead', enabled: true, channels: ['in_app', 'push'] });
      expect(rows.find((row) => row.role === 'teacher' && row.event_type === 'new_lead')?.enabled)
        .toBe(false);
    } finally {
      await db.close();
    }
  }, 30_000);
});
