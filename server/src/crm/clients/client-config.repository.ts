import { ConflictException, Injectable } from "@nestjs/common";
import { isDeepStrictEqual } from "node:util";
import { PoolClient } from "pg";
import {
  createSafeAuditChange,
} from "../../audit/audit-field-presentation.policy";
import type {
  AuditFieldChangeInput,
  AuditFieldValueType,
} from "../../audit/audit-presentation.types";
import { DatabaseService } from "../../db/database.service";
import {
  CLIENT_CUSTOM_VALUE_TYPES,
  ClientCustomValueType,
  ClientEntityType,
} from "../dto/client-config.dto";

export interface LeadSourceRow {
  id: string;
  canonical_name: string;
  display_name: string;
  is_active: boolean;
  is_system: boolean;
  version: number | string;
  created_at: Date | string;
  updated_at: Date | string;
  deleted_at: Date | string | null;
}

export interface ClientCustomFieldDefinitionRow {
  id: string;
  field_key: string;
  label: string;
  value_type: ClientCustomValueType;
  is_required: boolean;
  is_active: boolean;
  is_system: boolean;
  options: unknown;
  version: number | string;
  created_at: Date | string;
  updated_at: Date | string;
  deleted_at: Date | string | null;
  category_key?: string;
  category_label?: string;
  sort_order?: number | string;
  width?: string;
  placements?: unknown;
  visible_on_lead: boolean;
  visible_on_student: boolean;
}

export interface TypedClientCustomValue {
  readonly definitionId: string;
  valueText: string | null;
  valueNumber: number | null;
  valueBoolean: boolean | null;
  valueDate: string | null;
  valueJson: unknown | null;
}

interface TypedClientCustomFieldPresentation extends TypedClientCustomValue {
  readonly fieldKey: string;
  readonly label: string;
  readonly valueType: ClientCustomValueType;
}

export interface TypedClientCustomFieldWrite
  extends TypedClientCustomFieldPresentation {
  readonly definitionVersion: number | string;
}

interface StoredTypedClientCustomValueRow {
  definition_id: string;
  field_key: string;
  label: string;
  value_type: ClientCustomValueType;
  value_text: string | null;
  value_number: number | string | null;
  value_boolean: boolean | null;
  value_date: string | null;
  value_json: unknown | null;
}

export async function saveTypedClientValues(
  client: PoolClient,
  entityType: ClientEntityType,
  entityId: string,
  values: TypedClientCustomFieldWrite[],
): Promise<void> {
  const authoritativeValues = await lockAuthoritativeCustomFieldWrites(
    client,
    entityType,
    values,
  );
  await insertTypedClientValues(
    client,
    entityType,
    entityId,
    authoritativeValues,
  );
}

async function insertTypedClientValues(
  client: PoolClient,
  entityType: ClientEntityType,
  entityId: string,
  values: TypedClientCustomFieldWrite[],
): Promise<void> {
  const resolved = await client.query<{ client_id: string | null }>(
    `select app.resolve_client_id($1, $2) as client_id`,
    [entityType, entityId],
  );
  const clientId = resolved.rows[0]?.client_id;
  if (!clientId) throw new Error("Canonical Client identity was not found.");
  for (const value of values) {
    await client.query(
      `
        insert into app.client_custom_field_values (
          definition_id,
          client_id,
          entity_type,
          entity_id,
          value_text,
          value_number,
          value_boolean,
          value_date,
          value_json,
          validation_state
        )
        values ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb, 'valid')
        on conflict (definition_id, client_id)
        do update set
          entity_type = excluded.entity_type,
          entity_id = excluded.entity_id,
          value_text = excluded.value_text,
          value_number = excluded.value_number,
          value_boolean = excluded.value_boolean,
          value_date = excluded.value_date,
          value_json = excluded.value_json,
          validation_state = 'valid',
          updated_at = now()
      `,
      [
        value.definitionId,
        clientId,
        entityType,
        entityId,
        value.valueText,
        value.valueNumber,
        value.valueBoolean,
        value.valueDate,
        value.valueJson === null ? null : JSON.stringify(value.valueJson),
      ],
    );
  }
}

export async function replaceTypedClientValues(
  client: PoolClient,
  entityType: ClientEntityType,
  entityId: string,
  values: TypedClientCustomFieldWrite[],
): Promise<AuditFieldChangeInput[]> {
  const resolved = await client.query<{ client_id: string | null }>(
    `select app.resolve_client_id($1, $2) as client_id`,
    [entityType, entityId],
  );
  const clientId = resolved.rows[0]?.client_id;
  if (!clientId) throw new Error("Canonical Client identity was not found.");
  const authoritativeValues = await lockAuthoritativeCustomFieldWrites(
    client,
    entityType,
    values,
  );
  const previous = await client.query<StoredTypedClientCustomValueRow>(
    `select value.definition_id, definition.field_key, definition.label,
       definition.value_type, value.value_text, value.value_number,
       value.value_boolean, value.value_date::text as value_date,
       value.value_json
     from app.client_custom_field_values value
     join app.client_custom_field_definitions definition
       on definition.id = value.definition_id
     where value.client_id = $1
       and not definition.is_system
       and definition.is_active and definition.deleted_at is null
     order by definition.field_key, definition.id`,
    [clientId],
  );
  const definitionIds = authoritativeValues.map(
    (value) => value.definitionId,
  );
  await client.query(
    `delete from app.client_custom_field_values value
     using app.client_custom_field_definitions definition
     where value.definition_id = definition.id
       and value.client_id = $1
       and not definition.is_system
       and definition.is_active and definition.deleted_at is null
       and not (value.definition_id = any($2::uuid[]))`,
    [clientId, definitionIds],
  );
  await insertTypedClientValues(
    client,
    entityType,
    entityId,
    authoritativeValues,
  );
  return diffTypedClientValues(previous.rows, authoritativeValues);
}

async function lockAuthoritativeCustomFieldWrites(
  client: PoolClient,
  entityType: ClientEntityType,
  values: TypedClientCustomFieldWrite[],
): Promise<TypedClientCustomFieldWrite[]> {
  if (values.length === 0) return [];
  const definitionIds = values.map((value) => value.definitionId);
  const uniqueDefinitionIds = [...new Set(definitionIds)].sort();
  if (uniqueDefinitionIds.length !== definitionIds.length) {
    throw customFieldDefinitionConflict("customFields");
  }
  const locked = await client.query<ClientCustomFieldDefinitionRow>(
    `select id, field_key, label, value_type, is_required,
       is_active, is_system, options, version, created_at, updated_at,
       deleted_at, visible_on_lead, visible_on_student
     from app.client_custom_field_definitions
     where $1::text in ('lead', 'student')
       and id = any($2::uuid[])
     order by id
     for update`,
    [entityType, uniqueDefinitionIds],
  );
  const byId = new Map(
    locked.rows.map((definition) => [definition.id, definition]),
  );
  return values.map((value) => {
    const definition = byId.get(value.definitionId);
    const field = `customFields.${value.fieldKey}`;
    if (!definition) throw customFieldDefinitionConflict(field);
    const isVisible = entityType === "lead"
      ? definition.visible_on_lead
      : definition.visible_on_student;
    if (
      definition.is_system ||
      !definition.is_active ||
      definition.deleted_at !== null ||
      !isVisible ||
      !CLIENT_CUSTOM_VALUE_TYPES.includes(definition.value_type)
    ) {
      throw customFieldDefinitionConflict(field);
    }
    if (
      definition.field_key !== value.fieldKey ||
      definition.label !== value.label ||
      definition.value_type !== value.valueType ||
      String(definition.version) !== String(value.definitionVersion)
    ) {
      throw customFieldDefinitionConflict(field);
    }
    return {
      ...value,
      definitionId: definition.id,
      definitionVersion: definition.version,
      fieldKey: definition.field_key,
      label: definition.label,
      valueType: definition.value_type,
    };
  });
}

function customFieldDefinitionConflict(field: string): ConflictException {
  return new ConflictException({
    code: "CUSTOM_FIELD_DEFINITION_CHANGED",
    field,
    message:
      "Состав дополнительных полей изменился. Обновите карточку и повторите сохранение.",
  });
}

function diffTypedClientValues(
  previousRows: StoredTypedClientCustomValueRow[],
  values: TypedClientCustomFieldWrite[],
): AuditFieldChangeInput[] {
  const previous = new Map(
    previousRows.map((row) => [row.definition_id, storedTypedValue(row)]),
  );
  const next = new Map(values.map((value) => [value.definitionId, value]));
  const definitionIds = [
    ...previous.keys(),
    ...values
      .map((value) => value.definitionId)
      .filter((definitionId) => !previous.has(definitionId)),
  ];

  return definitionIds.flatMap((definitionId) => {
    const before = previous.get(definitionId);
    const after = next.get(definitionId);
    const from = before ? typedValueForAudit(before) : null;
    const to = after ? typedValueForAudit(after) : null;
    if (isDeepStrictEqual(from, to)) return [];
    const presentation = after ?? before;
    if (!presentation) return [];
    const change = createSafeAuditChange({
      field: `customFields.${presentation.fieldKey}`,
      label: presentation.label,
      valueType: auditValueType(presentation.valueType),
      displayMode: "values",
      from,
      to,
    });
    return change ? [change] : [];
  });
}

function storedTypedValue(
  row: StoredTypedClientCustomValueRow,
): TypedClientCustomFieldPresentation {
  return {
    definitionId: row.definition_id,
    fieldKey: row.field_key,
    label: row.label,
    valueType: row.value_type,
    valueText: row.value_text,
    valueNumber: row.value_number === null ? null : Number(row.value_number),
    valueBoolean: row.value_boolean,
    valueDate: row.value_date,
    valueJson: row.value_json,
  };
}

function typedValueForAudit(value: TypedClientCustomValue): unknown {
  if (value.valueNumber !== null) return value.valueNumber;
  if (value.valueBoolean !== null) return value.valueBoolean;
  if (value.valueDate !== null) return value.valueDate;
  if (value.valueJson !== null) return value.valueJson;
  return value.valueText;
}

function auditValueType(valueType: ClientCustomValueType): AuditFieldValueType {
  if (valueType === "date") return "date";
  if (valueType === "datetime") return "datetime";
  if (valueType === "boolean" || valueType === "toggle") return "boolean";
  if (valueType === "multi_select" || valueType === "checkbox_group") {
    return "list";
  }
  return "text";
}

export async function readTypedClientValueMap(
  database: DatabaseService,
  entityType: ClientEntityType,
  entityId: string,
): Promise<Record<string, unknown>> {
  const result = await database.query<{
    value_map: Record<string, unknown>;
  }>(
    `select ${typedClientValueMapSql("$1", "$2")} as value_map`,
    [entityType, entityId],
  );
  return result.rows[0]?.value_map ?? {};
}

export function typedClientValueMapSql(
  entityTypeExpression: string,
  entityIdExpression: string,
): string {
  for (const expression of [entityTypeExpression, entityIdExpression]) {
    if (
      !/^(?:\$[1-9][0-9]*|[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*)$/i.test(
        expression,
      )
    ) {
      throw new Error("Unsafe typed client value expression.");
    }
  }
  return `(
    select coalesce(
      jsonb_object_agg(
        definition.field_key,
        coalesce(
          to_jsonb(value.value_text),
          to_jsonb(value.value_number),
          to_jsonb(value.value_boolean),
          to_jsonb(value.value_date),
          value.value_json
        ) order by definition.sort_order, definition.field_key
      ),
      '{}'::jsonb
    )
    from app.client_custom_field_values value
    join app.client_custom_field_definitions definition
      on definition.id = value.definition_id
    where value.client_id = app.resolve_client_id(
      ${entityTypeExpression}, ${entityIdExpression}
    )
      and definition.is_active and definition.deleted_at is null
  )`;
}

export function typedClientTableFieldsSql(
  entityType: ClientEntityType,
  entityIdExpression: string,
): string {
  if (!/^[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*$/i.test(entityIdExpression)) {
    throw new Error("Unsafe typed client field identifier.");
  }
  return `(
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', definition.id,
          'key', definition.field_key,
          'label', definition.label,
          'valueType', definition.value_type,
          'value', coalesce(
            to_jsonb(value.value_text),
            to_jsonb(value.value_number),
            to_jsonb(value.value_boolean),
            to_jsonb(value.value_date),
            value.value_json
          )
        ) order by definition.sort_order, definition.field_key
      ),
      '[]'::jsonb
    )
    from app.client_custom_field_values value
    join app.client_custom_field_definitions definition
      on definition.id = value.definition_id
    where value.client_id = app.resolve_client_id(
      '${entityType}', ${entityIdExpression}
    )
      and definition.is_active and definition.deleted_at is null
      and definition.placements ? 'table'
  )`;
}

@Injectable()
export class ClientConfigRepository {
  constructor(private readonly database: DatabaseService) {}

  async listSources(includeArchived: boolean): Promise<LeadSourceRow[]> {
    const result = await this.database.query<LeadSourceRow>(
      `
        select id, canonical_name, display_name, is_active, is_system, version,
          created_at, updated_at, deleted_at
        from app.lead_sources
        where ($1::boolean or (is_active and deleted_at is null))
        order by
          (deleted_at is not null or not is_active) asc,
          lower(display_name) asc,
          id asc
      `,
      [includeArchived],
    );
    return result.rows;
  }

  async findActiveSource(sourceId: string): Promise<LeadSourceRow | null> {
    const result = await this.database.query<LeadSourceRow>(
      `
        select id, canonical_name, display_name, is_active, is_system, version,
          created_at, updated_at, deleted_at
        from app.lead_sources
        where id = $1
          and is_active
          and deleted_at is null
        limit 1
      `,
      [sourceId],
    );
    return result.rows[0] ?? null;
  }

  async createSource(
    client: PoolClient,
    input: { canonicalName: string; displayName: string },
  ): Promise<LeadSourceRow> {
    const result = await client.query<LeadSourceRow>(
      `
        insert into app.lead_sources (
          canonical_name,
          display_name,
          is_active
        )
        values ($1, $2, true)
        returning id, canonical_name, display_name, is_active, is_system, version,
          created_at, updated_at, deleted_at
      `,
      [input.canonicalName, input.displayName],
    );
    return result.rows[0]!;
  }

  async updateSource(
    client: PoolClient,
    sourceId: string,
    input: {
      expectedVersion: number;
      canonicalName?: string;
      displayName?: string;
      isActive?: boolean;
    },
  ): Promise<LeadSourceRow | null> {
    const result = await client.query<LeadSourceRow>(
      `
        update app.lead_sources
        set canonical_name = coalesce($3, canonical_name),
          display_name = coalesce($4, display_name),
          is_active = coalesce($5, is_active),
          deleted_at = case
            when $5::boolean is true then null
            when $5::boolean is false then coalesce(deleted_at, now())
            else deleted_at
          end,
          version = version + 1,
          updated_at = now()
        where id = $1
          and version = $2
        returning id, canonical_name, display_name, is_active, is_system, version,
          created_at, updated_at, deleted_at
      `,
      [
        sourceId,
        input.expectedVersion,
        input.canonicalName ?? null,
        input.displayName ?? null,
        input.isActive ?? null,
      ],
    );
    return result.rows[0] ?? null;
  }

  async listDefinitions(
    entityType: ClientEntityType | undefined,
    includeArchived: boolean,
  ): Promise<ClientCustomFieldDefinitionRow[]> {
    const result = await this.database.query<ClientCustomFieldDefinitionRow>(
      `
          select id, field_key, label, value_type, is_required,
            is_active, is_system, options, version, created_at, updated_at,
            deleted_at, category_key, category_label, sort_order, width, placements,
            visible_on_lead, visible_on_student
          from app.client_custom_field_definitions
          where ($1::text is null
              or ($1 = 'lead' and visible_on_lead)
              or ($1 = 'student' and visible_on_student))
            and ($2::boolean or (is_active and deleted_at is null))
          order by
            is_system desc,
            (deleted_at is not null or not is_active) asc,
            sort_order asc,
            lower(label) asc,
            id asc
        `,
      [entityType ?? null, includeArchived],
    );
    return result.rows;
  }

  async findDefinitionsByIds(
    entityType: ClientEntityType,
    definitionIds: string[],
  ): Promise<ClientCustomFieldDefinitionRow[]> {
    if (definitionIds.length === 0) return [];
    const result = await this.database.query<ClientCustomFieldDefinitionRow>(
      `
          select id, field_key, label, value_type, is_required,
            is_active, is_system, options, version, created_at, updated_at,
            deleted_at, visible_on_lead, visible_on_student
          from app.client_custom_field_definitions
          where id = any($2::uuid[])
            and (($1 = 'lead' and visible_on_lead)
              or ($1 = 'student' and visible_on_student))
        `,
      [entityType, definitionIds],
    );
    return result.rows;
  }

  async listRequiredCustomDefinitions(
    entityType: ClientEntityType,
  ): Promise<ClientCustomFieldDefinitionRow[]> {
    const result = await this.database.query<ClientCustomFieldDefinitionRow>(
      `
          select id, field_key, label, value_type, is_required,
            is_active, is_system, options, version, created_at, updated_at,
            deleted_at, visible_on_lead, visible_on_student
          from app.client_custom_field_definitions
          where is_required
            and (($1 = 'lead' and visible_on_lead)
              or ($1 = 'student' and visible_on_student))
            and not is_system
            and is_active
            and deleted_at is null
          order by field_key asc
        `,
      [entityType],
    );
    return result.rows;
  }

  async createDefinition(
    client: PoolClient,
    input: {
      key: string;
      label: string;
      valueType: ClientCustomValueType;
      required: boolean;
      options: string[];
      visibleOnLead: boolean;
      visibleOnStudent: boolean;
    },
  ): Promise<ClientCustomFieldDefinitionRow> {
    const result = await client.query<ClientCustomFieldDefinitionRow>(
      `
          insert into app.client_custom_field_definitions (
            field_key,
            label,
            value_type,
            is_required,
            options,
            visible_on_lead,
            visible_on_student
          )
          values ($1, $2, $3, $4, $5::jsonb, $6, $7)
          returning id, field_key, label, value_type,
            is_required, is_active, is_system, options, version, created_at,
            updated_at, deleted_at, visible_on_lead, visible_on_student
        `,
      [
        input.key,
        input.label,
        input.valueType,
        input.required,
        JSON.stringify(input.options),
        input.visibleOnLead,
        input.visibleOnStudent,
      ],
    );
    return result.rows[0]!;
  }

  async findDefinitionForUpdate(
    client: PoolClient,
    definitionId: string,
  ): Promise<ClientCustomFieldDefinitionRow | null> {
    const result = await client.query<ClientCustomFieldDefinitionRow>(
      `
          select id, field_key, label, value_type, is_required,
            is_active, is_system, options, version, created_at, updated_at,
            deleted_at, visible_on_lead, visible_on_student
          from app.client_custom_field_definitions
          where id = $1
          for update
        `,
      [definitionId],
    );
    return result.rows[0] ?? null;
  }

  async countDefinitionValues(
    client: PoolClient,
    definitionId: string,
  ): Promise<number> {
    const result = await client.query<{ count: string | number }>(
      `
        select count(*) as count
        from app.client_custom_field_values
        where definition_id = $1
      `,
      [definitionId],
    );
    return Number(result.rows[0]?.count ?? 0);
  }

  async updateDefinition(
    client: PoolClient,
    definitionId: string,
    input: {
      expectedVersion: number;
      label?: string;
      valueType?: ClientCustomValueType;
      required?: boolean;
      isActive?: boolean;
      options?: string[];
      visibleOnLead?: boolean;
      visibleOnStudent?: boolean;
    },
  ): Promise<ClientCustomFieldDefinitionRow | null> {
    const result = await client.query<ClientCustomFieldDefinitionRow>(
      `
          update app.client_custom_field_definitions
          set label = coalesce($3, label),
            value_type = coalesce($4, value_type),
            is_required = coalesce($5, is_required),
            is_active = coalesce($6, is_active),
            options = coalesce($7::jsonb, options),
            visible_on_lead = coalesce($8, visible_on_lead),
            visible_on_student = coalesce($9, visible_on_student),
            deleted_at = case
              when $6::boolean is true then null
              when $6::boolean is false then coalesce(deleted_at, now())
              else deleted_at
            end,
            version = version + 1,
            updated_at = now()
          where id = $1
            and version = $2
          returning id, field_key, label, value_type,
            is_required, is_active, is_system, options, version, created_at,
            updated_at, deleted_at, visible_on_lead, visible_on_student
        `,
      [
        definitionId,
        input.expectedVersion,
        input.label ?? null,
        input.valueType ?? null,
        input.required ?? null,
        input.isActive ?? null,
        input.options === undefined ? null : JSON.stringify(input.options),
        input.visibleOnLead ?? null,
        input.visibleOnStudent ?? null,
      ],
    );
    return result.rows[0] ?? null;
  }

  async branchExists(branchId: string): Promise<boolean> {
    const result = await this.database.query<{ exists: boolean }>(
      `
        select exists (
          select 1
          from app.branches
          where id = $1 and deleted_at is null
        ) as exists
      `,
      [branchId],
    );
    return result.rows[0]?.exists ?? false;
  }

  async saveValues(
    client: PoolClient,
    entityType: ClientEntityType,
    entityId: string,
    values: TypedClientCustomFieldWrite[],
  ): Promise<void> {
    await saveTypedClientValues(client, entityType, entityId, values);
  }
}
