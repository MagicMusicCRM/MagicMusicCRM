import {
  BadRequestException,
  ForbiddenException,
  Injectable,
} from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import {
  ActorContext,
  isAdminRole,
} from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import {
  CRM_CUSTOM_FIELD_ENTITIES,
  CRM_CUSTOM_FIELD_TYPES,
  CrmCustomFieldDefinitionDto,
} from "./dto/update-crm-custom-fields.dto";
import {
  DEFAULT_CRM_CUSTOM_FIELDS,
  type CrmCustomFieldDefinition,
} from "./crm-custom-field-catalog";

interface SettingRow {
  key: string;
  value_text: string | null;
  updated_at: Date | string;
}

interface JsonSettingRow {
  key: string;
  value: unknown;
  updated_at: Date | string;
  configuration_snapshot?: unknown;
}

const ADMIN_CHAT_AVATAR_KEY = "admin_chat_avatar_url";
const CRM_CUSTOM_FIELDS_KEY = "crm_custom_fields";

type TeacherOptionTarget = "levels" | "categories";

type CanonicalTeacherOptions = Record<TeacherOptionTarget, string[]>;

const TEACHER_OPTION_SOURCE_ENTITIES = new Set([
  "lead",
  "leads",
  "student",
  "students",
  "teacher",
  "teachers",
]);

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function indexOptionSets(value: unknown): Map<string, Record<string, unknown>> {
  const optionSets = new Map<string, Record<string, unknown>>();
  if (!Array.isArray(value)) return optionSets;
  for (const item of value) {
    if (!isRecord(item) || typeof item.key !== "string" || !item.key) continue;
    optionSets.set(item.key, item);
  }
  return optionSets;
}

function teacherOptionTarget(key: unknown): TeacherOptionTarget | null {
  if (key === "level" || key === "levels") return "levels";
  if (key === "category" || key === "categories") return "categories";
  return null;
}

function isTeacherOptionSourceEntity(value: unknown): boolean {
  if (typeof value !== "string") return true;
  const entity = value.trim().toLowerCase();
  return !entity || TEACHER_OPTION_SOURCE_ENTITIES.has(entity);
}

function configuredFieldOptions(
  field: Record<string, unknown>,
  optionSets: Map<string, Record<string, unknown>>,
): unknown {
  const key = typeof field.optionSetKey === "string" ? field.optionSetKey : null;
  return key ? optionSets.get(key)?.options : field.options;
}

function configuredOptionLabel(value: unknown): string | null {
  if (typeof value === "string") return value;
  if (!isRecord(value) || value.active === false) return null;
  return typeof value.label === "string" ? value.label : null;
}

function configuredOptionLabels(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const labels: string[] = [];
  for (const option of value) {
    const raw = configuredOptionLabel(option);
    if (raw === null) continue;
    const label = raw.trim();
    if (label.length > 0 && label.length <= 80) labels.push(label);
  }
  return labels;
}

function collectCanonicalTeacherOptions(
  snapshot: Record<string, unknown>,
): CanonicalTeacherOptions {
  const canonical: CanonicalTeacherOptions = { levels: [], categories: [] };
  const seen = { levels: new Set<string>(), categories: new Set<string>() };
  const fields = Array.isArray(snapshot.fields) ? snapshot.fields : [];
  const optionSets = indexOptionSets(snapshot.optionSets);
  for (const value of fields) {
    if (!isRecord(value) || value.active === false) continue;
    if (!isTeacherOptionSourceEntity(value.entityType)) continue;
    const key = typeof value.key === "string" ? value.key.toLowerCase() : "";
    const target = teacherOptionTarget(key);
    if (target === null) continue;
    for (const label of configuredOptionLabels(configuredFieldOptions(value, optionSets))) {
      if (seen[target].has(label)) continue;
      seen[target].add(label);
      canonical[target].push(label);
    }
  }
  return canonical;
}

function projectTeacherField(
  value: unknown,
  canonical: CanonicalTeacherOptions,
): unknown {
  if (!isRecord(value) || value.entity !== "teachers") return value;
  const target = teacherOptionTarget(value.key);
  if (target === null || canonical[target].length === 0) return value;
  return { ...value, type: "select", options: canonical[target] };
}

function appendMissingTeacherProjections(
  fields: readonly unknown[],
  canonical: CanonicalTeacherOptions,
): unknown[] {
  const keys = new Set<string>();
  for (const value of fields) {
    if (!isRecord(value) || value.entity !== "teachers") continue;
    if (typeof value.key === "string") keys.add(value.key);
  }
  const missing: unknown[] = [];
  for (const projection of [
    { key: "levels", label: "Уровни обучения", options: canonical.levels },
    { key: "categories", label: "Категории", options: canonical.categories },
  ]) {
    if (projection.options.length === 0 || keys.has(projection.key)) continue;
    missing.push({
      entity: "teachers",
      key: projection.key,
      label: projection.label,
      type: "select",
      required: false,
      options: projection.options,
    });
  }
  return [...fields, ...missing];
}

function projectTeacherFields(
  fields: unknown[],
  canonical: CanonicalTeacherOptions,
): unknown[] {
  const projected = fields.map((value) => projectTeacherField(value, canonical));
  return appendMissingTeacherProjections(projected, canonical);
}

@Injectable()
export class SettingsService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly realtime: RealtimeBus,
  ) {}

  async getAdminChatAvatar(_actor: ActorContext) {
    const result = await this.database.query<SettingRow>(
      `
        select key, value #>> '{}' as value_text, updated_at
        from app.system_settings
        where key = $1
        limit 1
      `,
      [ADMIN_CHAT_AVATAR_KEY],
    );
    const row = result.rows[0];
    return {
      key: ADMIN_CHAT_AVATAR_KEY,
      value: row?.value_text ?? null,
      updatedAt: row?.updated_at ?? null,
    };
  }

  async updateAdminChatAvatar(actor: ActorContext, url?: string | null) {
    if (!isAdminRole(actor.role)) {
      throw new ForbiddenException(
        "Только администратор может менять глобальные настройки.",
      );
    }
    const normalized = this.normalizeAdminAvatarUrl(url);
    const result = await this.database.query<SettingRow>(
      `
        insert into app.system_settings (key, value, updated_by)
        values ($1, $2::jsonb, $3)
        on conflict (key) do update
        set value = excluded.value,
          updated_by = excluded.updated_by,
          updated_at = now()
        returning key, value #>> '{}' as value_text, updated_at
      `,
      [
        ADMIN_CHAT_AVATAR_KEY,
        normalized === null ? "null" : JSON.stringify(normalized),
        actor.userId,
      ],
    );
    const row = result.rows[0];
    await this.audit.record({
      actor,
      action: "settings.admin_chat_avatar_updated",
      entityType: "setting",
      entityId: ADMIN_CHAT_AVATAR_KEY,
      metadata: { cleared: normalized === null },
    });
    // Shared UI element visible to every role — broadcast so open messengers
    // refetch the avatar without a manual refresh.
    this.realtime.emitSettingChanged(ADMIN_CHAT_AVATAR_KEY);
    return {
      key: ADMIN_CHAT_AVATAR_KEY,
      value: row?.value_text ?? null,
      updatedAt: row?.updated_at ?? null,
    };
  }

  async getCrmCustomFields(_actor: ActorContext) {
    const result = await this.database.query<JsonSettingRow>(
      `
        select $1::text as key,
          setting.value,
          setting.updated_at,
          (
            select revision.effective_snapshot
            from app.crm_configuration_revisions revision
            where revision.branch_id is null
            order by revision.version desc
            limit 1
          ) as configuration_snapshot
        from (select 1) seed
        left join app.system_settings setting on setting.key = $1
      `,
      [CRM_CUSTOM_FIELDS_KEY],
    );
    const row = result.rows[0];
    const rawFields = Array.isArray(row?.value)
      ? row.value
      : DEFAULT_CRM_CUSTOM_FIELDS;
    return {
      key: CRM_CUSTOM_FIELDS_KEY,
      fields: this.normalizeCustomFields(
        this.withCanonicalTeacherOptions(
          rawFields,
          row?.configuration_snapshot,
        ),
      ),
      updatedAt: row?.updated_at ?? null,
    };
  }

  async updateCrmCustomFields(
    actor: ActorContext,
    fields: CrmCustomFieldDefinitionDto[],
  ) {
    if (!isAdminRole(actor.role)) {
      throw new ForbiddenException(
        "Только администратор может менять глобальные настройки.",
      );
    }
    const normalized = this.normalizeCustomFields(fields);
    const result = await this.database.query<JsonSettingRow>(
      `
        insert into app.system_settings (key, value, updated_by)
        values ($1, $2::jsonb, $3)
        on conflict (key) do update
        set value = excluded.value,
          updated_by = excluded.updated_by,
          updated_at = now()
        returning key, value, updated_at
      `,
      [CRM_CUSTOM_FIELDS_KEY, JSON.stringify(normalized), actor.userId],
    );
    const row = result.rows[0];
    await this.audit.record({
      actor,
      action: "settings.crm_custom_fields_updated",
      entityType: "setting",
      entityId: CRM_CUSTOM_FIELDS_KEY,
      metadata: { fieldCount: normalized.length },
    });
    // CRM custom fields affect staff CRM forms — scope the hint to the crm room.
    this.realtime.emitCrmChanged({
      entity: "setting",
      action: "updated",
      id: CRM_CUSTOM_FIELDS_KEY,
    });
    return {
      key: CRM_CUSTOM_FIELDS_KEY,
      fields: this.normalizeCustomFields(row?.value),
      updatedAt: row?.updated_at ?? null,
    };
  }

  private normalizeAdminAvatarUrl(url?: string | null): string | null {
    const value = url?.trim();
    if (!value) return null;
    if (value.startsWith("storage://avatars/")) return value;
    try {
      const parsed = new URL(value);
      if (parsed.protocol === "https:") return value;
    } catch {
      // Fall through to the public validation error.
    }
    throw new BadRequestException("Некорректная ссылка на аватар.");
  }

  private normalizeCustomFields(value: unknown): CrmCustomFieldDefinition[] {
    if (!Array.isArray(value)) {
      throw new BadRequestException("Некорректная схема дополнительных полей.");
    }

    const seen = new Set<string>();
    return value.map((field) => {
      if (!field || typeof field !== "object" || Array.isArray(field)) {
        throw new BadRequestException(
          "Некорректная схема дополнительных полей.",
        );
      }
      const raw = field as Record<string, unknown>;
      const entity = this.normalizeEnumValue(
        raw.entity,
        CRM_CUSTOM_FIELD_ENTITIES,
        "Некорректная сущность дополнительного поля.",
      );
      const type = this.normalizeEnumValue(
        raw.type,
        CRM_CUSTOM_FIELD_TYPES,
        "Некорректный тип дополнительного поля.",
      );
      const key = this.normalizeFieldKey(raw.key);
      const label = this.normalizeText(
        raw.label,
        80,
        "Название дополнительного поля обязательно.",
      );
      const duplicateKey = `${entity}:${key}`;
      if (seen.has(duplicateKey)) {
        throw new BadRequestException(
          "Ключ дополнительного поля должен быть уникальным внутри сущности.",
        );
      }
      seen.add(duplicateKey);

      const normalized: CrmCustomFieldDefinition = {
        entity,
        key,
        label,
        type,
        required: raw.required === true,
      };
      const hint = this.normalizeOptionalText(raw.hint, 160);
      if (hint) normalized.hint = hint;
      if (type === "select") {
        normalized.options = this.normalizeOptions(raw.options);
      }
      return normalized;
    }).filter((field) =>
      !["workplace", "position", "individualPrice"].includes(field.key),
    );
  }

  private withCanonicalTeacherOptions(
    fields: unknown[],
    snapshotValue: unknown,
  ): unknown[] {
    if (!isRecord(snapshotValue)) return fields;
    return projectTeacherFields(
      fields,
      collectCanonicalTeacherOptions(snapshotValue),
    );
  }

  private normalizeFieldKey(value: unknown): string {
    const key = this.normalizeText(
      value,
      64,
      "Ключ дополнительного поля обязателен.",
    );
    if (!/^[A-Za-z][A-Za-z0-9_]*$/.test(key)) {
      throw new BadRequestException(
        "Ключ поля должен начинаться с латинской буквы и содержать только латиницу, цифры и подчёркивание.",
      );
    }
    return key;
  }

  private normalizeText(
    value: unknown,
    maxLength: number,
    errorMessage: string,
  ): string {
    if (typeof value !== "string") {
      throw new BadRequestException(errorMessage);
    }
    const text = value.trim();
    if (!text || text.length > maxLength) {
      throw new BadRequestException(errorMessage);
    }
    return text;
  }

  private normalizeOptionalText(
    value: unknown,
    maxLength: number,
  ): string | undefined {
    if (value === undefined || value === null) return undefined;
    if (typeof value !== "string") {
      throw new BadRequestException(
        "Некорректная подсказка дополнительного поля.",
      );
    }
    const text = value.trim();
    if (!text) return undefined;
    if (text.length > maxLength) {
      throw new BadRequestException(
        "Подсказка дополнительного поля слишком длинная.",
      );
    }
    return text;
  }

  private normalizeOptions(value: unknown): string[] {
    if (!Array.isArray(value)) {
      throw new BadRequestException(
        "Для поля со списком нужны варианты выбора.",
      );
    }
    const options = [
      ...new Set(
        value.map((item) =>
          this.normalizeText(
            item,
            80,
            "Вариант выбора дополнительного поля обязателен.",
          ),
        ),
      ),
    ];
    if (options.length === 0) {
      throw new BadRequestException(
        "Для поля со списком нужен хотя бы один вариант выбора.",
      );
    }
    return options;
  }

  private normalizeEnumValue<T extends readonly string[]>(
    value: unknown,
    allowed: T,
    errorMessage: string,
  ): T[number] {
    if (typeof value !== "string" || !allowed.includes(value)) {
      throw new BadRequestException(errorMessage);
    }
    return value as T[number];
  }
}
