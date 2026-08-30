import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'node:crypto';
import { Pool } from 'pg';
import { AuditPresentationService } from '../audit/audit-presentation.service';
import { ActorContext } from '../common/security/actor-context';
import { DatabaseService } from '../db/database.service';
import { MigrationRunner } from '../db/migration-runner';
import { CrmPolicy } from './crm.policy';
import { DashboardService } from './dashboard.service';

const databaseUrl = process.env.V4_PLATFORM_TEST_DATABASE_URL
  ?? 'postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm';
if (!new Set(['127.0.0.1', 'localhost', '[::1]']).has(new URL(databaseUrl).hostname)) {
  throw new Error('Dashboard activity tests require local PostgreSQL.');
}

jest.setTimeout(120_000);

interface CapturedQuery {
  sql: string;
  params: unknown[];
}

interface ExplainNode {
  'Node Type': string;
  'Relation Name'?: string;
  'Index Name'?: string;
  'Subplan Name'?: string;
  'Index Cond'?: string;
  Plans?: ExplainNode[];
}

function planNodes(root: ExplainNode): ExplainNode[] {
  return [root, ...(root.Plans ?? []).flatMap(planNodes)];
}

describe('DashboardService activity journal (PostgreSQL)', () => {
  let pool: Pool;
  let database: DatabaseService;
  let service: DashboardService;
  let actor: ActorContext;
  let captured: CapturedQuery | null;
  const ids = {
    actor: randomUUID(),
    actorProfile: randomUUID(),
    actorStaff: randomUUID(),
    clientUser: randomUUID(),
    studentProfile: randomUUID(),
    student: randomUUID(),
    task: randomUUID(),
    comment: randomUUID(),
    taskAudit: randomUUID(),
    commentAudit: randomUUID(),
    studentAudit: randomUUID(),
  };
  const commentBody = `PRIVATE-COMMENT-${randomUUID()}`;

  beforeAll(async () => {
    pool = new Pool({ connectionString: databaseUrl });
    await new MigrationRunner(pool).up();
    database = new DatabaseService({
      getOrThrow: () => databaseUrl,
    } as unknown as ConfigService);
    const capturingDatabase = {
      query: async <T extends Record<string, unknown>>(sql: string, params: unknown[] = []) => {
        captured = { sql, params };
        return database.query<T>(sql, params);
      },
    } as unknown as DatabaseService;
    service = new DashboardService(
      capturingDatabase,
      new CrmPolicy(),
      new AuditPresentationService(),
    );
    actor = { userId: ids.actor, role: 'director' };

    await pool.query(
      `insert into app.users (id, email, role, email_verified_at)
       values ($1, $2, 'director', now()), ($3, $4, 'client', now())`,
      [
        ids.actor,
        `dashboard-actor-${ids.actor}@example.test`,
        ids.clientUser,
        `dashboard-client-${ids.clientUser}@example.test`,
      ],
    );
    await pool.query(
      `insert into app.profiles (id, user_id, first_name, last_name)
       values ($1, $2, 'Анна', 'Директор'), ($3, $4, 'Мария', 'Ученица')`,
      [ids.actorProfile, ids.actor, ids.studentProfile, ids.clientUser],
    );
    await pool.query(
      `insert into app.staff_members (id, profile_id, role)
       values ($1, $2, 'director')`,
      [ids.actorStaff, ids.actorProfile],
    );
    await pool.query(
      `insert into app.students (id, profile_id) values ($1, $2)`,
      [ids.student, ids.studentProfile],
    );
    await pool.query(
      `insert into app.shared_tasks (
         id, title, all_day, start_at, created_by
       ) values ($1, 'Позвонить родителю', true, now() + interval '1 day', $2)`,
      [ids.task, ids.actor],
    );
    await pool.query(
      `insert into app.entity_comments (
         id, entity_type, entity_id, author_id, body
       ) values ($1, 'student', $2, $3, $4)`,
      [ids.comment, ids.student, ids.actor, commentBody],
    );
    await pool.query(
      `insert into app.audit_events (
         id, actor_user_id, action, entity_type, entity_id, metadata, created_at
       ) values
       ($1, $2, 'workflow.shared_task_created', 'shared_task', $3, '{}'::jsonb, now()),
       ($4, $2, 'crm.comment_created', 'comment', $5, '{}'::jsonb, now() - interval '1 second'),
       ($6, $2, 'crm.student_updated', 'student', $7, '{}'::jsonb, now() - interval '2 seconds')`,
      [
        ids.taskAudit,
        ids.actor,
        ids.task,
        ids.commentAudit,
        ids.comment,
        ids.studentAudit,
        ids.student,
      ],
    );
  });

  afterAll(async () => {
    if (pool) {
      await pool.query('delete from app.audit_events where id = any($1::uuid[])', [[
        ids.taskAudit,
        ids.commentAudit,
        ids.studentAudit,
      ]]);
      await pool.query('delete from app.entity_comments where id = $1', [ids.comment]);
      await pool.query('delete from app.shared_tasks where id = $1', [ids.task]);
      await pool.query('delete from app.students where id = $1', [ids.student]);
      await pool.query('delete from app.staff_members where id = $1', [ids.actorStaff]);
      await pool.query('delete from app.profiles where id = any($1::uuid[])', [[
        ids.actorProfile,
        ids.studentProfile,
      ]]);
      await pool.query('delete from app.users where id = any($1::uuid[])', [[
        ids.actor,
        ids.clientUser,
      ]]);
    }
    if (database) await database.onModuleDestroy();
    if (pool) await pool.end();
  });

  it('matches the task presentation alias and never returns comment bodies', async () => {
    const taskResult = await service.listActivityLog(actor, {
      entityType: 'task',
      entityId: ids.task,
      limit: 100,
    });
    expect(taskResult.items).toEqual([
      expect.objectContaining({
        actionKey: 'workflow.shared_task_created',
        target: expect.objectContaining({
          type: 'task',
          id: ids.task,
          displayName: 'Позвонить родителю',
        }),
      }),
    ]);

    const commentResult = await service.listActivityLog(actor, {
      entityType: 'comment',
      entityId: ids.comment,
      limit: 100,
    });
    expect(commentResult.items).toEqual([
      expect.objectContaining({
        actionKey: 'crm.comment_created',
        target: expect.objectContaining({
          type: 'comment',
          id: ids.comment,
          displayName: null,
        }),
      }),
    ]);
    expect(JSON.stringify(commentResult)).not.toContain(commentBody);
  });

  it('limits audit candidates before target joins and keeps UUID PK lookup usable', async () => {
    await service.listActivityLog(actor, { limit: 25 });
    expect(captured).not.toBeNull();

    const client = await pool.connect();
    try {
      await client.query('begin');
      await client.query('set local enable_seqscan = off');
      const explained = await client.query<{ 'QUERY PLAN': Array<{ Plan: ExplainNode }> }>(
        `explain (format json) ${captured!.sql}`,
        captured!.params,
      );
      const root = explained.rows[0]!['QUERY PLAN'][0]!.Plan;
      const nodes = planNodes(root);
      const candidatePlan = nodes.find(
        (node) => node['Subplan Name'] === 'CTE candidate_events',
      );
      expect(candidatePlan?.['Node Type']).toBe('Limit');
      expect(planNodes(candidatePlan!).some(
        (node) => node['Relation Name'] === 'students',
      )).toBe(false);

      const studentLookups = nodes.filter(
        (node) => node['Relation Name'] === 'students',
      );
      expect(studentLookups.some(
        (node) => /Index/.test(node['Node Type'])
          && node['Index Cond']?.includes('target_entity_uuid') === true,
      )).toBe(true);
      expect(captured!.sql).toContain('target_student_record.id = ae.target_entity_uuid');
      await client.query('rollback');
    } finally {
      client.release();
    }
  });
});
