import {
  createReadStream,
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { createInterface } from "node:readline";
import { join, resolve } from "node:path";
import { Pool, PoolClient } from "pg";
import { LegacyFileMapEntry } from "./storage-import-utils";
import {
  ImportWarning,
  SourceRow,
  TargetRow,
  asBoolean,
  asJsonObject,
  asNumber,
  asString,
  compactObject,
  deterministicUuid,
  directChatId,
  isUuid,
  normalizeDeletionStatus,
  normalizeLegalDocumentType,
  normalizeMessageType,
  normalizeRole,
  nullableUuid,
  sha256Hex,
  splitFullName,
} from "./v3-import-utils";

interface ImportConfig {
  exportDir: string;
  connectionString: string;
  dryRun: boolean;
  batchSize: number;
  fileMapPath: string;
}

interface ImportContext {
  exportDir: string;
  rowsBySource: Map<string, SourceRow[]>;
  warnings: ImportWarning[];
  authUsersById: Map<string, SourceRow>;
  profilesById: Map<string, SourceRow>;
  leadStatusesByKey: Map<string, string>;
  adminThreadByClientId: Map<string, string>;
  messagesById: Map<string, SourceRow>;
  legacyFileEntries: LegacyFileMapEntry[];
  fileIdByLegacyKey: Map<string, string>;
}

interface ImportReport {
  importId: string;
  startedAt: string;
  finishedAt: string;
  mode: "dry-run" | "live";
  source: {
    exportDir: string;
    exportId?: string;
  };
  target: {
    database: string;
  };
  totals: {
    sourceRows: number;
    plannedRows: number;
    insertedOrSkippedRows: number;
    skippedRows: number;
    warnings: number;
  };
  tables: Array<{
    table: string;
    plannedRows: number;
    insertedOrSkippedRows: number;
  }>;
  skippedSources: Array<{
    source: string;
    rows: number;
    reason: string;
  }>;
  warnings: ImportWarning[];
}

interface PlanResult {
  rows: TargetRow[];
  skippedSources: ImportReport["skippedSources"];
}

const DATA_SOURCE_FILES = [
  "auth.users",
  "auth.identities",
  "public.profiles",
  "public.branches",
  "public.rooms",
  "public.lead_statuses",
  "public.leads",
  "public.students",
  "public.teachers",
  "public.groups",
  "public.group_students",
  "public.lessons",
  "public.lesson_participation",
  "public.tasks",
  "public.payments",
  "public.expenses",
  "public.expected_payments",
  "public.subscriptions",
  "public.student_balances",
  "public.system_settings",
  "public.entity_comments",
  "public.profile_notes",
  "public.lead_comments",
  "public.legal_documents",
  "public.legal_consents",
  "public.account_deletion_requests",
  "public.admin_chat_threads",
  "public.group_chats",
  "public.group_chat_members",
  "public.messages",
  "public.message_reactions",
  "public.channels",
  "public.channel_permissions",
  "public.channel_posts",
  "public.notifications",
  "public.notification_recipients",
  "public.fcm_tokens",
];

class V3ImportPipeline {
  private readonly pool: Pool;

  constructor(private readonly config: ImportConfig) {
    this.pool = new Pool({
      connectionString: config.connectionString,
      max: 2,
      connectionTimeoutMillis: 10_000,
      idleTimeoutMillis: 30_000,
    });
  }

  async run(): Promise<ImportReport> {
    const startedAt = new Date().toISOString();
    const importId = `v3-import-${startedAt.replace(/[:.]/g, "-")}`;
    const warnings: ImportWarning[] = [];

    try {
      const rowsBySource = await this.readSources(warnings);
      const context = this.buildContext(rowsBySource, warnings);
      const plan = this.buildPlan(context);
      const tableStats = this.groupPlanRows(plan.rows);

      const client = await this.pool.connect();
      try {
        await client.query("begin");
        const insertedOrSkippedRows = await this.insertPlan(client, plan.rows);
        if (this.config.dryRun) {
          await client.query("rollback");
        } else {
          await client.query("commit");
        }

        const exportReport = this.readExportReport();
        const report: ImportReport = {
          importId,
          startedAt,
          finishedAt: new Date().toISOString(),
          mode: this.config.dryRun ? "dry-run" : "live",
          source: {
            exportDir: this.config.exportDir,
            exportId: asString(exportReport?.exportId),
          },
          target: {
            database: this.redactConnectionString(this.config.connectionString),
          },
          totals: {
            sourceRows: [...rowsBySource.values()].reduce(
              (sum, rows) => sum + rows.length,
              0,
            ),
            plannedRows: plan.rows.length,
            insertedOrSkippedRows,
            skippedRows: plan.skippedSources.reduce(
              (sum, source) => sum + source.rows,
              0,
            ),
            warnings: warnings.length,
          },
          tables: tableStats.map((table) => ({
            ...table,
            insertedOrSkippedRows: table.plannedRows,
          })),
          skippedSources: plan.skippedSources,
          warnings,
        };
        this.writeReport(report);
        return report;
      } catch (error) {
        await client.query("rollback");
        throw error;
      } finally {
        client.release();
      }
    } finally {
      await this.pool.end();
    }
  }

  private async readSources(
    warnings: ImportWarning[],
  ): Promise<Map<string, SourceRow[]>> {
    const rowsBySource = new Map<string, SourceRow[]>();
    for (const source of DATA_SOURCE_FILES) {
      const file = join(this.config.exportDir, "data", `${source}.ndjson`);
      if (!existsSync(file)) {
        rowsBySource.set(source, []);
        warnings.push({
          code: "source_file_missing",
          source,
          message: `Source file is missing and will be treated as empty: ${source}.ndjson`,
        });
        continue;
      }
      rowsBySource.set(source, await readNdjson(file));
    }
    return rowsBySource;
  }

  private buildContext(
    rowsBySource: Map<string, SourceRow[]>,
    warnings: ImportWarning[],
  ): ImportContext {
    const authUsersById = indexById(rowsBySource.get("auth.users") ?? []);
    const profilesById = indexById(rowsBySource.get("public.profiles") ?? []);
    const messagesById = indexById(rowsBySource.get("public.messages") ?? []);
    const leadStatusesByKey = new Map<string, string>();
    for (const status of rowsBySource.get("public.lead_statuses") ?? []) {
      const id = asString(status.id);
      for (const key of [status.id, status.key, status.label, status.name]) {
        const normalized = asString(key)?.toLowerCase();
        if (id && normalized) leadStatusesByKey.set(normalized, id);
      }
    }

    const adminThreadByClientId = new Map<string, string>();
    for (const thread of rowsBySource.get("public.admin_chat_threads") ?? []) {
      const threadId = asString(thread.id);
      const clientId =
        asString(thread.client_id) ??
        asString(thread.user_id) ??
        asString(thread.profile_id);
      if (threadId && clientId) adminThreadByClientId.set(clientId, threadId);
    }

    const legacyFileEntries = this.readFileMap(warnings);
    const fileIdByLegacyKey = new Map<string, string>();
    for (const entry of legacyFileEntries) {
      fileIdByLegacyKey.set(entry.name, entry.id);
      fileIdByLegacyKey.set(`${entry.bucketId}/${entry.name}`, entry.id);
      for (const key of entry.legacyKeys) fileIdByLegacyKey.set(key, entry.id);
    }

    return {
      exportDir: this.config.exportDir,
      rowsBySource,
      warnings,
      authUsersById,
      profilesById,
      leadStatusesByKey,
      adminThreadByClientId,
      messagesById,
      legacyFileEntries,
      fileIdByLegacyKey,
    };
  }

  private buildPlan(context: ImportContext): PlanResult {
    const rows: TargetRow[] = [];
    const skippedSources: ImportReport["skippedSources"] = [];

    const addMany = (
      source: string,
      transform: (row: SourceRow) => TargetRow | TargetRow[] | undefined,
    ): void => {
      const sourceRows = context.rowsBySource.get(source) ?? [];
      let skipped = 0;
      for (const sourceRow of sourceRows) {
        const transformed = transform(sourceRow);
        if (!transformed) {
          skipped += 1;
          continue;
        }
        if (Array.isArray(transformed)) rows.push(...transformed);
        else rows.push(transformed);
      }
      if (skipped > 0) {
        skippedSources.push({
          source,
          rows: skipped,
          reason: "Rows did not have required fields for v3 constraints.",
        });
      }
    };

    addMany("auth.users", (row) => this.userFromAuth(row, context));
    addMany("public.profiles", (row) => this.userFromProfile(row, context));
    addMany("auth.identities", (row) => this.identityFromAuth(row));
    addMany("public.profiles", (row) => this.profileFromLegacy(row, context));
    addMany("public.branches", (row) =>
      this.simpleRow(
        "app.branches",
        ["id"],
        row,
        {
          id: row.id,
          name: asString(row.name),
          address: asString(row.address),
          created_at: row.created_at,
        },
        ["id", "name"],
      ),
    );
    addMany("public.rooms", (row) =>
      this.simpleRow(
        "app.rooms",
        ["id"],
        row,
        {
          id: row.id,
          branch_id: nullableUuid(row.branch_id),
          name: asString(row.name),
          capacity: asNumber(row.capacity),
          created_at: row.created_at,
        },
        ["id", "name"],
      ),
    );
    addMany("public.lead_statuses", (row) =>
      this.simpleRow(
        "app.lead_statuses",
        ["id"],
        row,
        {
          id: row.id,
          name: asString(row.label) ?? asString(row.name) ?? asString(row.key),
          color: asString(row.color),
          sort_order: asNumber(row.sort_order) ?? 0,
          created_at: row.created_at,
        },
        ["id", "name"],
      ),
    );
    addMany("public.leads", (row) => this.leadFromLegacy(row, context));
    addMany("public.students", (row) => this.studentFromLegacy(row));
    addMany("public.teachers", (row) => this.teacherFromLegacy(row));
    addMany("public.groups", (row) =>
      this.simpleRow(
        "app.groups",
        ["id"],
        row,
        {
          id: row.id,
          teacher_id: nullableUuid(row.teacher_id),
          branch_id: nullableUuid(row.branch_id),
          name: asString(row.name),
          price_per_lesson: row.price_per_lesson,
          created_at: row.created_at,
        },
        ["id", "name"],
      ),
    );
    addMany("public.group_students", (row) =>
      this.simpleRow(
        "app.group_students",
        ["group_id", "student_id"],
        row,
        {
          group_id: row.group_id,
          student_id: row.student_id,
          joined_at: row.created_at,
        },
        ["group_id", "student_id"],
      ),
    );
    addMany("public.lessons", (row) => this.lessonFromLegacy(row));
    addMany("public.lesson_participation", (row) =>
      this.simpleRow(
        "app.lesson_participation",
        ["lesson_id", "student_id"],
        row,
        {
          lesson_id: row.lesson_id,
          student_id: row.student_id,
          status:
            asString(row.status) ??
            (asBoolean(row.is_present) === false ? "absent" : "scheduled"),
          pass_reason:
            asString(row.pass_reason) ??
            asString(row.absence_reason) ??
            asString(row.reason),
        },
        ["lesson_id", "student_id"],
      ),
    );
    addMany("public.tasks", (row) => this.taskFromLegacy(row));
    addMany("public.payments", (row) =>
      this.simpleRow(
        "app.payments",
        ["id"],
        row,
        {
          id: row.id,
          student_id: row.student_id,
          amount: row.amount,
          payment_date: row.payment_date ?? row.created_at,
          method: asString(row.type),
          external_id: asString(row.hollihop_id),
          notes: asString(row.description),
          created_at: row.created_at,
        },
        ["id", "student_id", "amount"],
      ),
    );
    addMany("public.expenses", (row) =>
      this.simpleRow(
        "app.expenses",
        ["id"],
        row,
        {
          id: row.id,
          amount: row.amount,
          category: asString(row.category) ?? "legacy",
          description: asString(row.description),
          created_at: row.created_at,
        },
        ["id", "amount", "category"],
      ),
    );
    addMany("public.expected_payments", (row) =>
      this.simpleRow(
        "app.expected_payments",
        ["id"],
        row,
        {
          id: row.id,
          student_id: row.student_id,
          amount: row.amount,
          due_date: row.due_date,
          status: asString(row.status) ?? "pending",
          description: asString(row.description) ?? asString(row.notes),
          created_at: row.created_at,
        },
        ["id", "student_id", "amount"],
      ),
    );
    addMany("public.subscriptions", (row) =>
      this.simpleRow(
        "app.subscriptions",
        ["id"],
        row,
        {
          id: row.id,
          student_id: row.student_id,
          lessons_total: asNumber(row.lessons_total) ?? 0,
          lessons_used: asNumber(row.lessons_used) ?? 0,
          expires_at: row.valid_until,
          status: asString(row.status) ?? "active",
          created_at: row.created_at,
        },
        ["id", "student_id"],
      ),
    );
    addMany("public.student_balances", (row) =>
      this.simpleRow(
        "app.student_balances",
        ["student_id"],
        row,
        {
          student_id: row.student_id,
          balance: row.balance ?? 0,
        },
        ["student_id"],
      ),
    );
    addMany("public.system_settings", (row) =>
      this.simpleRow(
        "app.system_settings",
        ["key"],
        row,
        {
          key: asString(row.key),
          value: row.value ?? null,
          updated_at: row.updated_at ?? row.created_at,
        },
        ["key"],
      ),
    );
    addMany("public.entity_comments", (row) => this.commentFromLegacy(row));
    addMany("public.profile_notes", (row) =>
      this.simpleRow(
        "app.profile_notes",
        ["id"],
        row,
        {
          id: row.id,
          profile_id: row.profile_id,
          author_id: nullableUuid(row.author_id),
          body:
            asString(row.content) ?? asString(row.body) ?? asString(row.note),
          created_at: row.created_at,
        },
        ["id", "profile_id", "body"],
      ),
    );
    addMany("public.lead_comments", (row) =>
      this.simpleRow(
        "app.lead_comments",
        ["id"],
        row,
        {
          id: row.id,
          lead_id: row.lead_id,
          author_id: nullableUuid(row.author_id),
          body:
            asString(row.content) ?? asString(row.body) ?? asString(row.note),
          created_at: row.created_at,
        },
        ["id", "lead_id", "body"],
      ),
    );
    addMany("public.legal_documents", (row) =>
      this.legalDocumentFromLegacy(row, context),
    );
    addMany("public.legal_consents", (row) =>
      this.simpleRow(
        "app.legal_consents",
        ["user_id", "document_id"],
        row,
        {
          id: row.id,
          user_id: row.user_id,
          document_id: row.document_id,
          version:
            asString(row.accepted_version) ?? asString(row.version) ?? "legacy",
          accepted_at: row.accepted_at,
        },
        ["user_id", "document_id"],
      ),
    );
    addMany("public.account_deletion_requests", (row) =>
      this.simpleRow(
        "app.account_deletion_requests",
        ["id"],
        row,
        {
          id: row.id,
          user_id: row.user_id,
          status: normalizeDeletionStatus(row.status),
          reason: asString(row.reason),
          requested_at: row.requested_at,
          resolved_at: row.processed_at,
          resolved_by: nullableUuid(row.processed_by),
          resolution_note: asString(row.staff_note),
        },
        ["id", "user_id"],
      ),
    );
    addMany("public.admin_chat_threads", (row) =>
      this.adminChatFromLegacy(row),
    );
    addMany("public.group_chats", (row) => this.groupChatFromLegacy(row));
    addMany("public.group_chat_members", (row) =>
      this.groupChatMemberFromLegacy(row),
    );
    addMany("public.messages", (row) =>
      this.directChatFromMessage(row, context),
    );
    addMany("public.messages", (row) =>
      this.directChatMembersFromMessage(row, context),
    );
    addMany("public.messages", (row) => this.messageFromLegacy(row, context));
    addMany("public.message_reactions", (row) =>
      this.messageReactionFromLegacy(row, context),
    );
    addMany("public.channels", (row) =>
      this.simpleRow(
        "app.channels",
        ["id"],
        row,
        {
          id: row.id,
          title: asString(row.name) ?? asString(row.title),
          description: asString(row.description),
          created_by: nullableUuid(row.created_by),
          created_at: row.created_at,
        },
        ["id", "title"],
      ),
    );
    addMany("public.channel_permissions", (row) =>
      this.channelPermissionFromLegacy(row),
    );
    addMany("public.channel_posts", (row) =>
      this.simpleRow(
        "app.channel_posts",
        ["id"],
        row,
        {
          id: row.id,
          channel_id: row.channel_id,
          author_id: nullableUuid(row.author_id),
          content: asString(row.content) ?? "[legacy attachment]",
          attachment_file_id: this.lookupLegacyFileId(
            row.attachment_url,
            context,
          ),
          published_at: row.created_at,
          updated_at: row.updated_at ?? row.created_at,
        },
        ["id", "channel_id", "content"],
      ),
    );
    addMany("public.notifications", (row) => this.notificationFromLegacy(row));
    addMany("public.notification_recipients", (row) =>
      this.simpleRow(
        "app.notification_recipients",
        ["notification_id", "user_id"],
        row,
        {
          id: row.id,
          notification_id: row.notification_id,
          user_id: row.user_id,
          is_read: asBoolean(row.is_read) ?? false,
          read_at: row.read_at,
          created_at: row.created_at,
        },
        ["notification_id", "user_id"],
      ),
    );
    addMany("public.fcm_tokens", (row) =>
      this.notificationDeviceFromLegacy(row),
    );

    context.warnings.push({
      code:
        context.legacyFileEntries.length > 0
          ? "file_references_mapped"
          : "file_references_deferred",
      message:
        context.legacyFileEntries.length > 0
          ? "Legacy file reference rewrite used the provided file migration map where avatar_url and attachment_url matched exported Storage objects."
          : "Legacy avatar_url and attachment_url values were preserved only as metadata because no file migration map was provided.",
    });

    return { rows, skippedSources };
  }

  private userFromAuth(
    row: SourceRow,
    context: ImportContext,
  ): TargetRow | undefined {
    const id = asString(row.id);
    const profile = id ? context.profilesById.get(id) : undefined;
    const email = asString(row.email) ?? asString(profile?.email);
    if (!id || !email) return undefined;
    const profileName = splitFullName(profile ?? {});
    const rawMetadata = asJsonObject(row.raw_user_meta_data);
    const metadataName =
      asString(rawMetadata.full_name) ?? asString(rawMetadata.name);
    return {
      table: "app.users",
      conflictColumns: ["id"],
      data: compactObject({
        id,
        email,
        password_hash: null,
        full_name:
          [profileName.firstName, profileName.lastName]
            .filter(Boolean)
            .join(" ") ||
          metadataName ||
          null,
        phone: asString(row.phone) ?? asString(profile?.phone),
        role: normalizeRole(
          profile?.role ?? asJsonObject(row.raw_app_meta_data).role,
        ),
        email_verified_at: row.email_confirmed_at ?? row.confirmed_at,
        profile_completed: Boolean(profile?.profile_completed_at),
        created_at: row.created_at,
        updated_at: row.updated_at,
        deleted_at: row.deleted_at,
      }),
    };
  }

  private userFromProfile(
    row: SourceRow,
    context: ImportContext,
  ): TargetRow | undefined {
    const id = asString(row.id);
    if (!id || context.authUsersById.has(id)) return undefined;
    const email = asString(row.email) ?? `legacy-${id}@migration.invalid`;
    if (email.endsWith("@migration.invalid")) {
      context.warnings.push({
        code: "missing_legacy_email",
        source: "public.profiles",
        rowId: id,
        message:
          "Profile had no auth.users/email row; generated migration.invalid email for referential integrity.",
      });
    }
    const name = splitFullName(row);
    return {
      table: "app.users",
      conflictColumns: ["id"],
      data: compactObject({
        id,
        email,
        password_hash: null,
        full_name:
          [name.firstName, name.lastName].filter(Boolean).join(" ") || null,
        phone: asString(row.phone),
        role: normalizeRole(row.role),
        email_verified_at: row.email ? row.created_at : null,
        profile_completed: Boolean(row.profile_completed_at),
        created_at: row.created_at,
        updated_at: row.updated_at ?? row.created_at,
      }),
    };
  }

  private identityFromAuth(row: SourceRow): TargetRow | undefined {
    const userId = asString(row.user_id);
    const provider = asString(row.provider);
    const providerUserId = asString(row.provider_id) ?? asString(row.id);
    if (!userId || !provider || !providerUserId) return undefined;
    return {
      table: "app.user_identities",
      conflictColumns: ["provider", "provider_user_id"],
      data: compactObject({
        id: isUuid(row.id) ? row.id : undefined,
        user_id: userId,
        provider,
        provider_user_id: providerUserId,
        email: asString(row.email),
        email_verified: asBoolean(row.email_verified) ?? false,
        raw_profile: asJsonObject(row.identity_data),
        created_at: row.created_at,
      }),
    };
  }

  private profileFromLegacy(
    row: SourceRow,
    context: ImportContext,
  ): TargetRow | undefined {
    const id = asString(row.id);
    if (!id) return undefined;
    const authUser = context.authUsersById.get(id);
    const name = splitFullName(row);
    const customData = {
      ...asJsonObject(row.custom_data),
      legacyEmail: asString(row.email),
      legacyAvatarUrl: asString(row.avatar_url),
      legacyFcmTokenHash: asString(row.fcm_token)
        ? sha256Hex(asString(row.fcm_token)!)
        : undefined,
      legacyLastSeenAt: row.last_seen_at,
      legacyProfileCompletedAt: row.profile_completed_at,
    };
    return {
      table: "app.profiles",
      conflictColumns: ["id"],
      data: compactObject({
        id,
        user_id: id,
        first_name: name.firstName,
        last_name: name.lastName,
        phone: asString(row.phone),
        dob: row.dob,
        avatar_file_id: this.lookupLegacyFileId(row.avatar_url, context),
        email_otp_2fa_enabled: asBoolean(row.email_otp_2fa_enabled) ?? false,
        custom_data: compactObject(customData),
        created_at: row.created_at ?? authUser?.created_at,
        updated_at: authUser?.updated_at ?? row.created_at,
      }),
    };
  }

  private leadFromLegacy(
    row: SourceRow,
    context: ImportContext,
  ): TargetRow | undefined {
    const id = asString(row.id);
    const name = splitFullName(row);
    const statusKey = asString(row.status)?.toLowerCase();
    if (!id) return undefined;
    return {
      table: "app.leads",
      conflictColumns: ["id"],
      data: compactObject({
        id,
        status_id: statusKey ? context.leadStatusesByKey.get(statusKey) : null,
        first_name: name.firstName,
        last_name: name.lastName,
        phone: asString(row.phone),
        email: asString(row.email),
        source: asString(row.source),
        notes: asString(row.notes),
        custom_data: compactObject({
          ...asJsonObject(row.custom_data),
          branchId: asString(row.branch_id),
          discipline: asString(row.discipline),
          level: asString(row.level),
          category: asString(row.category),
          addressDate: row.address_date,
          visitDate: row.visit_date,
        }),
        created_at: row.created_at,
        updated_at: row.updated_at ?? row.created_at,
      }),
    };
  }

  private studentFromLegacy(row: SourceRow): TargetRow | undefined {
    const id = asString(row.id);
    if (!id) return undefined;
    const customData = compactObject({
      ...asJsonObject(row.custom_data),
      hollihopId: row.hollihop_id,
      firstName: asString(row.first_name),
      lastName: asString(row.last_name),
      middleName: asString(row.middle_name),
      phone: asString(row.phone),
      email: asString(row.email),
      gender: asString(row.gender),
      birthday: row.birthday,
      individualPrice: row.individual_price,
      internalNotes: asString(row.internal_notes),
      legacyContractUrl: asString(row.contract_url),
    });
    return this.simpleRow(
      "app.students",
      ["id"],
      row,
      {
        id,
        profile_id: nullableUuid(row.profile_id),
        lead_id: nullableUuid(row.lead_id),
        status: asString(row.status) ?? "active",
        custom_data: customData,
        created_at: row.created_at,
      },
      ["id"],
    );
  }

  private teacherFromLegacy(row: SourceRow): TargetRow | undefined {
    const id = asString(row.id);
    if (!id) return undefined;
    const fired = asBoolean(row.fired) ?? false;
    return this.simpleRow(
      "app.teachers",
      ["id"],
      row,
      {
        id,
        profile_id: nullableUuid(row.profile_id),
        status: fired ? "inactive" : (asString(row.status) ?? "active"),
        specialization: asString(row.specialization),
        custom_data: compactObject({
          ...asJsonObject(row.custom_data),
          hollihopId: row.hollihop_id,
          firstName: asString(row.first_name),
          lastName: asString(row.last_name),
          middleName: asString(row.middle_name),
          phone: asString(row.phone),
          email: asString(row.email),
          disciplines: row.disciplines,
        }),
        created_at: row.created_at,
      },
      ["id"],
    );
  }

  private lessonFromLegacy(row: SourceRow): TargetRow | undefined {
    return this.simpleRow(
      "app.lessons",
      ["id"],
      row,
      {
        id: row.id,
        student_id: nullableUuid(row.student_id),
        group_id: nullableUuid(row.group_id),
        lead_id: nullableUuid(row.lead_id),
        teacher_id: nullableUuid(row.teacher_id),
        branch_id: nullableUuid(row.branch_id),
        room_id: nullableUuid(row.room_id),
        scheduled_at: row.scheduled_at,
        duration_minutes: asNumber(row.duration_minutes) ?? 60,
        status: asString(row.status) ?? "scheduled",
        is_trial: asBoolean(row.is_trial) ?? false,
        notes: asString(row.lesson_plan),
        created_at: row.created_at,
      },
      ["id", "scheduled_at"],
    );
  }

  private taskFromLegacy(row: SourceRow): TargetRow | undefined {
    const entity = [
      ["student", row.student_id],
      ["lead", row.lead_id],
      ["group", row.group_id],
      ["teacher", row.teacher_id],
      ["lesson", row.lesson_id],
      ["profile", row.profile_id],
    ].find(([, value]) => isUuid(value));
    if (!entity) return undefined;
    return this.simpleRow(
      "app.tasks",
      ["id"],
      row,
      {
        id: row.id,
        entity_type: entity[0],
        entity_id: entity[1],
        title: asString(row.title) ?? asString(row.name) ?? "Legacy task",
        description: asString(row.description) ?? asString(row.notes),
        status: asString(row.status) ?? "open",
        due_at: row.due_at ?? row.due_date,
        assigned_to: nullableUuid(row.assigned_to),
        created_by: nullableUuid(row.created_by),
        created_at: row.created_at,
      },
      ["id", "entity_type", "entity_id", "title"],
    );
  }

  private commentFromLegacy(row: SourceRow): TargetRow | undefined {
    const entityType = asString(row.entity_type);
    if (
      !["student", "teacher", "group", "lesson", "lead", "profile"].includes(
        entityType ?? "",
      )
    )
      return undefined;
    return this.simpleRow(
      "app.entity_comments",
      ["id"],
      row,
      {
        id: row.id,
        entity_type: entityType,
        entity_id: row.entity_id,
        author_id: nullableUuid(row.author_id),
        body: asString(row.content) ?? asString(row.body),
        created_at: row.created_at,
      },
      ["id", "entity_type", "entity_id", "body"],
    );
  }

  private legalDocumentFromLegacy(
    row: SourceRow,
    context: ImportContext,
  ): TargetRow | undefined {
    const documentType = normalizeLegalDocumentType(row.document_type);
    if (!documentType) {
      context.warnings.push({
        code: "unknown_legal_document_type",
        source: "public.legal_documents",
        rowId: asString(row.id),
        message:
          "Legal document type is not supported by v3 enum and was skipped.",
      });
      return undefined;
    }
    if (asString(row.content)) {
      context.warnings.push({
        code: "legal_content_deferred",
        source: "public.legal_documents",
        rowId: asString(row.id),
        message:
          "Legacy legal document content must be converted to file/url in a follow-up content migration.",
      });
    }
    if (asBoolean(row.is_current) === true) {
      context.warnings.push({
        code: "legacy_legal_current_disabled",
        source: "public.legal_documents",
        rowId: asString(row.id),
        message:
          "Legacy legal document was current in Supabase, but is_current is set to false during import to avoid colliding with v3 seeded current legal URLs.",
      });
    }
    return this.simpleRow(
      "app.legal_documents",
      ["document_type", "version"],
      row,
      {
        id: row.id,
        document_type: documentType,
        version: asString(row.version) ?? "legacy",
        title: asString(row.title) ?? documentType,
        url: null,
        published_at: row.published_at ?? row.created_at,
        is_current: false,
        created_at: row.created_at,
      },
      ["document_type", "version", "title"],
    );
  }

  private adminChatFromLegacy(
    row: SourceRow,
  ): TargetRow | TargetRow[] | undefined {
    const id = asString(row.id);
    if (!id) return undefined;
    const clientId =
      asString(row.client_id) ??
      asString(row.user_id) ??
      asString(row.profile_id);
    const createdBy =
      nullableUuid(row.created_by) ?? nullableUuid(row.staff_id);
    const chat: TargetRow = {
      table: "app.chats",
      conflictColumns: ["id"],
      data: compactObject({
        id,
        type: "administration",
        title: asString(row.title) ?? "Администрация",
        created_by: createdBy,
        created_at: row.created_at,
        updated_at: row.updated_at ?? row.created_at,
      }),
    };
    const members: TargetRow[] = [];
    if (clientId) {
      members.push({
        table: "app.chat_members",
        conflictColumns: ["chat_id", "user_id"],
        data: {
          chat_id: id,
          user_id: clientId,
          role: "member",
          joined_at: row.created_at,
        },
      });
    }
    if (createdBy) {
      members.push({
        table: "app.chat_members",
        conflictColumns: ["chat_id", "user_id"],
        data: {
          chat_id: id,
          user_id: createdBy,
          role: "admin",
          joined_at: row.created_at,
        },
      });
    }
    return [chat, ...members];
  }

  private groupChatFromLegacy(row: SourceRow): TargetRow | undefined {
    return this.simpleRow(
      "app.chats",
      ["id"],
      row,
      {
        id: row.id,
        type: "group",
        title: asString(row.name),
        created_by: nullableUuid(row.created_by),
        created_at: row.created_at,
        updated_at: row.responded_at ?? row.created_at,
      },
      ["id", "title"],
    );
  }

  private groupChatMemberFromLegacy(row: SourceRow): TargetRow | undefined {
    return this.simpleRow(
      "app.chat_members",
      ["chat_id", "user_id"],
      row,
      {
        id: row.id,
        chat_id: row.group_chat_id,
        user_id: row.user_id,
        role: asString(row.role) === "admin" ? "admin" : "member",
        joined_at: row.joined_at,
      },
      ["chat_id", "user_id"],
    );
  }

  private directChatFromMessage(
    row: SourceRow,
    context: ImportContext,
  ): TargetRow | undefined {
    if (isUuid(row.group_chat_id)) return undefined;
    const chatId = this.chatIdForLegacyMessage(row, context);
    if (!chatId) return undefined;
    const senderId = asString(row.sender_id);
    const receiverId = asString(row.receiver_id);
    const isAdministration =
      !receiverId ||
      context.adminThreadByClientId.has(senderId ?? "") ||
      context.adminThreadByClientId.has(receiverId);
    return {
      table: "app.chats",
      conflictColumns: ["id"],
      data: {
        id: chatId,
        type: isAdministration ? "administration" : "direct",
        title: "Legacy chat",
        created_by: nullableUuid(row.sender_id),
        created_at: row.created_at,
        updated_at: row.created_at,
      },
    };
  }

  private directChatMembersFromMessage(
    row: SourceRow,
    context: ImportContext,
  ): TargetRow[] | undefined {
    if (isUuid(row.group_chat_id)) return undefined;
    const senderId = asString(row.sender_id);
    const receiverId = asString(row.receiver_id);
    const chatId = this.chatIdForLegacyMessage(row, context);
    if (!senderId || !chatId) return undefined;
    const memberIds = [
      ...new Set(
        [senderId, receiverId].filter((value): value is string =>
          Boolean(value),
        ),
      ),
    ];
    return memberIds.map((userId) => ({
      table: "app.chat_members",
      conflictColumns: ["chat_id", "user_id"],
      data: {
        chat_id: chatId,
        user_id: userId,
        role: "member",
        joined_at: row.created_at,
      },
    }));
  }

  private messageFromLegacy(
    row: SourceRow,
    context: ImportContext,
  ): TargetRow | undefined {
    const chatId = this.chatIdForLegacyMessage(row, context);
    if (!chatId) return undefined;
    const messageType = normalizeMessageType(row.message_type);
    const hasLegacyAttachment = Boolean(asString(row.attachment_url));
    return this.simpleRow(
      "app.messages",
      ["id"],
      row,
      {
        id: row.id,
        chat_id: chatId,
        sender_id: nullableUuid(row.sender_id),
        content:
          asString(row.content) ??
          (hasLegacyAttachment
            ? "[legacy attachment pending file migration]"
            : null),
        message_type:
          hasLegacyAttachment && messageType === "text" ? "file" : messageType,
        attachment_file_id: this.lookupLegacyFileId(
          row.attachment_url,
          context,
        ),
        reply_to_id: null,
        forwarded_from_id: null,
        pinned_by: nullableUuid(row.pinned_by_id),
        pinned_at: row.pinned_at,
        created_at: row.created_at,
        updated_at: row.updated_at ?? row.created_at,
        deleted_at: row.deleted_at,
      },
      ["id", "chat_id"],
    );
  }

  private messageReactionFromLegacy(
    row: SourceRow,
    context: ImportContext,
  ): TargetRow | undefined {
    const messageId = asString(row.message_id);
    const sourceMessage = messageId
      ? context.messagesById.get(messageId)
      : undefined;
    if (!sourceMessage || !this.chatIdForLegacyMessage(sourceMessage, context))
      return undefined;
    return this.simpleRow(
      "app.message_reactions",
      ["message_id", "user_id", "emoji"],
      row,
      {
        id: row.id,
        message_id: messageId,
        user_id: row.user_id,
        emoji: asString(row.emoji) ?? asString(row.reaction) ?? "like",
        created_at: row.created_at,
      },
      ["message_id", "user_id", "emoji"],
    );
  }

  private chatIdForLegacyMessage(
    row: SourceRow,
    context: ImportContext,
  ): string | undefined {
    const groupChatId = asString(row.group_chat_id);
    if (groupChatId) return groupChatId;
    const senderId = asString(row.sender_id);
    const receiverId = asString(row.receiver_id);
    if (!senderId) return undefined;
    if (!receiverId) {
      return (
        context.adminThreadByClientId.get(senderId) ??
        deterministicUuid("legacy-admin-chat", senderId)
      );
    }
    return (
      context.adminThreadByClientId.get(senderId) ??
      context.adminThreadByClientId.get(receiverId) ??
      directChatId(senderId, receiverId)
    );
  }

  private channelPermissionFromLegacy(row: SourceRow): TargetRow | undefined {
    return this.simpleRow(
      "app.channel_permissions",
      ["channel_id", "user_id", "role"],
      row,
      {
        id: row.id,
        channel_id: row.channel_id,
        user_id: nullableUuid(row.user_id),
        role: null,
        can_read: true,
        can_write: asBoolean(row.can_post) ?? asBoolean(row.can_edit) ?? false,
        created_at: row.created_at,
      },
      ["channel_id"],
    );
  }

  private notificationFromLegacy(row: SourceRow): TargetRow | undefined {
    const data = asJsonObject(row.data);
    return this.simpleRow(
      "app.notifications",
      ["id"],
      row,
      {
        id: row.id,
        type: asString(row.type) ?? "legacy",
        title: asString(data.title) ?? asString(row.type) ?? "Уведомление",
        body:
          asString(data.body) ??
          asString(data.message) ??
          asString(row.type) ??
          "Уведомление",
        data,
        created_by: nullableUuid(row.created_by),
        created_at: row.created_at,
      },
      ["id", "type", "title", "body"],
    );
  }

  private notificationDeviceFromLegacy(row: SourceRow): TargetRow | undefined {
    const token = asString(row.token);
    if (!token) return undefined;
    const tokenHash = sha256Hex(token);
    return this.simpleRow(
      "app.notification_devices",
      ["user_id", "token_hash"],
      row,
      {
        user_id: row.user_id,
        platform: asString(row.platform) ?? "unknown",
        token_hash: tokenHash,
        encrypted_token: `sha256:${tokenHash}`,
        enabled: true,
        last_seen_at: row.updated_at ?? row.created_at,
        created_at: row.created_at ?? row.updated_at,
        updated_at: row.updated_at ?? row.created_at,
      },
      ["user_id", "token_hash"],
    );
  }

  private lookupLegacyFileId(
    value: unknown,
    context: ImportContext,
  ): string | undefined {
    const raw = asString(value);
    if (!raw) return undefined;
    const exact = context.fileIdByLegacyKey.get(raw);
    if (exact) return exact;
    try {
      const decoded = decodeURIComponent(raw);
      const decodedMatch = context.fileIdByLegacyKey.get(decoded);
      if (decodedMatch) return decodedMatch;
    } catch {
      // Legacy URLs may contain malformed escaping; fall through to partial matching.
    }
    const match = context.legacyFileEntries.find(
      (entry) =>
        raw.includes(entry.name) ||
        raw.includes(`${entry.bucketId}/${entry.name}`) ||
        entry.legacyKeys.some((key) => raw.includes(key)),
    );
    return match?.id;
  }

  private simpleRow(
    table: string,
    conflictColumns: string[],
    source: SourceRow,
    data: Record<string, unknown>,
    requiredColumns: string[],
  ): TargetRow | undefined {
    const compacted = compactObject(data);
    const hasRequired = requiredColumns.every((column) => {
      const value = compacted[column];
      return value !== undefined && value !== null && value !== "";
    });
    if (!hasRequired) return undefined;
    return {
      table,
      conflictColumns,
      data: compacted,
    };
  }

  private async insertPlan(
    client: PoolClient,
    rows: TargetRow[],
  ): Promise<number> {
    let insertedOrSkippedRows = 0;
    for (
      let offset = 0;
      offset < rows.length;
      offset += this.config.batchSize
    ) {
      const batch = rows.slice(offset, offset + this.config.batchSize);
      for (const row of batch) {
        await this.insertRow(client, row);
        insertedOrSkippedRows += 1;
      }
    }
    return insertedOrSkippedRows;
  }

  private async insertRow(client: PoolClient, row: TargetRow): Promise<void> {
    const columns = Object.keys(row.data);
    const values = columns.map((column) => row.data[column]);
    const placeholders = columns.map((_, index) => `$${index + 1}`).join(", ");
    const conflict =
      row.conflictColumns.length > 0
        ? `on conflict (${row.conflictColumns.map(quoteIdent).join(", ")}) do nothing`
        : "on conflict do nothing";
    await client.query(
      `insert into ${row.table} (${columns.map(quoteIdent).join(", ")}) values (${placeholders}) ${conflict}`,
      values,
    );
  }

  private groupPlanRows(
    rows: TargetRow[],
  ): Array<{ table: string; plannedRows: number }> {
    const counts = new Map<string, number>();
    for (const row of rows)
      counts.set(row.table, (counts.get(row.table) ?? 0) + 1);
    return [...counts.entries()]
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([table, plannedRows]) => ({ table, plannedRows }));
  }

  private readExportReport(): Record<string, unknown> | undefined {
    const file = join(this.config.exportDir, "export-report.json");
    if (!existsSync(file)) return undefined;
    return JSON.parse(readFileSync(file, "utf8")) as Record<string, unknown>;
  }

  private readFileMap(warnings: ImportWarning[]): LegacyFileMapEntry[] {
    if (!existsSync(this.config.fileMapPath)) {
      warnings.push({
        code: "file_map_missing",
        message: `File migration report is missing and file reference rewrite will be skipped: ${this.config.fileMapPath}`,
      });
      return [];
    }
    const parsed = JSON.parse(
      readFileSync(this.config.fileMapPath, "utf8"),
    ) as { files?: LegacyFileMapEntry[] };
    return Array.isArray(parsed.files) ? parsed.files : [];
  }

  private writeReport(report: ImportReport): void {
    mkdirSync(this.config.exportDir, { recursive: true });
    writeFileSync(
      join(this.config.exportDir, "import-report.json"),
      `${JSON.stringify(report, null, 2)}\n`,
      "utf8",
    );
  }

  private redactConnectionString(connectionString: string): string {
    try {
      const url = new URL(connectionString);
      if (url.username) url.username = "***";
      if (url.password) url.password = "***";
      return url.toString();
    } catch {
      return "<redacted>";
    }
  }
}

async function readNdjson(file: string): Promise<SourceRow[]> {
  const rows: SourceRow[] = [];
  const reader = createInterface({
    input: createReadStream(file, { encoding: "utf8" }),
    crlfDelay: Infinity,
  });
  for await (const line of reader) {
    const trimmed = line.trim();
    if (trimmed.length === 0) continue;
    rows.push(JSON.parse(trimmed) as SourceRow);
  }
  return rows;
}

function indexById(rows: SourceRow[]): Map<string, SourceRow> {
  const index = new Map<string, SourceRow>();
  for (const row of rows) {
    const id = asString(row.id);
    if (id) index.set(id, row);
  }
  return index;
}

function quoteIdent(identifier: string): string {
  if (!/^[a-z_][a-z0-9_]*$/i.test(identifier)) {
    throw new Error(`Unsafe target column: ${identifier}`);
  }
  return `"${identifier}"`;
}

function parseConfig(): ImportConfig {
  const connectionString =
    process.env.TARGET_DATABASE_URL ?? process.env.DATABASE_URL;
  if (!connectionString) {
    throw new Error(
      "TARGET_DATABASE_URL or DATABASE_URL is required for v3 import.",
    );
  }
  const batchSize = Number(process.env.MIGRATION_BATCH_SIZE ?? "500");
  return {
    exportDir: resolve(
      process.env.SUPABASE_EXPORT_DIR ?? "exports/supabase/latest",
    ),
    connectionString,
    dryRun: (process.env.MIGRATION_DRY_RUN ?? "true").toLowerCase() !== "false",
    batchSize: Number.isFinite(batchSize) && batchSize > 0 ? batchSize : 500,
    fileMapPath: resolve(
      process.env.SUPABASE_FILE_MAP ??
        join(
          process.env.SUPABASE_EXPORT_DIR ?? "exports/supabase/latest",
          "file-import-report.json",
        ),
    ),
  };
}

if (require.main === module) {
  const config = parseConfig();
  const pipeline = new V3ImportPipeline(config);
  pipeline
    .run()
    .then((report) => {
      // eslint-disable-next-line no-console
      console.log(
        JSON.stringify(
          {
            importId: report.importId,
            mode: report.mode,
            sourceRows: report.totals.sourceRows,
            plannedRows: report.totals.plannedRows,
            skippedRows: report.totals.skippedRows,
            warnings: report.totals.warnings,
            report: join(config.exportDir, "import-report.json"),
          },
          null,
          2,
        ),
      );
    })
    .catch((error: Error) => {
      // eslint-disable-next-line no-console
      console.error(error.message);
      process.exitCode = 1;
    });
}

export { V3ImportPipeline, parseConfig };
