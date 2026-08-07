import {
  createHash,
  generateKeyPairSync,
  sign,
  verify,
} from "crypto";
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
  | "SYS-SCHEDULE"
  | "SYS-COMMERCE"
  | "SYS-WORKFLOW";
type ReconciliationScope = "all" | "commerce";

interface InvariantDefinition {
  id: string;
  owner: V4System;
  economic: boolean;
  description: string;
  sourceSql: (schema: string) => string;
}

interface FactDiffRow extends QueryResultRow {
  entity_id: string;
  fact_hash: string;
  source_count: number | string;
  target_count: number | string;
}

interface InvariantResult {
  id: string;
  owner: V4System;
  economic: boolean;
  tolerance: 0;
  description: string;
  sourceCount: number;
  targetCount: number;
  sourceDigestSha256: string;
  targetDigestSha256: string;
  unexplainedDiff: Array<{
    entityId: string;
    factHashSha256: string;
    sourceCount: number;
    targetCount: number;
  }>;
}

interface UnsignedReconciliationReport {
  schemaVersion: 1;
  task: "T8.1.5";
  generatedAt: string;
  mode: "fixture" | "schema-compare";
  source: string;
  target: string;
  status: "clean" | "drift";
  tolerancePolicy: {
    economicFacts: 0;
    unexplainedFacts: 0;
  };
  summary: {
    invariants: number;
    sourceFacts: number;
    targetFacts: number;
    invariantsWithDrift: number;
    unexplainedDiff: number;
  };
  invariants: InvariantResult[];
}

interface ReconciliationReport extends UnsignedReconciliationReport {
  signature: {
    algorithm: "Ed25519";
    contentSha256: string;
    publicKeyPem: string;
    valueBase64: string;
    verified: true;
  };
}

const serverRoot = resolve(__dirname, "..", "..");
const repoRoot = resolve(serverRoot, "..");
const cleanFixturePath = resolve(
  repoRoot,
  "scripts",
  "fixtures",
  "v4-reconcile-clean.sql",
);
const driftFixturePath = resolve(
  repoRoot,
  "scripts",
  "fixtures",
  "v4-reconcile-drift.sql",
);

function quoteIdentifier(identifier: string): string {
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(identifier)) {
    throw new Error(`Unsafe schema identifier: ${identifier}`);
  }
  return `"${identifier}"`;
}

function sourceSql(
  table: string,
  columns: string,
  where = "",
): (schema: string) => string {
  return (schema) => `
    select id::text as entity_id, jsonb_build_object(${columns}) as fact
      from ${quoteIdentifier(schema)}.${quoteIdentifier(table)}
      ${where}
  `;
}

const invariants: InvariantDefinition[] = [
  {
    id: "finance.payment-facts",
    owner: "SYS-COMMERCE",
    economic: true,
    description: "Append-only active payment facts remain identical.",
    sourceSql: sourceSql(
      "payments",
      `
        'studentId', student_id::text,
        'amount', amount::text,
        'currency', currency,
        'paymentDate', payment_date::text,
        'externalId', external_id,
        'branchId', branch_id::text,
        'invoiceNumber', invoice_number,
        'lessonId', lesson_id::text,
        'amountMinor', amount_minor::text,
        'issuedSubscriptionId', issued_subscription_id::text,
        'idempotencyRef', idempotency_ref,
        'requestFingerprint', request_fingerprint
        ,'paymentRecordId', payment_record_id::text
      `,
      "where deleted_at is null",
    ),
  },
  {
    id: "finance.adjustment-facts",
    owner: "SYS-COMMERCE",
    economic: true,
    description: "Account adjustment facts and lifecycle remain identical.",
    sourceSql: sourceSql(
      "account_adjustments",
      `
        'studentId', student_id::text,
        'branchId', branch_id::text,
        'kind', kind,
        'amount', amount::text,
        'method', method,
        'counterpartyStudentId', counterparty_student_id::text,
        'occurredAt', occurred_at::text,
        'status', status,
        'invoiceNumber', invoice_number
      `,
      "where deleted_at is null",
    ),
  },
  {
    id: "finance.balance-facts",
    owner: "SYS-COMMERCE",
    economic: true,
    description: "Materialized student balances remain identical.",
    sourceSql: (schema) => `
      select student_id::text as entity_id,
             jsonb_build_object('balance', balance::text) as fact
        from ${quoteIdentifier(schema)}.student_balances
    `,
  },
  {
    id: "commerce.subscription-facts",
    owner: "SYS-COMMERCE",
    economic: true,
    description: "Issued subscription ownership, usage, and links remain identical.",
    sourceSql: sourceSql(
      "subscriptions",
      `
        'studentId', student_id::text,
        'lessonsTotal', lessons_total::text,
        'lessonsUsed', lessons_used::text,
        'startsAt', starts_at::text,
        'expiresAt', expires_at::text,
        'status', status,
        'packageId', package_id::text,
        'paymentId', payment_id::text,
        'snapshotVersion', snapshot_version,
        'packageVersion', package_version,
        'basePriceMinor', base_price_minor::text,
        'currencyCode', currency_code,
        'discountType', discount_type,
        'discountPercentBasisPoints', discount_percent_basis_points,
        'discountFixedMinor', discount_fixed_minor::text,
        'discountReason', discount_reason,
        'finalPriceMinor', final_price_minor::text,
        'commercialSnapshot', commercial_snapshot,
        'version', version::text
        ,'payerStudentId', payer_student_id::text
        ,'fundingMode', funding_mode
        ,'purchaseReason', purchase_reason
      `,
    ),
  },
  {
    id: "commerce.installment-facts",
    owner: "SYS-COMMERCE",
    economic: true,
    description: "Issued installment schedule and lifecycle remain identical.",
    sourceSql: sourceSql(
      "subscription_installments",
      `
        'issuedSubscriptionId', issued_subscription_id::text,
        'installmentNumber', installment_number,
        'dueAt', due_at::text,
        'amountMinor', amount_minor::text,
        'currencyCode', currency_code,
        'status', status,
        'version', version::text
      `,
    ),
  },
  {
    id: "commerce.obligation-facts",
    owner: "SYS-COMMERCE",
    economic: true,
    description: "Append-only subscription obligations remain identical.",
    sourceSql: sourceSql(
      "subscription_obligation_facts",
      `
        'studentId', student_id::text,
        'issuedSubscriptionId', issued_subscription_id::text,
        'factType', fact_type,
        'direction', direction,
        'amountMinor', amount_minor::text,
        'currencyCode', currency_code,
        'sourceType', source_type,
        'sourceRef', source_ref,
        'occurredAt', occurred_at::text
      `,
    ),
  },
  {
    id: "commerce.lifecycle-facts",
    owner: "SYS-COMMERCE",
    economic: false,
    description: "Subscription issue/replace/cancel history remains identical.",
    sourceSql: sourceSql(
      "subscription_lifecycle_events",
      `
        'issuedSubscriptionId', issued_subscription_id::text,
        'eventType', event_type,
        'beforeId', before_issued_subscription_id::text,
        'afterId', after_issued_subscription_id::text,
        'actorUserId', actor_user_id::text,
        'reason', reason,
        'aggregateVersion', aggregate_version::text,
        'occurredAt', occurred_at::text
      `,
    ),
  },
  {
    id: "commerce.client-payment-records",
    owner: "SYS-COMMERCE",
    economic: true,
    description: "Three-state client payment aggregates remain identical.",
    sourceSql: sourceSql(
      "client_payment_records",
      `
        'studentId', student_id::text,
        'issuedSubscriptionId', issued_subscription_id::text,
        'installmentId', installment_id::text,
        'amountMinor', amount_minor::text,
        'currencyCode', currency_code,
        'status', status,
        'dueAt', due_at::text,
        'actualPaymentId', actual_payment_id::text,
        'version', version::text
      `,
    ),
  },
  {
    id: "commerce.client-payment-status-events",
    owner: "SYS-COMMERCE",
    economic: false,
    description: "Payment status history and reasons remain identical.",
    sourceSql: sourceSql(
      "client_payment_status_events",
      `
        'paymentRecordId', payment_record_id::text,
        'beforeStatus', before_status,
        'afterStatus', after_status,
        'reason', reason,
        'actorUserId', actor_user_id::text,
        'aggregateVersion', aggregate_version::text,
        'actualPaymentId', actual_payment_id::text,
        'occurredAt', occurred_at::text
      `,
    ),
  },
  {
    id: "commerce.reporting-exclusions",
    owner: "SYS-COMMERCE",
    economic: true,
    description: "Reporting source/counterpart exclusions remain identical.",
    sourceSql: sourceSql(
      "commerce_reporting_exclusions",
      `
        'sourceKind', source_kind,
        'sourceId', source_id::text,
        'counterpartKind', counterpart_kind,
        'counterpartId', counterpart_id::text,
        'reason', reason,
        'actorUserId', actor_user_id::text,
        'occurredAt', occurred_at::text
      `,
    ),
  },
  {
    id: "commerce.lesson-charge-facts",
    owner: "SYS-COMMERCE",
    economic: true,
    description: "Immutable Lesson client charge facts remain identical.",
    sourceSql: sourceSql(
      "lesson_client_charge_facts",
      `
        'lessonId', lesson_id::text,
        'clientType', client_type,
        'clientId', client_id::text,
        'chargeType', charge_type,
        'snapshotValue', snapshot_value::text,
        'subscriptionId', subscription_id::text,
        'amountMinor', amount_minor::text,
        'units', units::text,
        'currencyCode', currency_code,
        'createdAt', created_at::text
        ,'settlementTypeKey', settlement_type_key
        ,'settlementLabel', settlement_label
        ,'settlementColorToken', settlement_color_token
        ,'hourShareBasisPoints', hour_share_basis_points
        ,'fixedPenaltyMinor', fixed_penalty_minor::text
        ,'configurationRevisionId', configuration_revision_id::text
      `,
    ),
  },
  {
    id: "commerce.teacher-compensation-facts",
    owner: "SYS-COMMERCE",
    economic: true,
    description: "Immutable Lesson teacher compensation facts remain identical.",
    sourceSql: sourceSql(
      "lesson_teacher_compensation_facts",
      `
        'lessonId', lesson_id::text,
        'teacherId', teacher_id::text,
        'compensationType', compensation_type,
        'snapshotRate', snapshot_rate::text,
        'rateMinor', rate_minor::text,
        'durationMinutes', duration_minutes,
        'amountMinor', amount_minor::text,
        'currencyCode', currency_code,
        'createdAt', created_at::text
        ,'compensationRuleKey', compensation_rule_key
        ,'compensationRuleLabel', compensation_rule_label
        ,'compensationMode', compensation_mode
        ,'compensationDefaultValue', compensation_default_value::text
        ,'compensationActualValue', compensation_actual_value::text
        ,'compensationOverrideReason', compensation_override_reason
        ,'configurationRevisionId', configuration_revision_id::text
      `,
    ),
  },
  {
    id: "commerce.reservation-facts",
    owner: "SYS-COMMERCE",
    economic: false,
    description: "Lesson coverage allocation and terminal state remain identical.",
    sourceSql: sourceSql(
      "lesson_reservations",
      `
        'lessonId', lesson_id::text,
        'subscriptionId', subscription_id::text,
        'units', units::text,
        'state', state,
        'version', version::text,
        'financialFactId', financial_fact_id::text,
        'terminalAt', terminal_at::text
      `,
    ),
  },
  {
    id: "schedule.lesson-facts",
    owner: "SYS-SCHEDULE",
    economic: false,
    description: "Lesson lifecycle, resources, and audience remain identical.",
    sourceSql: sourceSql(
      "lessons",
      `
        'studentId', student_id::text,
        'groupId', group_id::text,
        'leadId', lead_id::text,
        'teacherId', teacher_id::text,
        'branchId', branch_id::text,
        'roomId', room_id::text,
        'scheduledAt', scheduled_at::text,
        'durationMinutes', duration_minutes,
        'status', status,
        'isTrial', is_trial,
        'seriesId', series_id::text,
        'teacherRate', teacher_rate::text
      `,
      "where deleted_at is null",
    ),
  },
  {
    id: "schedule.participation-facts",
    owner: "SYS-SCHEDULE",
    economic: true,
    description: "Attendance and charge participation facts remain identical.",
    sourceSql: sourceSql(
      "lesson_participation",
      `
        'lessonId', lesson_id::text,
        'studentId', student_id::text,
        'status', status,
        'subscriptionId', subscription_id::text,
        'attendanceKind', attendance_kind,
        'chargeShare', charge_share::text,
        'chargedHours', charged_hours::text
      `,
    ),
  },
  {
    id: "workflow.task-facts",
    owner: "SYS-WORKFLOW",
    economic: false,
    description: "Task target, audience, lifecycle, and version inputs remain identical.",
    sourceSql: sourceSql(
      "tasks",
      `
        'entityType', entity_type::text,
        'entityId', entity_id::text,
        'status', status,
        'dueAt', due_at::text,
        'assignedTo', assigned_to::text,
        'branchId', branch_id::text,
        'priority', priority,
        'dueAllDay', due_all_day
      `,
      "where deleted_at is null",
    ),
  },
  {
    id: "access.role-mappings",
    owner: "SYS-ACCESS",
    economic: false,
    description: "Application role and CRM entity mappings remain identical.",
    sourceSql: (schema) => `
      select
        concat(u.id::text, ':', coalesce(link.id::text, 'none')) as entity_id,
        jsonb_build_object(
          'userId', u.id::text,
          'role', u.role::text,
          'isAppAccount', u.is_app_account,
          'entityType', link.entity_type::text,
          'entityId', link.entity_id::text,
          'linkSource', link.link_source
        ) as fact
      from ${quoteIdentifier(schema)}.users u
      left join ${quoteIdentifier(schema)}.user_crm_links link
        on link.user_id = u.id and link.deleted_at is null
      where u.deleted_at is null
    `,
  },
];

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
  if (!line) throw new Error("DATABASE_URL is not defined in server/.env.");
  const raw = line.slice(line.indexOf("=") + 1).trim();
  const value =
    (raw.startsWith('"') && raw.endsWith('"')) ||
    (raw.startsWith("'") && raw.endsWith("'"))
      ? raw.slice(1, -1)
      : raw;
  if (!value) throw new Error("DATABASE_URL is empty.");
  return value;
}

function argumentValue(name: string): string | undefined {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

function canonicalize(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .filter(([key]) => key !== "signature")
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, entry]) => [key, canonicalize(entry)]),
    );
  }
  return value;
}

function canonicalJson(value: unknown): string {
  return JSON.stringify(canonicalize(value));
}

function signReport(
  unsigned: UnsignedReconciliationReport,
): ReconciliationReport {
  const content = Buffer.from(canonicalJson(unsigned), "utf8");
  const { publicKey, privateKey } = generateKeyPairSync("ed25519");
  const valueBase64 = sign(null, content, privateKey).toString("base64");
  const publicKeyPem = publicKey.export({
    type: "spki",
    format: "pem",
  }) as string;
  if (
    !verify(
      null,
      content,
      publicKey,
      Buffer.from(valueBase64, "base64"),
    )
  ) {
    throw new Error("Generated reconciliation signature did not verify.");
  }
  return {
    ...unsigned,
    signature: {
      algorithm: "Ed25519",
      contentSha256: createHash("sha256").update(content).digest("hex"),
      publicKeyPem,
      valueBase64,
      verified: true,
    },
  };
}

async function createFactTables(client: PoolClient): Promise<void> {
  await client.query(`
    create temporary table v4_reconcile_source_facts (
      invariant_id text not null,
      entity_id text not null,
      fact jsonb not null
    );
    create temporary table v4_reconcile_target_facts (
      invariant_id text not null,
      entity_id text not null,
      fact jsonb not null
    );
  `);
}

async function populateSchemaFacts(
  client: PoolClient,
  side: "source" | "target",
  schema: string,
  definitions: readonly InvariantDefinition[],
): Promise<void> {
  for (const invariant of definitions) {
    await client.query(
      `
        insert into v4_reconcile_${side}_facts (
          invariant_id,
          entity_id,
          fact
        )
        select $1, entity_id, fact
          from (${invariant.sourceSql(schema)}) normalized
      `,
      [invariant.id],
    );
  }
}

async function compareInvariant(
  client: PoolClient,
  definition: InvariantDefinition,
): Promise<InvariantResult> {
  const counts = await client.query<{
    source_count: number | string;
    target_count: number | string;
    source_digest: string;
    target_digest: string;
  }>(
    `
      select
        (
          select count(*)
            from v4_reconcile_source_facts
           where invariant_id = $1
        ) as source_count,
        (
          select count(*)
            from v4_reconcile_target_facts
           where invariant_id = $1
        ) as target_count,
        (
          select encode(
            digest(
              coalesce(
                string_agg(
                  entity_id || ':' || fact::text,
                  E'\\n' order by entity_id, fact::text
                ),
                ''
              ),
              'sha256'
            ),
            'hex'
          )
            from v4_reconcile_source_facts
           where invariant_id = $1
        ) as source_digest,
        (
          select encode(
            digest(
              coalesce(
                string_agg(
                  entity_id || ':' || fact::text,
                  E'\\n' order by entity_id, fact::text
                ),
                ''
              ),
              'sha256'
            ),
            'hex'
          )
            from v4_reconcile_target_facts
           where invariant_id = $1
        ) as target_digest
    `,
    [definition.id],
  );
  const diff = await client.query<FactDiffRow>(
    `
      with source as (
        select
          entity_id,
          encode(digest(fact::text, 'sha256'), 'hex') as fact_hash,
          count(*) as fact_count
        from v4_reconcile_source_facts
        where invariant_id = $1
        group by entity_id, fact
      ),
      target as (
        select
          entity_id,
          encode(digest(fact::text, 'sha256'), 'hex') as fact_hash,
          count(*) as fact_count
        from v4_reconcile_target_facts
        where invariant_id = $1
        group by entity_id, fact
      )
      select
        coalesce(source.entity_id, target.entity_id) as entity_id,
        coalesce(source.fact_hash, target.fact_hash) as fact_hash,
        coalesce(source.fact_count, 0) as source_count,
        coalesce(target.fact_count, 0) as target_count
      from source
      full join target
        on target.entity_id = source.entity_id
       and target.fact_hash = source.fact_hash
      where coalesce(source.fact_count, 0) <> coalesce(target.fact_count, 0)
      order by entity_id, fact_hash
    `,
    [definition.id],
  );
  const row = counts.rows[0];
  if (!row) throw new Error(`Missing counts for ${definition.id}.`);
  return {
    id: definition.id,
    owner: definition.owner,
    economic: definition.economic,
    tolerance: 0,
    description: definition.description,
    sourceCount: Number(row.source_count),
    targetCount: Number(row.target_count),
    sourceDigestSha256: row.source_digest,
    targetDigestSha256: row.target_digest,
    unexplainedDiff: diff.rows.map((item) => ({
      entityId: item.entity_id,
      factHashSha256: item.fact_hash,
      sourceCount: Number(item.source_count),
      targetCount: Number(item.target_count),
    })),
  };
}

async function reconcile(
  client: PoolClient,
  definitions: readonly InvariantDefinition[],
): Promise<InvariantResult[]> {
  const results: InvariantResult[] = [];
  for (const invariant of definitions) {
    results.push(await compareInvariant(client, invariant));
  }
  return results;
}

function writeReport(
  report: ReconciliationReport,
  label: string,
): string {
  const directory = resolve(repoRoot, "docs", "audits");
  mkdirSync(directory, { recursive: true });
  const path = resolve(directory, `v4-reconciliation-${label}.json`);
  writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`, "utf8");
  return path;
}

async function run(): Promise<{
  report: ReconciliationReport;
  reportPath: string;
}> {
  const fixture = argumentValue("--fixture");
  if (fixture !== undefined && !["clean", "drift"].includes(fixture)) {
    throw new Error("--fixture must be clean or drift.");
  }
  const sourceSchema = argumentValue("--source-schema") ?? "app";
  const targetSchema = argumentValue("--target-schema") ?? "app";
  const rawScope = argumentValue("--scope") ?? "all";
  if (!["all", "commerce"].includes(rawScope)) {
    throw new Error("--scope must be all or commerce.");
  }
  const scope = rawScope as ReconciliationScope;
  const definitions =
    scope === "commerce"
      ? invariants.filter((invariant) => invariant.owner === "SYS-COMMERCE")
      : invariants;
  const pool = new Pool({
    connectionString: loadDatabaseUrl(),
    max: 1,
    connectionTimeoutMillis: 10_000,
    statement_timeout: 120_000,
    application_name: "magicmusiccrm-v4-reconciliation",
  });
  const client = await pool.connect();
  try {
    await createFactTables(client);
    await client.query(
      "begin transaction isolation level repeatable read read only",
    );
    if (fixture) {
      await client.query(readFileSync(cleanFixturePath, "utf8"));
      if (fixture === "drift") {
        await client.query(readFileSync(driftFixturePath, "utf8"));
      }
    } else {
      await populateSchemaFacts(client, "source", sourceSchema, definitions);
      await populateSchemaFacts(client, "target", targetSchema, definitions);
    }
    const results = await reconcile(client, definitions);
    const summary = results.reduce(
      (value, invariant) => {
        value.sourceFacts += invariant.sourceCount;
        value.targetFacts += invariant.targetCount;
        if (invariant.unexplainedDiff.length > 0) {
          value.invariantsWithDrift += 1;
          value.unexplainedDiff += invariant.unexplainedDiff.reduce(
            (count, diff) =>
              count + Math.abs(diff.sourceCount - diff.targetCount),
            0,
          );
        }
        return value;
      },
      {
        invariants: results.length,
        sourceFacts: 0,
        targetFacts: 0,
        invariantsWithDrift: 0,
        unexplainedDiff: 0,
      },
    );
    const unsigned: UnsignedReconciliationReport = {
      schemaVersion: 1,
      task: "T8.1.5",
      generatedAt: new Date().toISOString(),
      mode: fixture ? "fixture" : "schema-compare",
      source: fixture ? `${fixture}:source` : sourceSchema,
      target: fixture ? `${fixture}:target` : targetSchema,
      status: summary.unexplainedDiff === 0 ? "clean" : "drift",
      tolerancePolicy: {
        economicFacts: 0,
        unexplainedFacts: 0,
      },
      summary,
      invariants: results,
    };
    const report = signReport(unsigned);
    const baseLabel = fixture ?? `${sourceSchema}-to-${targetSchema}`;
    const label = scope === "all" ? baseLabel : `${scope}-${baseLabel}`;
    return { report, reportPath: writeReport(report, label) };
  } finally {
    try {
      await client.query("rollback");
    } finally {
      client.release();
      await pool.end();
    }
  }
}

async function main(): Promise<void> {
  const expectFail = process.argv.includes("--expect-fail");
  const { report, reportPath } = await run();
  process.stdout.write(
    `${JSON.stringify({
      task: report.task,
      status: report.status,
      summary: report.summary,
      signatureVerified: report.signature.verified,
      report: reportPath.replace(`${repoRoot}\\`, "").replace(/\\/g, "/"),
    })}\n`,
  );
  if (expectFail && report.status !== "drift") {
    throw new Error("Expected reconciliation drift, but report is clean.");
  }
  if (!expectFail && report.status === "drift") {
    process.exitCode = 1;
  }
}

if (require.main === module) {
  main().catch((error: unknown) => {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`v4 reconciliation failed: ${message}\n`);
    process.exitCode = 1;
  });
}

export {
  canonicalJson,
  invariants,
  run,
  signReport,
};
