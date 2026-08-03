import { createHash } from "crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "fs";
import { resolve } from "path";
import { Pool, PoolClient, QueryResultRow } from "pg";

type BackfillMode = "dry-run" | "apply";
type BackfillKind = "access-link" | "teacher-branch" | "lesson-snapshot";

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

interface LessonSubjectRow extends QueryResultRow {
  lesson_id: string;
  group_id: string | null;
  client_type: "lead" | "student";
  client_id: string;
  student_id: string | null;
  scheduled_at: Date | string;
  duration_minutes: number | string;
  is_trial: boolean;
  personal_price: string | null;
  teacher_rate: string;
}

interface SubscriptionCapacityRow extends QueryResultRow {
  id: string;
  student_id: string;
  starts_at: Date | string | null;
  expires_at: Date | string | null;
  snapshot_ready: boolean;
  remaining_units: string;
  created_at: Date | string;
}

interface SnapshotParticipantPlan {
  clientType: "lead" | "student";
  clientId: string;
  chargeType: "subscription" | "personal_account" | "none";
  chargeValue: number;
  subscriptionId: string | null;
}

interface LessonSnapshotPlan {
  lessonId: string;
  groupId: string | null;
  teacherCompensationType: "hourly" | "none";
  teacherCompensationValue: number;
  trial: boolean;
  participants: SnapshotParticipantPlan[];
}

interface BackfillReport {
  schemaVersion: 2;
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
  manualMappingTable: BackfillReport["reviewQueue"];
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
      select distinct teacher.id as teacher_id, lesson.branch_id
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
              and assignment.branch_id = lesson.branch_id
              and assignment.active_from <= current_date
              and (assignment.active_until is null
                   or assignment.active_until >= current_date)
         )
    )
    select 'teacher-branch'::text as kind,
           teacher_id::text as entity_id,
           branch_id::text as related_id
      from future_evidence
     order by teacher_id`);
  return result.rows;
}

async function planLessonSnapshots(client: PoolClient): Promise<{
  plans: LessonSnapshotPlan[];
  review: ReviewRow[];
}> {
  const subjects = await client.query<LessonSubjectRow>(`
    with target_lessons as (
      select lesson.id as lesson_id, lesson.group_id,
             case when lesson.lead_id is not null then 'lead' else 'student' end
               as direct_client_type,
             coalesce(lesson.lead_id, lesson.student_id) as direct_client_id,
             lesson.student_id as direct_student_id,
             lesson.scheduled_at, lesson.duration_minutes, lesson.is_trial,
             group_row.price_per_lesson as group_price,
             coalesce(
               lesson.teacher_rate,
               group_row.teacher_rate,
               (
                 select rate.rate
                 from app.teacher_rates rate
                 where rate.teacher_id = lesson.teacher_id
                   and rate.effective_from <= lesson.scheduled_at::date
                 order by rate.effective_from desc, rate.created_at desc
                 limit 1
               ),
               0
             )::text as teacher_rate
        from app.lessons lesson
        left join app.groups group_row
          on group_row.id = lesson.group_id and group_row.deleted_at is null
        left join app.lesson_snapshots snapshot on snapshot.lesson_id = lesson.id
       where lesson.deleted_at is null
         and lesson.status = 'scheduled'
         and lesson.scheduled_at >= now()
         and (
           lesson.group_id is not null
           or lesson.scheduled_at < now() + interval '60 days'
         )
         and (snapshot.lesson_id is null or snapshot.validation_state <> 'valid')
    )
    select target.lesson_id, target.group_id,
           target.direct_client_type::text as client_type,
           target.direct_client_id::text as client_id,
           target.direct_student_id::text as student_id,
           target.scheduled_at, target.duration_minutes, target.is_trial,
           case
             when student.custom_data->>'individualPrice' ~ '^[0-9]+(\\.[0-9]+)?$'
               then student.custom_data->>'individualPrice'
             when student.custom_data->>'individual_price' ~ '^[0-9]+(\\.[0-9]+)?$'
               then student.custom_data->>'individual_price'
             else null
           end as personal_price,
           target.teacher_rate
      from target_lessons target
      left join app.students student
        on student.id = target.direct_student_id and student.deleted_at is null
     where target.group_id is null and target.direct_client_id is not null
    union all
    select target.lesson_id, target.group_id, 'student', member.student_id::text,
           member.student_id::text, target.scheduled_at, target.duration_minutes,
           target.is_trial, target.group_price::text, target.teacher_rate
      from target_lessons target
      join app.group_students member on member.group_id = target.group_id
       and member.joined_at <= target.scheduled_at
       and (member.left_at is null or member.left_at > target.scheduled_at)
      join app.students student
        on student.id = member.student_id and student.deleted_at is null
     where target.group_id is not null
     order by scheduled_at, lesson_id, client_id
  `);
  const studentIds = Array.from(new Set(subjects.rows
    .map((row) => row.student_id)
    .filter((value): value is string => Boolean(value))));
  const subscriptions = studentIds.length === 0
    ? { rows: [] as SubscriptionCapacityRow[] }
    : await client.query<SubscriptionCapacityRow>(`
        select subscription.id, subscription.student_id,
               subscription.starts_at, subscription.expires_at,
               (subscription.commercial_snapshot is not null) as snapshot_ready,
               greatest(0,
                 subscription.lessons_total - subscription.lessons_used
                 - coalesce((
                   select sum(reservation.units)
                   from app.lesson_reservations reservation
                   where reservation.subscription_id = subscription.id
                     and reservation.state = 'reserved'
                 ), 0)
                 - coalesce((
                   select sum(fact.units)
                   from app.lesson_client_charge_facts fact
                   where fact.subscription_id = subscription.id
                     and fact.charge_type = 'subscription'
                 ), 0)
               )::text as remaining_units,
               subscription.created_at
          from app.subscriptions subscription
         where subscription.student_id = any($1::uuid[])
           and subscription.status = 'active'
         order by subscription.student_id,
                  subscription.expires_at nulls last,
                  subscription.created_at,
                  subscription.id
      `, [studentIds]);
  const byStudent = new Map<string, Array<SubscriptionCapacityRow & { remaining: number }>>();
  for (const subscription of subscriptions.rows) {
    const list = byStudent.get(subscription.student_id) ?? [];
    list.push({ ...subscription, remaining: Number(subscription.remaining_units) });
    byStudent.set(subscription.student_id, list);
  }
  const plans = new Map<string, LessonSnapshotPlan>();
  const review = new Map<string, ReviewRow>();
  const discardPlan = (lessonId: string) => {
    for (const participant of plans.get(lessonId)?.participants ?? []) {
      if (!participant.subscriptionId) continue;
      const subscription = Array.from(byStudent.values())
        .flat()
        .find((candidate) => candidate.id === participant.subscriptionId);
      if (subscription) subscription.remaining += participant.chargeValue;
    }
    plans.delete(lessonId);
  };
  const lessonIds = new Set(subjects.rows.map((row) => row.lesson_id));
  const participantCounts = new Map<string, number>();
  for (const subject of subjects.rows) {
    participantCounts.set(
      subject.lesson_id,
      (participantCounts.get(subject.lesson_id) ?? 0) + 1,
    );
    if (review.has(subject.lesson_id)) continue;
    const scheduledAt = new Date(subject.scheduled_at);
    const units = Number(subject.duration_minutes) / 60;
    const active = subject.student_id
      ? (byStudent.get(subject.student_id) ?? []).filter((subscription) => {
          const starts = subscription.starts_at
            ? new Date(`${String(subscription.starts_at).slice(0, 10)}T00:00:00Z`)
            : null;
          const expires = subscription.expires_at
            ? new Date(`${String(subscription.expires_at).slice(0, 10)}T23:59:59.999Z`)
            : null;
          return (!starts || starts <= scheduledAt) && (!expires || expires >= scheduledAt)
            && subscription.remaining + Number.EPSILON >= units;
        })
      : [];
    const unprovable = active.find((subscription) => !subscription.snapshot_ready);
    if (unprovable) {
      review.set(subject.lesson_id, {
        check_id: "schedule.future-snapshot-incomplete",
        entity_id: subject.lesson_id,
        related_id: unprovable.id,
        reason: "active_subscription_snapshot_unprovable",
      });
      discardPlan(subject.lesson_id);
      continue;
    }
    const subscription = active.find((candidate) => candidate.snapshot_ready);
    let participant: SnapshotParticipantPlan;
    if (subscription) {
      subscription.remaining -= units;
      participant = {
        clientType: subject.client_type,
        clientId: subject.client_id,
        chargeType: "subscription",
        chargeValue: units,
        subscriptionId: subscription.id,
      };
    } else if (subject.is_trial && subject.personal_price === null) {
      participant = {
        clientType: subject.client_type,
        clientId: subject.client_id,
        chargeType: "none",
        chargeValue: 0,
        subscriptionId: null,
      };
    } else if (subject.personal_price !== null) {
      participant = {
        clientType: subject.client_type,
        clientId: subject.client_id,
        chargeType: "personal_account",
        chargeValue: Number(subject.personal_price),
        subscriptionId: null,
      };
    } else {
      review.set(subject.lesson_id, {
        check_id: "schedule.future-snapshot-incomplete",
        entity_id: subject.lesson_id,
        related_id: subject.client_id,
        reason: "personal_account_price_missing",
      });
      discardPlan(subject.lesson_id);
      continue;
    }
    const rate = Number(subject.teacher_rate);
    const plan = plans.get(subject.lesson_id) ?? {
      lessonId: subject.lesson_id,
      groupId: subject.group_id,
      teacherCompensationType: rate > 0 ? "hourly" : "none",
      teacherCompensationValue: rate > 0 ? rate : 0,
      trial: subject.is_trial,
      participants: [],
    };
    plan.participants.push(participant);
    plans.set(subject.lesson_id, plan);
  }
  for (const lessonId of lessonIds) {
    if ((participantCounts.get(lessonId) ?? 0) === 0) {
      review.set(lessonId, {
        check_id: "schedule.future-snapshot-incomplete",
        entity_id: lessonId,
        related_id: null,
        reason: "group_has_no_scheduled_participants",
      });
      discardPlan(lessonId);
    }
  }
  return {
    plans: Array.from(plans.values()).sort((a, b) => a.lessonId.localeCompare(b.lessonId)),
    review: Array.from(review.values()).sort((a, b) => a.entity_id.localeCompare(b.entity_id)),
  };
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

async function applySnapshotPlans(
  client: PoolClient,
  plans: readonly LessonSnapshotPlan[],
): Promise<number> {
  let applied = 0;
  for (const plan of plans) {
    const first = plan.participants[0]!;
    const snapshot = await client.query(
      `
        insert into app.lesson_snapshots (
          lesson_id, client_type, client_id, group_id, completion_type,
          client_charge_type, client_charge_value,
          teacher_compensation_type, teacher_compensation_value,
          subscription_id, trial, validation_state, origin, duration_minutes
        ) values (
          $1, $2, $3, $4, 'standard.success', $5, $6, $7, $8, $9,
          $10, 'valid', 'legacy_backfill',
          (select duration_minutes from app.lessons where id = $1)
        )
        on conflict (lesson_id) do update set
          client_charge_type = excluded.client_charge_type,
          client_charge_value = excluded.client_charge_value,
          teacher_compensation_type = excluded.teacher_compensation_type,
          teacher_compensation_value = excluded.teacher_compensation_value,
          subscription_id = excluded.subscription_id,
          validation_state = 'valid'
        where app.lesson_snapshots.validation_state = 'legacy_incomplete'
        returning lesson_id
      `,
      [
        plan.lessonId,
        plan.groupId ? null : first.clientType,
        plan.groupId ? null : first.clientId,
        plan.groupId,
        plan.groupId ? "none" : first.chargeType,
        plan.groupId ? 0 : first.chargeValue,
        plan.teacherCompensationType,
        plan.teacherCompensationValue,
        plan.groupId ? null : first.subscriptionId,
        plan.trial,
      ],
    );
    if (snapshot.rowCount !== 1) continue;
    if (plan.groupId) {
      for (const participant of plan.participants) {
        await client.query(
          `
            insert into app.lesson_snapshot_participants (
              lesson_id, student_id, charge_type, charge_value, subscription_id
            ) values ($1, $2, $3, $4, $5)
            on conflict (lesson_id, student_id) do nothing
          `,
          [
            plan.lessonId,
            participant.clientId,
            participant.chargeType,
            participant.chargeValue,
            participant.subscriptionId,
          ],
        );
      }
    }
    for (const participant of plan.participants) {
      if (participant.chargeType !== "subscription" || !participant.subscriptionId) continue;
      await client.query(
        `
          insert into app.lesson_reservations (lesson_id, subscription_id, units)
          values ($1, $2, $3)
          on conflict (lesson_id, subscription_id) do nothing
        `,
        [plan.lessonId, participant.subscriptionId, participant.chargeValue],
      );
    }
    applied += 1;
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
  const lessonIds = candidates
    .filter((candidate) => candidate.kind === "lesson-snapshot")
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
    select 'commerce.subscription-snapshot-unprovable',
           subscription.id::text,
           subscription.package_id::text,
           concat_ws(',',
             'commercial_snapshot_null',
             'payment=' || coalesce(subscription.payment_id::text, 'null')
           )
      from app.subscriptions subscription
     where subscription.commercial_snapshot is null
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
       and (
         lesson.group_id is not null
         or lesson.scheduled_at < now() + interval '60 days'
       )
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
       and (
         lesson.group_id is not null
         or lesson.scheduled_at < now() + interval '60 days'
       )
       and (snapshot.lesson_id is null or snapshot.validation_state <> 'valid')
       and not (lesson.id = any($3::uuid[]))
    order by 1, 2`, [accessIds, teacherIds, lessonIds]);
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
    const deterministicCandidates = [
      ...(await findAccessCandidates(client)),
      ...(await findTeacherBranchCandidates(client)),
    ];
    const snapshotPlanning = await planLessonSnapshots(client);
    const snapshotCandidates: BackfillCandidate[] = snapshotPlanning.plans.map(
      (plan) => ({
        kind: "lesson-snapshot",
        entity_id: plan.lessonId,
        related_id: plan.groupId ?? plan.participants[0]!.clientId,
      }),
    );
    const candidates = [...deterministicCandidates, ...snapshotCandidates];
    const applied = mode === "apply"
      ? (await applyCandidates(client, deterministicCandidates))
        + (await applySnapshotPlans(client, snapshotPlanning.plans))
      : 0;
    const discoveredReview = await findReviewQueue(
      client,
      mode === "apply" ? [] : candidates,
    );
    const reviewByKey = new Map<string, ReviewRow>();
    for (const row of [...snapshotPlanning.review, ...discoveredReview]) {
      reviewByKey.set(`${row.check_id}:${row.entity_id}`, row);
    }
    const review = Array.from(reviewByKey.values()).sort((a, b) =>
      `${a.check_id}:${a.entity_id}`.localeCompare(`${b.check_id}:${b.entity_id}`),
    );
    const normalizedCandidates = canonicalCandidates(candidates);
    const normalizedReview = canonicalReview(review);
    const digest = createHash("sha256")
      .update(JSON.stringify({ normalizedCandidates, normalizedReview }))
      .digest("hex");
    const report: BackfillReport = {
      schemaVersion: 2,
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
      manualMappingTable: normalizedReview,
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
