import { createHash } from "crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "fs";
import { resolve } from "path";
import { Pool, PoolClient, QueryResultRow } from "pg";

type BackfillMode = "dry-run" | "apply";
type BackfillKind = "access-link" | "teacher-branch";

interface BackfillCandidate extends QueryResultRow {
  kind: BackfillKind;
  entity_id: string;
  related_id: string;
}

interface ReviewRow extends QueryResultRow {
  check_id: string;
  entity_id: string;
  related_id: string | null;
  reason: string;
}

interface BackfillReport {
  schemaVersion: 1;
  task: "T8.3.1";
  mode: BackfillMode;
  generatedAt: string;
  summary: {
    candidates: number;
    applied: number;
    reviewQueue: number;
  };
  candidates: Array<{
    kind: BackfillKind;
    entityId: string;
    relatedId: string;
  }>;
  reviewQueue: Array<{
    checkId: string;
    entityId: string;
    relatedId: string | null;
    reason: string;
  }>;
  proof: {
    transaction: "repeatable-read";
    deterministicOnly: true;
    reportDigestSha256: string;
  };
}

const serverRoot = resolve(__dirname, "..", "..");
const repoRoot = resolve(serverRoot, "..");

function loadDatabaseUrl(): string {
  const direct = process.env.MIGRATION_DATABASE_URL?.trim()
    || process.env.DATABASE_URL?.trim();
  if (direct) return direct;

  const envPath = resolve(serverRoot, ".env");
  if (existsSync(envPath)) {
    const line = readFileSync(envPath, "utf8")
      .split(/\r?\n/)
      .find((item) => /^(MIGRATION_DATABASE_URL|DATABASE_URL)=/.test(item));
    const value = line?.slice(line.indexOf("=") + 1).trim();
    if (value) return value;
  }
  throw new Error("MIGRATION_DATABASE_URL or DATABASE_URL is required.");
}

function canonicalCandidates(rows: readonly BackfillCandidate[]) {
  return rows
    .map((row) => ({
      kind: row.kind,
      entityId: row.entity_id,
      relatedId: row.related_id,
    }))
    .sort((left, right) =>
      `${left.kind}:${left.entityId}:${left.relatedId}`.localeCompare(
        `${right.kind}:${right.entityId}:${right.relatedId}`,
      ),
    );
}

async function findAccessCandidates(
  client: PoolClient,
): Promise<BackfillCandidate[]> {
  const result = await client.query<BackfillCandidate>(`
    with expected as (
      select u.id as user_id,
             case
               when u.role::text = 'client' then 'student'
               when u.role::text = 'teacher' then 'teacher'
               when u.role::text in ('admin','manager','director','system_admin')
                 then 'staff'
             end as entity_type
        from app.users u
       where u.deleted_at is null
         and u.is_app_account = true
    ),
    profile_entities as (
      select p.user_id, 'student'::text as entity_type, s.id as entity_id
        from app.profiles p
        join app.students s on s.profile_id = p.id and s.deleted_at is null
       where p.deleted_at is null
      union all
      select p.user_id, 'teacher'::text, t.id
        from app.profiles p
        join app.teachers t on t.profile_id = p.id and t.deleted_at is null
       where p.deleted_at is null
      union all
      select p.user_id, 'staff'::text, s.id
        from app.profiles p
        join app.staff_members s on s.profile_id = p.id and s.deleted_at is null
       where p.deleted_at is null
    ),
    deterministic as (
      select e.user_id, e.entity_type, (array_agg(pe.entity_id))[1] as entity_id
        from expected e
        join profile_entities pe
          on pe.user_id = e.user_id and pe.entity_type = e.entity_type
       where e.entity_type is not null
         and not exists (
           select 1 from app.user_crm_links link
            where link.user_id = e.user_id
              and link.entity_type::text = e.entity_type
              and link.deleted_at is null
         )
       group by e.user_id, e.entity_type
      having count(*) = 1
    )
    select 'access-link'::text as kind,
           d.user_id::text as entity_id,
           d.entity_id::text as related_id
      from deterministic d
     where not exists (
       select 1 from app.user_crm_links link
        where link.entity_type::text = d.entity_type
          and link.entity_id = d.entity_id
          and link.deleted_at is null
     )
     order by d.user_id`);
  return result.rows;
}

async function findTeacherBranchCandidates(
  client: PoolClient,
): Promise<BackfillCandidate[]> {
  const result = await client.query<BackfillCandidate>(`
    with future_evidence as (
      select teacher.id as teacher_id,
             (array_agg(distinct lesson.branch_id))[1] as branch_id
        from app.teachers teacher
        join app.lessons lesson
          on lesson.teacher_id = teacher.id
         and lesson.deleted_at is null
         and lesson.status = 'scheduled'
         and lesson.scheduled_at >= now()
         and lesson.branch_id is not null
       where teacher.deleted_at is null
         and teacher.status = 'active'
         and not exists (
           select 1 from app.teacher_branches assignment
            where assignment.teacher_id = teacher.id
              and assignment.active_from <= current_date
              and (assignment.active_until is null
                   or assignment.active_until >= current_date)
         )
       group by teacher.id
      having count(distinct lesson.branch_id) = 1
    )
    select 'teacher-branch'::text as kind,
           teacher_id::text as entity_id,
           branch_id::text as related_id
      from future_evidence
     order by teacher_id`);
  return result.rows;
}

async function applyCandidates(
  client: PoolClient,
  candidates: readonly BackfillCandidate[],
): Promise<number> {
  let applied = 0;
  for (const candidate of candidates) {
    if (candidate.kind === "access-link") {
      const result = await client.query(
        `insert into app.user_crm_links (
           user_id, entity_type, entity_id, link_source, confirmed_at
         )
         select $1::uuid,
                case
                  when u.role::text = 'client' then 'student'
                  when u.role::text = 'teacher' then 'teacher'
                  else 'staff'
                end::app.crm_entity_type,
                $2::uuid,
                'import',
                now()
           from app.users u
          where u.id = $1::uuid
         on conflict do nothing`,
        [candidate.entity_id, candidate.related_id],
      );
      applied += result.rowCount ?? 0;
      continue;
    }

    const result = await client.query(
      `insert into app.teacher_branches (
         teacher_id, branch_id, active_from, active_until, version, updated_at
       ) values ($1::uuid, $2::uuid, current_date, null, 1, now())
       on conflict (teacher_id, branch_id) do update
         set active_from = least(app.teacher_branches.active_from, current_date),
             active_until = null,
             version = app.teacher_branches.version + 1,
             updated_at = now()
       where app.teacher_branches.active_until is not null`,
      [candidate.entity_id, candidate.related_id],
    );
    applied += result.rowCount ?? 0;
  }
  return applied;
}

async function findReviewQueue(
  client: PoolClient,
  candidates: readonly BackfillCandidate[],
): Promise<ReviewRow[]> {
  const accessIds = candidates
    .filter((candidate) => candidate.kind === "access-link")
    .map((candidate) => candidate.entity_id);
  const teacherIds = candidates
    .filter((candidate) => candidate.kind === "teacher-branch")
    .map((candidate) => candidate.entity_id);
  const result = await client.query<ReviewRow>(`
    with expected_links as (
      select u.id,
             case
               when u.role::text = 'client' then 'student'
               when u.role::text = 'teacher' then 'teacher'
               when u.role::text in ('admin','manager','director','system_admin')
                 then 'staff'
             end as expected_type
        from app.users u
       where u.deleted_at is null and u.is_app_account = true
    ),
    link_counts as (
      select expected.id, expected.expected_type, count(link.user_id) as links
        from expected_links expected
        left join app.user_crm_links link
          on link.user_id = expected.id
         and link.entity_type::text = expected.expected_type
         and link.deleted_at is null
       where expected.expected_type is not null
       group by expected.id, expected.expected_type
    )
    select 'access.user-link-cardinality'::text as check_id,
           id::text as entity_id,
           null::text as related_id,
           ('expected_' || expected_type || '_links_' || links)::text as reason
      from link_counts
     where links <> 1 and not (id = any($1::uuid[]))
    union all
    select 'schedule.active-teacher-branch-missing', teacher.id::text, null,
           'no_unambiguous_branch_evidence'
      from app.teachers teacher
     where teacher.deleted_at is null
       and teacher.status = 'active'
       and not exists (
         select 1 from app.teacher_branches assignment
          where assignment.teacher_id = teacher.id
            and assignment.active_from <= current_date
            and (assignment.active_until is null
                 or assignment.active_until >= current_date)
       )
       and not (teacher.id = any($2::uuid[]))
    union all
    select 'schedule.future-missing-resources', lesson.id::text, null,
           concat_ws(',',
             case when lesson.teacher_id is null then 'teacher' end,
             case when lesson.branch_id is null then 'branch' end,
             case when lesson.room_id is null then 'room' end,
             case when coalesce(lesson.student_id, lesson.lead_id, lesson.group_id) is null
               then 'client' end,
             case when lesson.duration_minutes <= 0 then 'duration' end)
      from app.lessons lesson
     where lesson.deleted_at is null
       and lesson.status = 'scheduled'
       and lesson.scheduled_at >= now()
       and (lesson.teacher_id is null or lesson.branch_id is null
         or lesson.room_id is null
         or coalesce(lesson.student_id, lesson.lead_id, lesson.group_id) is null
         or lesson.duration_minutes <= 0)
    union all
    select 'schedule.future-snapshot-incomplete', lesson.id::text,
           snapshot.lesson_id::text,
           case when snapshot.lesson_id is null
             then 'snapshot_missing' else 'snapshot_not_valid' end
      from app.lessons lesson
      left join app.lesson_snapshots snapshot on snapshot.lesson_id = lesson.id
     where lesson.deleted_at is null
       and lesson.status = 'scheduled'
       and lesson.scheduled_at >= now()
       and (snapshot.lesson_id is null or snapshot.validation_state <> 'valid')
    order by 1, 2`, [accessIds, teacherIds]);
  return result.rows;
}

function canonicalReview(rows: readonly ReviewRow[]) {
  return rows.map((row) => ({
    checkId: row.check_id,
    entityId: row.entity_id,
    relatedId: row.related_id,
    reason: row.reason,
  }));
}

async function runBackfill(
  pool: Pool,
  mode: BackfillMode,
): Promise<BackfillReport> {
  const client = await pool.connect();
  try {
    await client.query("begin transaction isolation level repeatable read");
    await client.query("select pg_advisory_xact_lock(hashtext('v4-production-backfill'))");
    const candidates = [
      ...(await findAccessCandidates(client)),
      ...(await findTeacherBranchCandidates(client)),
    ];
    const applied = mode === "apply"
      ? await applyCandidates(client, candidates)
      : 0;
    const review = await findReviewQueue(
      client,
      mode === "apply" ? [] : candidates,
    );
    const normalizedCandidates = canonicalCandidates(candidates);
    const normalizedReview = canonicalReview(review);
    const digest = createHash("sha256")
      .update(JSON.stringify({ normalizedCandidates, normalizedReview }))
      .digest("hex");
    const report: BackfillReport = {
      schemaVersion: 1,
      task: "T8.3.1",
      mode,
      generatedAt: new Date().toISOString(),
      summary: {
        candidates: candidates.length,
        applied,
        reviewQueue: review.length,
      },
      candidates: normalizedCandidates,
      reviewQueue: normalizedReview,
      proof: {
        transaction: "repeatable-read",
        deterministicOnly: true,
        reportDigestSha256: digest,
      },
    };
    if (mode === "apply") await client.query("commit");
    else await client.query("rollback");
    return report;
  } catch (error) {
    await client.query("rollback").catch(() => undefined);
    throw error;
  } finally {
    client.release();
  }
}

function writeReport(report: BackfillReport): string {
  const directory = resolve(repoRoot, "docs", "audits");
  mkdirSync(directory, { recursive: true });
  const path = resolve(directory, `v4-production-backfill-${report.mode}.json`);
  writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`, "utf8");
  return path;
}

async function main(): Promise<void> {
  const dryRun = process.argv.includes("--dry-run");
  const apply = process.argv.includes("--apply");
  if (dryRun === apply) {
    throw new Error("Pass exactly one of --dry-run or --apply.");
  }
  const mode: BackfillMode = apply ? "apply" : "dry-run";
  const pool = new Pool({
    connectionString: loadDatabaseUrl(),
    max: 1,
    connectionTimeoutMillis: 10_000,
    statement_timeout: 120_000,
    application_name: `magicmusiccrm-v4-backfill-${mode}`,
  });
  try {
    const report = await runBackfill(pool, mode);
    const reportPath = writeReport(report);
    process.stdout.write(`${JSON.stringify({
      task: report.task,
      mode,
      summary: report.summary,
      report: reportPath.replace(`${repoRoot}\\`, "").replace(/\\/g, "/"),
    })}\n`);
    if (report.summary.reviewQueue > 0) process.exitCode = 2;
  } finally {
    await pool.end();
  }
}

if (require.main === module) {
  main().catch((error: unknown) => {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`v4 backfill failed: ${message}\n`);
    process.exitCode = 1;
  });
}

export { canonicalCandidates, runBackfill };
