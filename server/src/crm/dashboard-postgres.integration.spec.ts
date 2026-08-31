import { randomUUID } from 'node:crypto';
import { Pool, PoolClient, QueryConfig, QueryResultRow } from 'pg';
import { AuditPresentationService } from '../audit/audit-presentation.service';
import { ActorContext } from '../common/security/actor-context';
import { DatabaseService } from '../db/database.service';
import { MigrationRunner } from '../db/migration-runner';
import { CrmPolicy } from './crm.policy';
import { DashboardService } from './dashboard.service';

const databaseUrl = process.env.V4_PLATFORM_TEST_DATABASE_URL
  ?? 'postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm';
const parsedDatabaseUrl = new URL(databaseUrl);

function isApprovedDashboardTestDatabase(url: URL): boolean {
  const databaseName = url.pathname.replace(/^\//, '');
  return new Set(['127.0.0.1', 'localhost', '[::1]']).has(url.hostname)
    && (
      databaseName === 'magiccrm'
      || databaseName.toLowerCase().includes('test')
      || /^magiccrm_v7_prodlike_audit_[0-9]{14}_[a-f0-9]{8}$/.test(databaseName)
    );
}

if (!isApprovedDashboardTestDatabase(parsedDatabaseUrl)) {
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

interface FixtureCounts {
  auditEvents: number;
  comments: number;
  tasks: number;
  students: number;
  staffMembers: number;
  profiles: number;
  users: number;
}

interface CleanupEvidence {
  resolved: FixtureCounts;
  deleted: FixtureCounts;
}

function planNodes(root: ExplainNode): ExplainNode[] {
  return [root, ...(root.Plans ?? []).flatMap(planNodes)];
}

async function staleDashboardFixtureCleanup(client: PoolClient): Promise<CleanupEvidence> {
  await client.query('begin');
  try {
    const userIds = (await client.query<{ id: string }>(
      `select id::text as id
       from app.users
       where email ~ '^dashboard-(actor|client)-[0-9a-f-]{36}@example[.]test$'`,
    )).rows.map((row) => row.id);
    const profileIds = (await client.query<{ id: string }>(
      'select id::text as id from app.profiles where user_id = any($1::uuid[])',
      [userIds],
    )).rows.map((row) => row.id);
    const staffIds = (await client.query<{ id: string }>(
      'select id::text as id from app.staff_members where profile_id = any($1::uuid[])',
      [profileIds],
    )).rows.map((row) => row.id);
    const studentIds = (await client.query<{ id: string }>(
      'select id::text as id from app.students where profile_id = any($1::uuid[])',
      [profileIds],
    )).rows.map((row) => row.id);
    const commentIds = (await client.query<{ id: string }>(
      `select id::text as id
       from app.entity_comments
       where body ~ '^PRIVATE-COMMENT-[0-9a-f-]{36}$'
         and author_id = any($1::uuid[])
         and entity_id = any($2::uuid[])`,
      [userIds, studentIds],
    )).rows.map((row) => row.id);
    const taskIds = (await client.query<{ id: string }>(
      `select id::text as id
       from app.shared_tasks
       where created_by = any($1::uuid[])
         and (
           title ~ '^DASHBOARD-TEST-TASK-[0-9a-f-]{36}$'
           or title = 'Позвонить родителю'
         )`,
      [userIds],
    )).rows.map((row) => row.id);
    const auditIds = (await client.query<{ id: string }>(
      'select id::text as id from app.audit_events where actor_user_id = any($1::uuid[])',
      [userIds],
    )).rows.map((row) => row.id);

    const resolved: FixtureCounts = {
      auditEvents: auditIds.length,
      comments: commentIds.length,
      tasks: taskIds.length,
      students: studentIds.length,
      staffMembers: staffIds.length,
      profiles: profileIds.length,
      users: userIds.length,
    };
    const deleted: FixtureCounts = {
      auditEvents: (await client.query(
        'delete from app.audit_events where id = any($1::uuid[])',
        [auditIds],
      )).rowCount ?? 0,
      comments: (await client.query(
        'delete from app.entity_comments where id = any($1::uuid[])',
        [commentIds],
      )).rowCount ?? 0,
      tasks: (await client.query(
        'delete from app.shared_tasks where id = any($1::uuid[])',
        [taskIds],
      )).rowCount ?? 0,
      students: (await client.query(
        'delete from app.students where id = any($1::uuid[])',
        [studentIds],
      )).rowCount ?? 0,
      staffMembers: (await client.query(
        'delete from app.staff_members where id = any($1::uuid[])',
        [staffIds],
      )).rowCount ?? 0,
      profiles: (await client.query(
        'delete from app.profiles where id = any($1::uuid[])',
        [profileIds],
      )).rowCount ?? 0,
      users: (await client.query(
        'delete from app.users where id = any($1::uuid[])',
        [userIds],
      )).rowCount ?? 0,
    };
    await client.query('commit');
    return { resolved, deleted };
  } catch (error) {
    await client.query('rollback');
    throw error;
  }
}

describe('dashboard PostgreSQL database guard', () => {
  it.each([
    'postgresql://user:pass@127.0.0.1:54329/magiccrm',
    'postgresql://user:pass@localhost:54329/magiccrm_dashboard_test',
    'postgresql://user:pass@127.0.0.1:54329/magiccrm_v7_prodlike_audit_20260831211734_23e8348b',
  ])('accepts approved local database %s', (value) => {
    expect(isApprovedDashboardTestDatabase(new URL(value))).toBe(true);
  });

  it.each([
    'postgresql://user:pass@database.internal:54329/magiccrm_v7_prodlike_audit_20260831211734_23e8348b',
    'postgresql://user:pass@127.0.0.1:54329/magiccrm_v7_prodlike_audit_2026083121173_23e8348b',
    'postgresql://user:pass@127.0.0.1:54329/prefix_magiccrm_v7_prodlike_audit_20260831211734_23e8348b',
    'postgresql://user:pass@127.0.0.1:54329/magiccrm_v7_prodlike_audit_20260831211734_23E8348B',
  ])('rejects unapproved database %s', (value) => {
    expect(isApprovedDashboardTestDatabase(new URL(value))).toBe(false);
  });
});

describe('DashboardService activity journal (PostgreSQL)', () => {
  let pool: Pool;
  let fixtureClient: PoolClient;
  let fixtureTransactionOpen = false;
  let service: DashboardService;
  let actor: ActorContext;
  let captured: CapturedQuery | null;
  let cleanupEvidence: CleanupEvidence;
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
    lead: randomUUID(),
    leadAudit: randomUUID(),
  };
  const commentBody = `PRIVATE-COMMENT-${randomUUID()}`;
  const taskTitle = `DASHBOARD-TEST-TASK-${ids.task}`;

  beforeAll(async () => {
    pool = new Pool({ connectionString: databaseUrl });
    await new MigrationRunner(pool).up();
    fixtureClient = await pool.connect();
    cleanupEvidence = await staleDashboardFixtureCleanup(fixtureClient);
    if (Object.values(cleanupEvidence.deleted).some((count) => count > 0)) {
      process.stderr.write(
        `dashboard stale fixture cleanup ${JSON.stringify(cleanupEvidence)}\n`,
      );
    }
    await fixtureClient.query('begin');
    fixtureTransactionOpen = true;
    const capturingDatabase = {
      query: async <T extends QueryResultRow = QueryResultRow>(
        query: string | QueryConfig<unknown[]>,
        params: unknown[] = [],
      ) => {
        if (typeof query !== 'string') {
          throw new Error('Dashboard test adapter expects SQL text.');
        }
        captured = { sql: query, params };
        return fixtureClient.query<T>(query, params);
      },
    } as unknown as DatabaseService;
    service = new DashboardService(
      capturingDatabase,
      new CrmPolicy(),
      new AuditPresentationService(),
    );
    actor = { userId: ids.actor, role: 'director' };

    await fixtureClient.query(
      `insert into app.users (id, email, role, email_verified_at)
       values ($1, $2, 'director', now()), ($3, $4, 'client', now())`,
      [
        ids.actor,
        `dashboard-actor-${ids.actor}@example.test`,
        ids.clientUser,
        `dashboard-client-${ids.clientUser}@example.test`,
      ],
    );
    await fixtureClient.query(
      `insert into app.profiles (id, user_id, first_name, last_name)
       values ($1, $2, 'Анна', 'Директор'), ($3, $4, 'Мария', 'Ученица')`,
      [ids.actorProfile, ids.actor, ids.studentProfile, ids.clientUser],
    );
    await fixtureClient.query(
      `insert into app.staff_members (id, profile_id, role)
       values ($1, $2, 'director')`,
      [ids.actorStaff, ids.actorProfile],
    );
    await fixtureClient.query(
      `insert into app.students (id, profile_id) values ($1, $2)`,
      [ids.student, ids.studentProfile],
    );
    await fixtureClient.query(
      `insert into app.shared_tasks (
         id, title, all_day, start_at, created_by
       ) values ($1, $2, true, now() + interval '1 day', $3)`,
      [ids.task, taskTitle, ids.actor],
    );
    await fixtureClient.query(
      `insert into app.entity_comments (
         id, entity_type, entity_id, author_id, body
       ) values ($1, 'student', $2, $3, $4)`,
      [ids.comment, ids.student, ids.actor, commentBody],
    );
    await fixtureClient.query(
      `insert into app.audit_events (
         id, actor_user_id, action, entity_type, entity_id, metadata, created_at
       ) values
       ($1, $2, 'workflow.shared_task_created', 'shared_task', $3, '{}'::jsonb, now()),
       ($4, $2, 'crm.comment_created', 'crm:comment', $5, '{}'::jsonb, now() - interval '1 second'),
       ($6, $2, 'crm.student_updated', 'crm:student', $7, '{}'::jsonb, now() - interval '2 seconds'),
       ($8, $2, 'crm.lead_updated', 'crm:lead', $9, '{}'::jsonb, now() - interval '3 seconds')`,
      [
        ids.taskAudit,
        ids.actor,
        ids.task,
        ids.commentAudit,
        ids.comment,
        ids.studentAudit,
        ids.student,
        ids.leadAudit,
        ids.lead,
      ],
    );
  });

  afterAll(async () => {
    if (fixtureClient && fixtureTransactionOpen) {
      await fixtureClient.query('rollback');
      fixtureTransactionOpen = false;
    }
    if (fixtureClient) fixtureClient.release();
    if (pool) await pool.end();
  });

  it('removes every exact stale local fixture resolved before the suite', () => {
    expect(cleanupEvidence.deleted).toEqual(cleanupEvidence.resolved);
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
          displayName: taskTitle,
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

  it.each([
    ['shared_task', ids.task, 'workflow.shared_task_created'],
    ['crm:comment', ids.comment, 'crm.comment_created'],
    ['crm:student', ids.student, 'crm.student_updated'],
    ['crm:lead', ids.lead, 'crm.lead_updated'],
  ])('keeps the raw %s entity filter compatible', async (entityType, entityId, actionKey) => {
    const result = await service.listActivityLog(actor, {
      entityType,
      entityId,
      limit: 100,
    });
    expect(result.items).toEqual([
      expect.objectContaining({ actionKey }),
    ]);
  });

  it('searches the raw entity type as well as its presentation alias', async () => {
    const result = await service.listActivityLog(actor, {
      q: 'crm:student',
      entityId: ids.student,
      limit: 100,
    });
    expect(result.items).toEqual([
      expect.objectContaining({ actionKey: 'crm.student_updated' }),
    ]);
  });

  it('keeps transaction fixtures invisible to an observer connection', async () => {
    const observer = await pool.connect();
    try {
      const result = await observer.query<{
        actor_visible: boolean;
        task_visible: boolean;
        student_visible: boolean;
      }>(
        `select
           exists(select 1 from app.users where id = $1) as actor_visible,
           exists(select 1 from app.shared_tasks where id = $2) as task_visible,
           exists(select 1 from app.students where id = $3) as student_visible`,
        [ids.actor, ids.task, ids.student],
      );
      expect(result.rows[0]).toEqual({
        actor_visible: false,
        task_visible: false,
        student_visible: false,
      });
    } finally {
      observer.release();
    }
  });

  it('limits audit candidates before target joins and keeps UUID PK lookup usable', async () => {
    await service.listActivityLog(actor, { limit: 25 });
    expect(captured).not.toBeNull();

    await fixtureClient.query('set local enable_seqscan = off');
    const explained = await fixtureClient.query<{ 'QUERY PLAN': Array<{ Plan: ExplainNode }> }>(
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
    expect(studentLookups.length).toBeGreaterThan(0);

    const pkExplained = await fixtureClient.query<{
      'QUERY PLAN': Array<{ Plan: ExplainNode }>;
    }>(
      `explain (format json)
       select id from app.students where id = $1::uuid`,
      [ids.student],
    );
    const pkNodes = planNodes(pkExplained.rows[0]!['QUERY PLAN'][0]!.Plan);
    expect(pkNodes.some(
      (node) => /Index/.test(node['Node Type'])
        && node['Index Name'] === 'students_pkey'
        && node['Index Cond']?.includes('(id =') === true,
    )).toBe(true);
    expect(captured!.sql).toContain('target_student_record.id = ae.target_entity_uuid');
  });
});
