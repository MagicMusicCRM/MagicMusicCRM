import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import type { PoolClient } from 'pg';
import { buildCrmConfigurationBaseline } from './crm-configuration-baseline';
import { loadLessonSettlementCatalog, assertPlannedLessonSettlementDecision } from './commerce/lesson-settlement-catalog';

const migration = (direction: string) => readFileSync(resolve(__dirname, '../../db/migrations', `0154_retire_partial_miss.${direction}.sql`), 'utf8');

describe('retire partial miss', () => {
  it('disables new decisions, preserves frozen revisions, and is repeatable', async () => {
    const db = new PGlite();
    try {
      await db.exec(`create schema app;
        create table app.crm_configuration_revisions (
          id uuid primary key default gen_random_uuid(), branch_id uuid, version bigint not null,
          patch jsonb not null, effective_snapshot jsonb not null, impact jsonb not null, reason text not null);
        create table app.crm_configuration_drafts (snapshot jsonb not null);`);
      const snapshot = buildCrmConfigurationBaseline([]);
      const partial = snapshot.lessonSettlementTypes.find(item => item.stableKey === 'partially_paid_miss')!;
      expect(partial.active).toBe(false);
      partial.active = true;
      const seeded = await db.query<{id: string}>(`insert into app.crm_configuration_revisions
        (version, patch, effective_snapshot, impact, reason) values (1,$1,$1,'{}','seed') returning id`, [JSON.stringify(snapshot)]);
      await db.query('insert into app.crm_configuration_drafts values ($1)', [JSON.stringify(snapshot)]);
      await db.exec(migration('up'));
      await db.exec(migration('up'));
      const revisions = await db.query<{effective_snapshot: typeof snapshot}>('select effective_snapshot from app.crm_configuration_revisions order by version');
      expect(revisions.rows).toHaveLength(2);
      expect(revisions.rows[0].effective_snapshot).toEqual(snapshot);
      const expected = structuredClone(snapshot);
      expected.lessonSettlementTypes.find(item => item.stableKey === 'partially_paid_miss')!.active = false;
      expect(revisions.rows[1].effective_snapshot).toEqual(expected);
      const drafts = await db.query<{snapshot: typeof snapshot}>('select snapshot from app.crm_configuration_drafts');
      expect(drafts.rows[0].snapshot).toEqual(expected);
      const client = db as unknown as PoolClient;
      const current = await loadLessonSettlementCatalog(client, 'branch');
      const decision = { settlementTypeKey: 'partially_paid_miss', clientDecisions: [], teacherCompensationRuleKey: 'percent' };
      expect(() => assertPlannedLessonSettlementDecision(current, decision)).toThrow();
      const frozen = await loadLessonSettlementCatalog(client, 'branch', {
        settlementRevisionId: seeded.rows[0].id, compensationRevisionId: seeded.rows[0].id,
      });
      expect(() => assertPlannedLessonSettlementDecision(frozen, decision)).not.toThrow();
      expect(() => assertPlannedLessonSettlementDecision(current, { ...decision, settlementTypeKey: 'partially_paid_lesson' })).not.toThrow();
      await expect(db.exec(migration('down'))).rejects.toThrow('immutable');
    } finally { await db.close(); }
  });
});
