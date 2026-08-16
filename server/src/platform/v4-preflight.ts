import { createHash } from "crypto";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "fs";
import { resolve } from "path";
import { Pool, PoolClient, QueryResultRow } from "pg";

type V4System =
  | "SYS-ACCESS"
  | "SYS-CRM"
  | "SYS-SCHEDULE"
  | "SYS-COMMERCE"
  | "SYS-WORKFLOW"
  | "SYS-PLATFORM";

type FindingSeverity = "blocker" | "warning";

interface FindingRow {
  entityId: string;
  relatedId: string | null;
  detail: string;
}

interface PreflightCheck {
  id: string;
  owner: V4System;
  severity: FindingSeverity;
  description: string;
  count: number;
  rows: FindingRow[];
}

interface PreflightSummary {
  checks: number;
  findings: number;
  blockerFindings: number;
  warningFindings: number;
}

interface V4PreflightReport {
  schemaVersion: 1;
  task: "T8.1.3";
  mode: "repeatable-read/read-only";
  summary: PreflightSummary;
  checks: PreflightCheck[];
  proof: {
    transactionReadOnly: true;
    writeProbeRejected: true;
    writeProbeSqlState: "25006";
    repeatedScanStable: true;
    scanDigestSha256: string;
  };
}

interface CheckDefinition {
  id: string;
  owner: V4System;
  severity: FindingSeverity;
  description: string;
  requires: Record<string, string[]>;
  sql: string;
  params?: unknown[];
}

interface RawFindingRow extends QueryResultRow {
  entity_id: unknown;
  related_id: unknown;
  detail: unknown;
}

type SchemaColumns = Map<string, Set<string>>;

const serverRoot = resolve(__dirname, "..", "..");
const repoRoot = resolve(serverRoot, "..");
const reportJsonPath = resolve(
  repoRoot,
  "docs",
  "audits",
  "v4-data-preflight.json",
);
const reportMarkdownPath = resolve(
  repoRoot,
  "docs",
  "audits",
  "v4-data-preflight.md",
);

function loadDatabaseUrl(): string {
  const fromProcess = process.env.DATABASE_URL?.trim();
  if (fromProcess) return fromProcess;

  const envPath = resolve(serverRoot, ".env");
  if (!existsSync(envPath)) {
    throw new Error(
      "DATABASE_URL is not set and server/.env is unavailable.",
    );
  }
  const line = readFileSync(envPath, "utf8")
    .split(/\r?\n/)
    .find((candidate) => /^\s*DATABASE_URL\s*=/.test(candidate));
  if (!line) {
    throw new Error("DATABASE_URL is not defined in server/.env.");
  }
  const raw = line.slice(line.indexOf("=") + 1).trim();
  const unquoted =
    (raw.startsWith('"') && raw.endsWith('"')) ||
    (raw.startsWith("'") && raw.endsWith("'"))
      ? raw.slice(1, -1)
      : raw;
  if (!unquoted) throw new Error("DATABASE_URL is empty.");
  return unquoted;
}

async function readSchema(client: PoolClient): Promise<SchemaColumns> {
  const result = await client.query<{
    table_name: string;
    column_name: string;
  }>(
    `select table_name, column_name
       from information_schema.columns
      where table_schema = 'app'
      order by table_name, ordinal_position`,
  );
  const schema: SchemaColumns = new Map();
  for (const row of result.rows) {
    const columns = schema.get(row.table_name) ?? new Set<string>();
    columns.add(row.column_name);
    schema.set(row.table_name, columns);
  }
  return schema;
}

function missingRequirements(
  schema: SchemaColumns,
  requires: Record<string, string[]>,
): string[] {
  const missing: string[] = [];
  for (const [table, columns] of Object.entries(requires)) {
    const available = schema.get(table);
    if (!available) {
      missing.push(`app.${table}`);
      continue;
    }
    for (const column of columns) {
      if (!available.has(column)) missing.push(`app.${table}.${column}`);
    }
  }
  return missing.sort();
}

function normalizeRows(rows: RawFindingRow[]): FindingRow[] {
  return rows
    .map((row) => ({
      entityId: String(row.entity_id),
      relatedId:
        row.related_id === null || row.related_id === undefined
          ? null
          : String(row.related_id),
      detail:
        row.detail === null || row.detail === undefined
          ? ""
          : String(row.detail),
    }))
    .sort((left, right) => {
      const leftKey = `${left.entityId}\u0000${left.relatedId ?? ""}\u0000${left.detail}`;
      const rightKey = `${right.entityId}\u0000${right.relatedId ?? ""}\u0000${right.detail}`;
      return leftKey.localeCompare(rightKey);
    });
}

async function executeCheck(
  client: PoolClient,
  schema: SchemaColumns,
  definition: CheckDefinition,
): Promise<PreflightCheck> {
  const missing = missingRequirements(schema, definition.requires);
  if (missing.length > 0) {
    const rows = missing.map((identifier) => ({
      entityId: identifier,
      relatedId: null,
      detail: "required schema object is missing",
    }));
    return {
      id: definition.id,
      owner: definition.owner,
      severity: definition.severity,
      description: definition.description,
      count: rows.length,
      rows,
    };
  }

  const result = await client.query<RawFindingRow>(
    definition.sql,
    definition.params,
  );
  const rows = normalizeRows(result.rows);
  return {
    id: definition.id,
    owner: definition.owner,
    severity: definition.severity,
    description: definition.description,
    count: rows.length,
    rows,
  };
}

function scheduleChecks(asOf: string): CheckDefinition[] {
  const lessonBase = {
    lessons: [
      "id",
      "student_id",
      "group_id",
      "lead_id",
      "teacher_id",
      "branch_id",
      "room_id",
      "scheduled_at",
      "duration_minutes",
      "status",
      "deleted_at",
    ],
  };

  return [
    {
      id: "schedule.future-overlaps",
      owner: "SYS-SCHEDULE",
      severity: "blocker",
      description:
        "Future scheduled lessons overlap on teacher, room, student, lead, or group.",
      requires: lessonBase,
      params: [asOf],
      sql: `
        with future as (
          select id, student_id, group_id, lead_id, teacher_id, room_id,
                 scheduled_at,
                 scheduled_at + make_interval(mins => duration_minutes) as ends_at
            from app.lessons
           where deleted_at is null
             and status = 'scheduled'
             and scheduled_at >= $1::timestamptz
             and (group_id is not null or scheduled_at < $1::timestamptz + interval '60 days')
        ),
        pairs as (
          select a.id as entity_id, b.id as related_id, 'teacher' as detail
            from future a join future b
              on a.id::text < b.id::text
             and a.teacher_id is not null
             and a.teacher_id = b.teacher_id
             and a.scheduled_at < b.ends_at and b.scheduled_at < a.ends_at
          union all
          select a.id, b.id, 'room'
            from future a join future b
              on a.id::text < b.id::text
             and a.room_id is not null
             and a.room_id = b.room_id
             and a.scheduled_at < b.ends_at and b.scheduled_at < a.ends_at
          union all
          select a.id, b.id, 'student'
            from future a join future b
              on a.id::text < b.id::text
             and a.student_id is not null
             and a.student_id = b.student_id
             and a.scheduled_at < b.ends_at and b.scheduled_at < a.ends_at
          union all
          select a.id, b.id, 'lead'
            from future a join future b
              on a.id::text < b.id::text
             and a.lead_id is not null
             and a.lead_id = b.lead_id
             and a.scheduled_at < b.ends_at and b.scheduled_at < a.ends_at
          union all
          select a.id, b.id, 'group'
            from future a join future b
              on a.id::text < b.id::text
             and a.group_id is not null
             and a.group_id = b.group_id
             and a.scheduled_at < b.ends_at and b.scheduled_at < a.ends_at
        )
        select entity_id::text, related_id::text, detail
          from pairs
         order by entity_id, related_id, detail`,
    },
    {
      id: "schedule.future-missing-resources",
      owner: "SYS-SCHEDULE",
      severity: "blocker",
      description:
        "Future lessons miss teacher, branch, room, client reference, or positive duration.",
      requires: lessonBase,
      params: [asOf],
      sql: `
        select id::text as entity_id, null::text as related_id,
               concat_ws(',',
                 case when teacher_id is null then 'teacher' end,
                 case when branch_id is null then 'branch' end,
                 case when room_id is null then 'room' end,
                 case when student_id is null and group_id is null and lead_id is null
                      then 'client_ref' end,
                 case when duration_minutes <= 0 then 'duration' end
               ) as detail
          from app.lessons
         where deleted_at is null
           and status = 'scheduled'
           and scheduled_at >= $1::timestamptz
           and (group_id is not null or scheduled_at < $1::timestamptz + interval '60 days')
           and (
             teacher_id is null or branch_id is null or room_id is null
             or (student_id is null and group_id is null and lead_id is null)
             or duration_minutes <= 0
           )
         order by id`,
    },
    {
      id: "schedule.future-teacher-branch-missing",
      owner: "SYS-SCHEDULE",
      severity: "blocker",
      description:
        "Future lesson teacher has no explicit assignment to the lesson branch.",
      requires: {
        lessons: [
          "id",
          "group_id",
          "teacher_id",
          "branch_id",
          "scheduled_at",
          "status",
          "deleted_at",
        ],
        teacher_branches: [
          "teacher_id",
          "branch_id",
          "active_from",
          "active_until",
        ],
        branches: ["id", "timezone_name"],
      },
      params: [asOf],
      sql: `
        select l.id::text as entity_id, l.teacher_id::text as related_id,
               'teacher_branch'::text as detail
          from app.lessons l
          join app.branches branch on branch.id = l.branch_id
         where l.deleted_at is null
           and l.status = 'scheduled'
           and l.scheduled_at >= $1::timestamptz
           and (l.group_id is not null or l.scheduled_at < $1::timestamptz + interval '60 days')
           and l.teacher_id is not null
           and l.branch_id is not null
           and not exists (
             select 1
               from app.teacher_branches tb
              where tb.teacher_id = l.teacher_id
                and tb.branch_id = l.branch_id
                and tb.active_from <= timezone(
                  branch.timezone_name,
                  l.scheduled_at
                )::date
                and (
                  tb.active_until is null
                  or tb.active_until >= timezone(
                    branch.timezone_name,
                    l.scheduled_at
                  )::date
                )
           )
         order by l.id`,
    },
    {
      id: "schedule.active-teacher-branch-missing",
      owner: "SYS-SCHEDULE",
      severity: "blocker",
      description:
        "Active teacher has no current explicit branch assignment.",
      requires: {
        teachers: ["id", "status", "deleted_at"],
        teacher_branches: [
          "teacher_id",
          "active_from",
          "active_until",
        ],
      },
      sql: `
        select teacher.id::text as entity_id,
               null::text as related_id,
               'teacher_branch'::text as detail
          from app.teachers teacher
         where teacher.deleted_at is null
           and lower(teacher.status) = 'active'
           and not exists (
             select 1
               from app.teacher_branches assignment
              where assignment.teacher_id = teacher.id
                and assignment.active_from
                      <= timezone('Europe/Moscow', now())::date
                and (
                  assignment.active_until is null
                  or assignment.active_until
                       >= timezone('Europe/Moscow', now())::date
                )
           )
         order by teacher.id`,
    },
  ];
}

function commerceChecks(): CheckDefinition[] {
  return [
    {
      id: "commerce.subscription-usage-out-of-range",
      owner: "SYS-COMMERCE",
      severity: "blocker",
      description:
        "Issued subscription usage is negative or exceeds its total capacity.",
      requires: {
        subscriptions: ["id", "lessons_total", "lessons_used"],
      },
      sql: `
        select id::text as entity_id, null::text as related_id,
               'lessons_used_out_of_range'::text as detail
          from app.subscriptions
         where lessons_total < 0
            or lessons_used < 0
            or lessons_used > lessons_total
         order by id`,
    },
    {
      id: "commerce.subscription-reference-gaps",
      owner: "SYS-COMMERCE",
      severity: "blocker",
      description:
        "Issued subscriptions cannot prove package/payment references or student consistency.",
      requires: {
        subscriptions: ["id", "student_id", "package_id", "payment_id"],
        subscription_packages: ["id"],
        payments: ["id", "student_id", "deleted_at"],
      },
      sql: `
        select sub.id::text as entity_id,
               coalesce(sub.payment_id, sub.package_id)::text as related_id,
               concat_ws(',',
                 case when sub.package_id is null then 'package_id_missing' end,
                 case when sub.payment_id is null then 'payment_id_missing' end,
                 case when sub.package_id is not null and pkg.id is null
                      then 'package_row_missing' end,
                 case when sub.payment_id is not null and pay.id is null
                      then 'payment_row_missing' end,
                 case when pay.id is not null and pay.student_id <> sub.student_id
                      then 'payment_student_mismatch' end
               ) as detail
          from app.subscriptions sub
          left join app.subscription_packages pkg on pkg.id = sub.package_id
          left join app.payments pay
            on pay.id = sub.payment_id and pay.deleted_at is null
         where sub.package_id is null
            or sub.payment_id is null
            or (sub.package_id is not null and pkg.id is null)
            or (sub.payment_id is not null and pay.id is null)
            or (pay.id is not null and pay.student_id <> sub.student_id)
         order by sub.id`,
    },
    {
      id: "commerce.duplicate-payment-external-id",
      owner: "SYS-COMMERCE",
      severity: "blocker",
      description:
        "Active payment facts reuse the same non-empty external identifier.",
      requires: {
        payments: ["id", "external_id", "deleted_at"],
      },
      sql: `
        select min(id::text) as entity_id, max(id::text) as related_id,
               'duplicate_external_id'::text as detail
          from app.payments
         where deleted_at is null
           and nullif(btrim(external_id), '') is not null
         group by external_id
        having count(*) > 1
         order by min(id::text)`,
    },
    {
      id: "commerce.materialized-balance-drift",
      owner: "SYS-COMMERCE",
      severity: "warning",
      description:
        "Stored student balance differs from the current ledger projection.",
      requires: {
        student_balances: ["student_id", "balance"],
        students: ["id", "custom_data", "deleted_at"],
        lessons: [
          "id",
          "student_id",
          "group_id",
          "status",
          "is_trial",
          "deleted_at",
        ],
        lesson_participation: [
          "id",
          "lesson_id",
          "student_id",
          "subscription_id",
          "attendance_kind",
          "charge_share",
          "charged_hours",
        ],
        subscriptions: ["id", "student_id", "package_id", "payment_id", "lessons_total"],
        subscription_packages: ["id", "price"],
        payments: ["id", "student_id", "amount", "deleted_at"],
        groups: ["id", "price_per_lesson", "deleted_at"],
        account_adjustments: ["student_id", "amount", "status", "deleted_at"],
      },
      sql: `
        with lesson_costs as (
          select coalesce(sub.student_id, l.student_id, lp.student_id) as student_id,
                 sum(coalesce(
                   coalesce(sub_pay.amount, pkg.price)
                     / nullif(sub.lessons_total, 0) * lp.charged_hours,
                   coalesce(
                     g.price_per_lesson,
                     case
                       when s.custom_data->>'individualPrice' ~ '^[0-9]+(\\.[0-9]+)?$'
                         then (s.custom_data->>'individualPrice')::numeric
                       when s.custom_data->>'individual_price' ~ '^[0-9]+(\\.[0-9]+)?$'
                         then (s.custom_data->>'individual_price')::numeric
                       else null
                     end,
                     0
                   ) * case
                     when lp.id is null then 1
                     when lp.attendance_kind in ('attended', 'paid_miss') then 1
                     when lp.attendance_kind = 'partially_paid' then lp.charge_share
                     else 0
                   end
                 )) as total_cost
            from app.lessons l
            left join app.lesson_participation lp on lp.lesson_id = l.id
            join app.students s on s.id = coalesce(l.student_id, lp.student_id)
            left join app.groups g on g.id = l.group_id and g.deleted_at is null
            left join app.subscriptions sub on sub.id = lp.subscription_id
            left join app.subscription_packages pkg on pkg.id = sub.package_id
            left join app.payments sub_pay on sub_pay.id = sub.payment_id
           where l.deleted_at is null
             and l.status in ('completed', 'done')
             and l.is_trial = false
             and coalesce(l.student_id, lp.student_id) is not null
           group by coalesce(sub.student_id, l.student_id, lp.student_id)
        ),
        payment_totals as (
          select student_id, sum(amount) as total_paid
            from app.payments
           where deleted_at is null
           group by student_id
        ),
        adjustment_totals as (
          select student_id, sum(amount) as total_adjustments
            from app.account_adjustments
           where deleted_at is null and status <> 'void'
           group by student_id
        ),
        computed as (
          select s.id as student_id,
                 coalesce(pay.total_paid, 0) - coalesce(cost.total_cost, 0)
                   + coalesce(adj.total_adjustments, 0) as balance
            from app.students s
            left join payment_totals pay on pay.student_id = s.id
            left join lesson_costs cost on cost.student_id = s.id
            left join adjustment_totals adj on adj.student_id = s.id
           where s.deleted_at is null
        )
        select stored.student_id::text as entity_id, null::text as related_id,
               'stored_balance_differs_from_projection'::text as detail
          from app.student_balances stored
          join computed on computed.student_id = stored.student_id
         where abs(stored.balance - computed.balance) > 0.01
         order by stored.student_id`,
    },
    {
      id: "commerce.v7-subscription-funding-gap",
      owner: "SYS-COMMERCE",
      severity: "blocker",
      description: "Every subscription has a canonical payer and funding mode.",
      requires: {
        subscriptions: ["id", "student_id", "payer_student_id", "funding_mode"],
      },
      sql: `
        select id::text as entity_id, student_id::text as related_id,
               'payer_or_funding_missing'::text as detail
        from app.subscriptions
        where payer_student_id is null or funding_mode is null
        order by id`,
    },
    {
      id: "commerce.v7-payment-linkage-drift",
      owner: "SYS-COMMERCE",
      severity: "blocker",
      description: "Legacy actual payment and v7 paid record link exactly once.",
      requires: {
        payments: [
          "id", "student_id", "amount_minor", "payment_record_id", "deleted_at",
        ],
        client_payment_records: [
          "id", "student_id", "amount_minor", "status", "actual_payment_id",
        ],
      },
      sql: `
        select payment.id::text as entity_id, record.id::text as related_id,
               'payment_record_linkage_mismatch'::text as detail
        from app.payments payment
        left join app.client_payment_records record
          on record.actual_payment_id = payment.id
        where payment.deleted_at is null and payment.amount_minor > 0
          and (
            record.id is null
            or payment.payment_record_id is distinct from record.id
            or record.student_id <> payment.student_id
            or record.amount_minor <> payment.amount_minor
            or record.status <> 'paid'
          )
        order by payment.id`,
    },
    {
      id: "commerce.v7-subscription-version-drift",
      owner: "SYS-COMMERCE",
      severity: "blocker",
      description: "Subscription and aggregate versions agree.",
      requires: {
        subscriptions: ["id", "version", "commercial_snapshot"],
        aggregate_versions: ["aggregate_type", "aggregate_id", "version"],
      },
      sql: `
        select subscription.id::text as entity_id,
               aggregate.aggregate_id as related_id,
               'subscription_aggregate_version_mismatch'::text as detail
        from app.subscriptions subscription
        left join app.aggregate_versions aggregate
          on aggregate.aggregate_type = 'commerce:issued-subscription'
         and aggregate.aggregate_id = subscription.id::text
        where subscription.commercial_snapshot is not null
          and aggregate.version is distinct from subscription.version
        order by subscription.id`,
    },
    {
      id: "commerce.v7-payment-version-drift",
      owner: "SYS-COMMERCE",
      severity: "blocker",
      description: "Payment record, latest status event and aggregate version agree.",
      requires: {
        client_payment_records: ["id", "status", "version"],
        client_payment_status_events: [
          "payment_record_id", "after_status", "aggregate_version",
        ],
        aggregate_versions: ["aggregate_type", "aggregate_id", "version"],
      },
      sql: `
        select record.id::text as entity_id, null::text as related_id,
               'payment_event_or_aggregate_version_mismatch'::text as detail
        from app.client_payment_records record
        left join lateral (
          select event.after_status, event.aggregate_version
          from app.client_payment_status_events event
          where event.payment_record_id = record.id
          order by event.aggregate_version desc limit 1
        ) latest on true
        left join app.aggregate_versions aggregate
          on aggregate.aggregate_type = 'commerce:client-payment'
         and aggregate.aggregate_id = record.id::text
        where latest.aggregate_version is distinct from record.version
           or latest.after_status is distinct from record.status
           or aggregate.version is distinct from record.version
        order by record.id`,
    },
  ];
}

function mappingChecks(): CheckDefinition[] {
  return [
    {
      id: "crm.student-identity-missing",
      owner: "SYS-CRM",
      severity: "blocker",
      description:
        "Active student has neither profile identity nor source lead mapping.",
      requires: {
        students: ["id", "profile_id", "lead_id", "deleted_at"],
      },
      sql: `
        select id::text as entity_id, null::text as related_id,
               'profile_and_lead_missing'::text as detail
          from app.students
         where deleted_at is null
           and profile_id is null
           and lead_id is null
         order by id`,
    },
    {
      id: "crm.student-phone-ambiguous",
      owner: "SYS-CRM",
      severity: "warning",
      description:
        "Multiple active students normalize to the same non-empty profile phone.",
      requires: {
        students: ["id", "profile_id", "deleted_at"],
        profiles: ["id", "phone", "deleted_at"],
      },
      sql: `
        with normalized as (
          select s.id,
                 regexp_replace(coalesce(p.phone, ''), '\\D', '', 'g') as phone_key
            from app.students s
            join app.profiles p
              on p.id = s.profile_id and p.deleted_at is null
           where s.deleted_at is null
        ),
        duplicate_keys as (
          select phone_key
            from normalized
           where phone_key <> ''
           group by phone_key
          having count(*) > 1
        )
        select n.id::text as entity_id, null::text as related_id,
               'duplicate_normalized_phone'::text as detail
          from normalized n
          join duplicate_keys d on d.phone_key = n.phone_key
         order by n.id`,
    },
    {
      id: "workflow.task-audience-ambiguous",
      owner: "SYS-WORKFLOW",
      severity: "blocker",
      description:
        "Open task has neither an assignee nor a branch audience anchor.",
      requires: {
        tasks: ["id", "status", "assigned_to", "branch_id", "deleted_at"],
      },
      sql: `
        select id::text as entity_id, null::text as related_id,
               'assignee_and_branch_missing'::text as detail
          from app.tasks
         where deleted_at is null
           and status not in ('done', 'completed', 'cancelled')
           and assigned_to is null
           and branch_id is null
         order by id`,
    },
    {
      id: "workflow.task-entity-orphan",
      owner: "SYS-WORKFLOW",
      severity: "blocker",
      description:
        "Active task points to an entity row that cannot be mapped.",
      requires: {
        tasks: ["id", "entity_type", "entity_id", "deleted_at"],
        students: ["id"],
        teachers: ["id"],
        groups: ["id"],
        lessons: ["id"],
        leads: ["id"],
        profiles: ["id"],
        staff_members: ["id"],
      },
      sql: `
        select t.id::text as entity_id, t.entity_id::text as related_id,
               ('orphan_' || t.entity_type::text)::text as detail
          from app.tasks t
         where t.deleted_at is null
           and (
             (t.entity_type::text = 'student' and not exists (
               select 1 from app.students x where x.id = t.entity_id
             ))
             or (t.entity_type::text = 'teacher' and not exists (
               select 1 from app.teachers x where x.id = t.entity_id
             ))
             or (t.entity_type::text = 'group' and not exists (
               select 1 from app.groups x where x.id = t.entity_id
             ))
             or (t.entity_type::text = 'lesson' and not exists (
               select 1 from app.lessons x where x.id = t.entity_id
             ))
             or (t.entity_type::text = 'lead' and not exists (
               select 1 from app.leads x where x.id = t.entity_id
             ))
             or (t.entity_type::text = 'profile' and not exists (
               select 1 from app.profiles x where x.id = t.entity_id
             ))
             or (t.entity_type::text = 'staff' and not exists (
               select 1 from app.staff_members x where x.id = t.entity_id
             ))
           )
         order by t.id`,
    },
    {
      id: "access.user-link-cardinality",
      owner: "SYS-ACCESS",
      severity: "blocker",
      description:
        "Active application account does not have exactly one role-compatible CRM link.",
      requires: {
        users: ["id", "role", "is_app_account", "deleted_at"],
        user_crm_links: ["user_id", "entity_type", "deleted_at"],
      },
      sql: `
        with expected as (
          select u.id, u.role::text as role,
                 case
                   when u.role::text = 'client' then 'student'
                   when u.role::text = 'teacher' then 'teacher'
                   when u.role::text in ('admin','manager','director','system_admin')
                     then 'staff'
                   else null
                 end as expected_type
            from app.users u
           where u.deleted_at is null
             and u.is_app_account = true
        ),
        counts as (
          select e.id, e.expected_type, count(l.user_id) as link_count
            from expected e
            left join app.user_crm_links l
              on l.user_id = e.id
             and l.deleted_at is null
             and l.entity_type::text = e.expected_type
           where e.expected_type is not null
           group by e.id, e.expected_type
        )
        select id::text as entity_id, null::text as related_id,
               ('expected_' || expected_type || '_links_' || link_count)::text as detail
          from counts
         where link_count <> 1
         order by id`,
    },
    {
      id: "access.user-crm-link-ambiguous",
      owner: "SYS-ACCESS",
      severity: "blocker",
      description:
        "User has multiple active CRM links for the same entity type.",
      requires: {
        user_crm_links: ["id", "user_id", "entity_type", "entity_id", "deleted_at"],
      },
      sql: `
        select user_id::text as entity_id, min(entity_id::text) as related_id,
               ('multiple_' || entity_type::text || '_links')::text as detail
          from app.user_crm_links
         where deleted_at is null
         group by user_id, entity_type
        having count(*) > 1
         order by user_id`,
    },
  ];
}

async function snapshotChecks(
  client: PoolClient,
  schema: SchemaColumns,
  asOf: string,
): Promise<PreflightCheck[]> {
  const checks: PreflightCheck[] = [];

  const lessonSnapshotTable = schema.get("lesson_snapshots");
  const lessonDefinition: CheckDefinition = lessonSnapshotTable
    ? {
        id: "schedule.future-snapshot-incomplete",
        owner: "SYS-SCHEDULE",
        severity: "blocker",
        description:
          "Future scheduled lesson lacks an immutable completion/financial snapshot.",
        requires: {
          lessons: [
            "id",
            "group_id",
            "scheduled_at",
            "status",
            "deleted_at",
          ],
          lesson_snapshots: ["lesson_id", "validation_state"],
        },
        params: [asOf],
        sql: `
          select lesson.id::text as entity_id,
                 snapshot.lesson_id::text as related_id,
                 case
                   when snapshot.lesson_id is null then 'lesson_snapshot_missing'
                   else 'lesson_snapshot_not_valid'
                 end::text as detail
            from app.lessons lesson
            left join app.lesson_snapshots snapshot
              on snapshot.lesson_id = lesson.id
           where lesson.deleted_at is null
             and lesson.status = 'scheduled'
             and lesson.scheduled_at >= $1::timestamptz
             and (
               lesson.group_id is not null
               or lesson.scheduled_at < $1::timestamptz + interval '60 days'
             )
             and (
               snapshot.lesson_id is null
               or snapshot.validation_state <> 'valid'
             )
           order by lesson.id`,
      }
    : {
        id: "schedule.future-snapshot-incomplete",
        owner: "SYS-SCHEDULE",
        severity: "blocker",
        description:
          "Future scheduled lesson lacks an immutable completion/financial snapshot.",
        requires: {
          lessons: ["id", "group_id", "scheduled_at", "status", "deleted_at"],
        },
        params: [asOf],
        sql: `
          select id::text as entity_id, null::text as related_id,
                 'lesson_snapshot_schema_missing'::text as detail
            from app.lessons
           where deleted_at is null
             and status = 'scheduled'
             and scheduled_at >= $1::timestamptz
             and (group_id is not null or scheduled_at < $1::timestamptz + interval '60 days')
           order by id`,
      };
  checks.push(await executeCheck(client, schema, lessonDefinition));

  const subscriptionSnapshotColumns = [
    "commercial_snapshot",
    "package_snapshot",
    "snapshot_json",
  ];
  const subscriptionColumns =
    schema.get("subscriptions") ?? new Set<string>();
  const subscriptionSnapshot = subscriptionSnapshotColumns.find((column) =>
    subscriptionColumns.has(column),
  );
  const subscriptionDefinition: CheckDefinition = subscriptionSnapshot
    ? {
        id: "commerce.subscription-snapshot-unprovable",
        owner: "SYS-COMMERCE",
        severity: "blocker",
        description:
          "Issued subscription has no provable immutable commercial snapshot.",
        requires: {
          subscriptions: ["id", subscriptionSnapshot],
        },
        sql: `
          select id::text as entity_id, null::text as related_id,
                 'commercial_snapshot_null'::text as detail
            from app.subscriptions
           where ${subscriptionSnapshot} is null
           order by id`,
      }
    : {
        id: "commerce.subscription-snapshot-unprovable",
        owner: "SYS-COMMERCE",
        severity: "blocker",
        description:
          "Issued subscription has no provable immutable commercial snapshot.",
        requires: {
          subscriptions: ["id"],
        },
        sql: `
          select id::text as entity_id, null::text as related_id,
                 'commercial_snapshot_schema_missing'::text as detail
            from app.subscriptions
           order by id`,
      };
  checks.push(await executeCheck(client, schema, subscriptionDefinition));

  return checks;
}

async function collectChecks(
  client: PoolClient,
  schema: SchemaColumns,
  asOf: string,
): Promise<PreflightCheck[]> {
  const definitions = [
    ...scheduleChecks(asOf),
    ...commerceChecks(),
    ...mappingChecks(),
  ];
  const checks: PreflightCheck[] = [];
  for (const definition of definitions) {
    checks.push(await executeCheck(client, schema, definition));
  }
  checks.push(...(await snapshotChecks(client, schema, asOf)));
  return checks.sort((left, right) => left.id.localeCompare(right.id));
}

function canonicalChecks(checks: PreflightCheck[]): string {
  return JSON.stringify(checks);
}

function buildSummary(checks: PreflightCheck[]): PreflightSummary {
  return checks.reduce<PreflightSummary>(
    (summary, check) => {
      summary.checks += 1;
      summary.findings += check.count;
      if (check.severity === "blocker") {
        summary.blockerFindings += check.count;
      } else {
        summary.warningFindings += check.count;
      }
      return summary;
    },
    {
      checks: 0,
      findings: 0,
      blockerFindings: 0,
      warningFindings: 0,
    },
  );
}

async function assertReadOnly(client: PoolClient): Promise<void> {
  const setting = await client.query<{ transaction_read_only: string }>(
    "show transaction_read_only",
  );
  if (setting.rows[0]?.transaction_read_only !== "on") {
    throw new Error("Preflight transaction is not read-only.");
  }

  await client.query("savepoint v4_read_only_probe");
  try {
    await client.query(
      "update app.users set updated_at = updated_at where false",
    );
  } catch (error) {
    const sqlState =
      typeof error === "object" && error !== null && "code" in error
        ? String((error as { code?: unknown }).code ?? "")
        : "";
    await client.query("rollback to savepoint v4_read_only_probe");
    await client.query("release savepoint v4_read_only_probe");
    if (sqlState !== "25006") {
      throw new Error(
        `Read-only write probe failed with unexpected SQLSTATE ${sqlState || "<missing>"}.`,
      );
    }
    return;
  }

  await client.query("rollback to savepoint v4_read_only_probe");
  await client.query("release savepoint v4_read_only_probe");
  throw new Error("Read-only write probe unexpectedly succeeded.");
}

async function runPreflight(pool: Pool): Promise<V4PreflightReport> {
  const client = await pool.connect();
  try {
    await client.query(
      "begin transaction isolation level repeatable read read only",
    );
    await assertReadOnly(client);
    const timestamp = await client.query<{ as_of: string }>(
      "select transaction_timestamp()::text as as_of",
    );
    const asOf = timestamp.rows[0]?.as_of;
    if (!asOf) throw new Error("Unable to capture preflight snapshot time.");

    const schema = await readSchema(client);
    const first = await collectChecks(client, schema, asOf);
    const second = await collectChecks(client, schema, asOf);
    const firstCanonical = canonicalChecks(first);
    const secondCanonical = canonicalChecks(second);
    if (firstCanonical !== secondCanonical) {
      throw new Error(
        "Preflight findings changed inside one repeatable-read snapshot.",
      );
    }

    const digest = createHash("sha256")
      .update(firstCanonical)
      .digest("hex");
    return {
      schemaVersion: 1,
      task: "T8.1.3",
      mode: "repeatable-read/read-only",
      summary: buildSummary(first),
      checks: first,
      proof: {
        transactionReadOnly: true,
        writeProbeRejected: true,
        writeProbeSqlState: "25006",
        repeatedScanStable: true,
        scanDigestSha256: digest,
      },
    };
  } finally {
    try {
      await client.query("rollback");
    } finally {
      client.release();
    }
  }
}

function renderMarkdown(report: V4PreflightReport): string {
  const lines = [
    "# MagicMusicCRM v4 — Read-Only Data Preflight",
    "",
    "**Task:** T8.1.3",
    `**Mode:** \`${report.mode}\``,
    `**Result:** ${report.proof.repeatedScanStable ? "PASS" : "FAIL"}`,
    `**Scan digest:** \`${report.proof.scanDigestSha256}\``,
    "",
    "## Summary",
    "",
    "| Metric | Count |",
    "|---|---:|",
    `| Checks | ${report.summary.checks} |`,
    `| Findings | ${report.summary.findings} |`,
    `| Blockers | ${report.summary.blockerFindings} |`,
    `| Warnings | ${report.summary.warningFindings} |`,
    "",
    "## Checks",
    "",
    "| Check | Owner | Severity | Findings |",
    "|---|---|---|---:|",
    ...report.checks.map(
      (check) =>
        `| \`${check.id}\` | ${check.owner} | ${check.severity} | ${check.count} |`,
    ),
    "",
    "The JSON artifact contains every finding as stable entity/related IDs; it",
    "does not include names, phones, emails, connection strings, or monetary",
    "amounts.",
    "",
    "## Read-only proof",
    "",
    `- Transaction setting is read-only: ${report.proof.transactionReadOnly}.`,
    `- A no-row UPDATE probe was rejected with SQLSTATE \`${report.proof.writeProbeSqlState}\`.`,
    `- Two scans in one repeatable-read snapshot were byte-stable: ${report.proof.repeatedScanStable}.`,
    `- Findings digest: \`${report.proof.scanDigestSha256}\`.`,
    "",
    "## Reproduction",
    "",
    "```powershell",
    "npm --prefix server run v4:preflight -- --check-read-only",
    "```",
  ];
  return `${lines.join("\n")}\n`;
}

function writeReport(report: V4PreflightReport): void {
  mkdirSync(resolve(repoRoot, "docs", "audits"), { recursive: true });
  writeFileSync(reportJsonPath, `${JSON.stringify(report, null, 2)}\n`, {
    encoding: "utf8",
  });
  writeFileSync(reportMarkdownPath, renderMarkdown(report), {
    encoding: "utf8",
  });
}

function safeErrorMessage(error: unknown): string {
  if (error instanceof AggregateError) {
    const nested = error.errors
      .map((item: unknown) => safeErrorMessage(item))
      .filter(Boolean);
    return nested.length > 0
      ? `${error.name}: ${nested.join("; ")}`
      : error.name;
  }
  if (error instanceof Error) {
    const code =
      "code" in error && typeof (error as { code?: unknown }).code === "string"
        ? ` [${String((error as { code: string }).code)}]`
        : "";
    return `${error.name}${code}: ${error.message || "<no message>"}`;
  }
  return String(error);
}

async function main(): Promise<void> {
  const requireZeroBlockers = process.argv.includes("--require-zero-blockers");
  if (!process.argv.includes("--check-read-only") && !requireZeroBlockers) {
    throw new Error(
      "T8.1.3 preflight requires --check-read-only; mutable mode does not exist.",
    );
  }
  const pool = new Pool({
    connectionString: loadDatabaseUrl(),
    max: 1,
    connectionTimeoutMillis: 10_000,
    statement_timeout: 120_000,
    application_name: "magicmusiccrm-v4-read-only-preflight",
  });
  try {
    const report = await runPreflight(pool);
    writeReport(report);
    process.stdout.write(
      `${JSON.stringify({
        task: report.task,
        mode: report.mode,
        summary: report.summary,
        proof: report.proof,
        artifacts: [
          "docs/audits/v4-data-preflight.json",
          "docs/audits/v4-data-preflight.md",
        ],
      })}\n`,
    );
    if (requireZeroBlockers && report.summary.blockerFindings > 0) {
      process.exitCode = 2;
    }
  } finally {
    await pool.end();
  }
}

if (require.main === module) {
  main().catch((error: unknown) => {
    process.stderr.write(`v4 preflight failed: ${safeErrorMessage(error)}\n`);
    process.exitCode = 1;
  });
}

export { runPreflight };
