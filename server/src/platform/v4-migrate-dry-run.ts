import { createHash } from "crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "fs";
import { resolve } from "path";
import { Pool, PoolClient, QueryResultRow } from "pg";

interface MigrationInvariant {
  id: string;
  sourceCount: number;
  targetCount: number;
  violations: number;
}

interface CountRow extends QueryResultRow {
  source_count: string | number;
  target_count: string | number;
  violations: string | number;
}

interface MigrationDryRunReport {
  schemaVersion: 1;
  task: "T8.3.2";
  mode: "repeatable-read/read-only";
  generatedAt: string;
  requiredMigrations: string[];
  missingMigrations: string[];
  invariants: MigrationInvariant[];
  summary: {
    invariants: number;
    sourceRows: number;
    targetRows: number;
    violations: number;
    pendingBatches: number;
  };
  proof: {
    transactionReadOnly: true;
    digestSha256: string;
  };
}

const serverRoot = resolve(__dirname, "..", "..");
const repoRoot = resolve(serverRoot, "..");
const requiredMigrations = [
  "0076_capability_registry",
  "0083_lesson_lifecycle_schema",
  "0087_lesson_settlement_facts",
  "0089_commerce_catalog_snapshot_ledger",
  "0090_commerce_package_aggregate_versions",
  "0091_commerce_issued_subscription_aggregate_versions",
  "0092_shared_tasks_audience_schema",
  "0097_unified_crm_configuration",
  "0098_admin_persona_boundary",
];

const invariantSql: ReadonlyArray<{ id: string; sql: string }> = [
  {
    id: "platform.foreign-key-restore-readiness",
    sql: `
      select 0 as source_count, 0 as target_count,
             (select count(*)
                from app.user_access_versions version
                left join app.users actor on actor.id = version.user_id
               where actor.id is null)
             + (select count(*)
                  from app.issued_subscription_aggregate_version_backfill version
                  left join app.subscriptions subscription
                    on subscription.id = version.subscription_id
                 where subscription.id is null) as violations`,
  },
  {
    id: "access.capability-registry-packages",
    sql: `
      select 23 as source_count,
             (select count(*) from app.capability_definitions where active) as target_count,
             greatest(0, 23 - (select count(*) from app.capability_definitions where active))
             + abs(6 - (select count(*) from app.role_packages where active))
             + abs(138 - (
               select count(*)
                 from app.role_package_capabilities entry
                 join app.role_packages package on package.id = entry.package_id
                where package.active
             )) as violations`,
  },
  {
    id: "access.role-compatible-links",
    sql: `
      with expected as (
        select u.id,
               case
                 when u.role::text = 'client' then 'student'
                 when u.role::text = 'teacher' then 'teacher'
                 when u.role::text in ('admin','manager','director','system_admin')
                   then 'staff'
               end as entity_type
          from app.users u
         where u.deleted_at is null and u.is_app_account
      ), counts as (
        select expected.id, count(link.id) as links
          from expected
          left join app.user_crm_links link
            on link.user_id = expected.id
           and link.entity_type::text = expected.entity_type
           and link.deleted_at is null
         where expected.entity_type is not null
         group by expected.id
      )
      select count(*) as source_count,
             count(*) filter (where links = 1) as target_count,
             count(*) filter (where links <> 1) as violations
        from counts`,
  },
  {
    id: "schedule.lesson-lifecycle-snapshots",
    sql: `
      with source as (
        select lesson.id, lesson.lifecycle_state
          from app.lessons lesson
         where lesson.deleted_at is null
           and coalesce(lesson.lead_id, lesson.student_id) is not null
      ), target as (
        select snapshot.lesson_id
          from app.lesson_snapshots snapshot
          join source on source.id = snapshot.lesson_id
      )
      select (select count(*) from source) as source_count,
             (select count(*) from target) as target_count,
             (select count(*) from source
               where lifecycle_state not in (
                 'scheduled','successfully_completed','cancelled','rescheduled'
               ))
             + ((select count(*) from source) - (select count(*) from target))
               as violations`,
  },
  {
    id: "commerce.subscription-commercial-snapshots",
    sql: `
      select count(*) as source_count,
             count(*) filter (where commercial_snapshot is not null) as target_count,
             count(*) filter (
               where commercial_snapshot is null
                  or version < 1
                  or final_price_minor < 0
             ) as violations
        from app.subscriptions`,
  },
  {
    id: "commerce.lesson-settlement-facts",
    sql: `
      with terminal as (
        select lesson.id
          from app.lessons lesson
         where lesson.deleted_at is null
           and lesson.lifecycle_state = 'successfully_completed'
      ), settled as (
        select terminal.id
          from terminal
          join app.lesson_client_charge_facts client_fact
            on client_fact.lesson_id = terminal.id
          join app.lesson_teacher_compensation_facts teacher_fact
            on teacher_fact.lesson_id = terminal.id
      )
      select (select count(*) from terminal) as source_count,
             (select count(*) from settled) as target_count,
             (select count(*) from terminal)
               - (select count(*) from settled) as violations`,
  },
  {
    id: "workflow.legacy-to-shared-task-links",
    sql: `
      select (select count(*) from app.tasks) as source_count,
             (select count(*) from app.shared_task_legacy_links) as target_count,
             (select count(*)
                from app.tasks task
               where not exists (
                 select 1 from app.shared_task_legacy_links link
                  where link.legacy_task_id = task.id
               )) as violations`,
  },
  {
    id: "workflow.assigned-task-audiences",
    sql: `
      with source as (
        select task.id, task.assigned_to, link.shared_task_id
          from app.tasks task
          join app.shared_task_legacy_links link on link.legacy_task_id = task.id
         where task.assigned_to is not null
      )
      select count(*) as source_count,
             count(*) filter (where exists (
               select 1 from app.task_audiences audience
                where audience.task_id = source.shared_task_id
                  and audience.audience_type = 'user'
                  and audience.target_id = source.assigned_to
             )) as target_count,
             count(*) filter (where not exists (
               select 1 from app.task_audiences audience
                where audience.task_id = source.shared_task_id
                  and audience.audience_type = 'user'
                  and audience.target_id = source.assigned_to
             )) as violations
        from source`,
  },
];

function loadDatabaseUrl(): string {
  const direct =
    process.env.MIGRATION_DATABASE_URL?.trim() ||
    process.env.DATABASE_URL?.trim();
  if (direct) return direct;
  const envPath = resolve(serverRoot, ".env");
  if (existsSync(envPath)) {
    for (const line of readFileSync(envPath, "utf8").split(/\r?\n/)) {
      if (/^(MIGRATION_DATABASE_URL|DATABASE_URL)=/.test(line)) {
        const value = line.slice(line.indexOf("=") + 1).trim();
        if (value) return value;
      }
    }
  }
  throw new Error("MIGRATION_DATABASE_URL or DATABASE_URL is required.");
}

async function collectInvariant(
  client: PoolClient,
  definition: { id: string; sql: string },
): Promise<MigrationInvariant> {
  const result = await client.query<CountRow>(definition.sql);
  const row = result.rows[0];
  if (!row) throw new Error(`Invariant ${definition.id} returned no row.`);
  return {
    id: definition.id,
    sourceCount: Number(row.source_count),
    targetCount: Number(row.target_count),
    violations: Number(row.violations),
  };
}

async function runMigrationDryRun(pool: Pool): Promise<MigrationDryRunReport> {
  const client = await pool.connect();
  try {
    await client.query(
      "begin transaction isolation level repeatable read read only",
    );
    const readOnly = await client.query<{ setting: string }>(
      "select current_setting('transaction_read_only') as setting",
    );
    if (readOnly.rows[0]?.setting !== "on") {
      throw new Error("Migration dry-run transaction is not read-only.");
    }
    const applied = await client.query<{ id: string }>(
      "select id from app_schema_migrations where id = any($1::text[])",
      [requiredMigrations],
    );
    const appliedIds = new Set(applied.rows.map((row) => row.id));
    const missingMigrations = requiredMigrations.filter(
      (id) => !appliedIds.has(id),
    );
    const invariants: MigrationInvariant[] = [];
    for (const definition of invariantSql) {
      invariants.push(await collectInvariant(client, definition));
    }
    const summary = invariants.reduce(
      (value, invariant) => ({
        invariants: value.invariants + 1,
        sourceRows: value.sourceRows + invariant.sourceCount,
        targetRows: value.targetRows + invariant.targetCount,
        violations: value.violations + invariant.violations,
        pendingBatches:
          value.pendingBatches +
          (invariant.sourceCount === invariant.targetCount ? 0 : 1),
      }),
      {
        invariants: 0,
        sourceRows: 0,
        targetRows: 0,
        violations: missingMigrations.length,
        pendingBatches: missingMigrations.length,
      },
    );
    const digestSha256 = createHash("sha256")
      .update(
        JSON.stringify({
          requiredMigrations,
          missingMigrations,
          invariants,
          summary,
        }),
      )
      .digest("hex");
    return {
      schemaVersion: 1,
      task: "T8.3.2",
      mode: "repeatable-read/read-only",
      generatedAt: new Date().toISOString(),
      requiredMigrations,
      missingMigrations,
      invariants,
      summary,
      proof: { transactionReadOnly: true, digestSha256 },
    };
  } finally {
    await client.query("rollback").catch(() => undefined);
    client.release();
  }
}

function writeReport(report: MigrationDryRunReport): string {
  const directory = resolve(repoRoot, "docs", "audits");
  mkdirSync(directory, { recursive: true });
  const path = resolve(directory, "v4-migration-dry-run.json");
  writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`, "utf8");
  return path;
}

async function main(): Promise<void> {
  const pool = new Pool({
    connectionString: loadDatabaseUrl(),
    max: 1,
    connectionTimeoutMillis: 10_000,
    statement_timeout: 120_000,
    application_name: "magicmusiccrm-v4-migration-dry-run",
  });
  try {
    const first = await runMigrationDryRun(pool);
    const second = await runMigrationDryRun(pool);
    if (first.proof.digestSha256 !== second.proof.digestSha256) {
      throw new Error("Repeated migration dry-run changed its logical digest.");
    }
    const path = writeReport(second);
    process.stdout.write(
      `${JSON.stringify({
        task: second.task,
        summary: second.summary,
        repeatedDigestStable: true,
        report: path.replace(`${repoRoot}\\`, "").replace(/\\/g, "/"),
      })}\n`,
    );
    if (second.summary.violations > 0 || second.summary.pendingBatches > 0) {
      process.exitCode = 2;
    }
  } finally {
    await pool.end();
  }
}

if (require.main === module) {
  main().catch((error: unknown) => {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`v4 migration dry-run failed: ${message}\n`);
    process.exitCode = 1;
  });
}

export { requiredMigrations, runMigrationDryRun };
