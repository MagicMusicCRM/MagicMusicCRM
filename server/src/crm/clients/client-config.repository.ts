import { Injectable } from "@nestjs/common";
import { PoolClient } from "pg";
import { DatabaseService } from "../../db/database.service";
import {
  ClientCustomValueType,
  ClientEntityType,
} from "../dto/client-config.dto";

export interface LeadSourceRow {
  id: string;
  canonical_name: string;
  display_name: string;
  is_active: boolean;
  version: number | string;
  created_at: Date | string;
  updated_at: Date | string;
  deleted_at: Date | string | null;
}

export interface ClientCustomFieldDefinitionRow {
  id: string;
  entity_type: ClientEntityType;
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
}

export interface TypedClientCustomValue {
  definitionId: string;
  valueText: string | null;
  valueNumber: number | null;
  valueBoolean: boolean | null;
  valueDate: string | null;
  valueJson: unknown | null;
}

export async function saveTypedClientValues(
  client: PoolClient,
  entityType: ClientEntityType,
  entityId: string,
  values: TypedClientCustomValue[],
): Promise<void> {
  for (const value of values) {
    await client.query(
      `
        insert into app.client_custom_field_values (
          definition_id,
          entity_type,
          entity_id,
          value_text,
          value_number,
          value_boolean,
          value_date,
          value_json,
          validation_state
        )
        values ($1, $2, $3, $4, $5, $6, $7, $8::jsonb, 'valid')
        on conflict (definition_id, entity_type, entity_id)
        do update set
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
  values: TypedClientCustomValue[],
): Promise<void> {
  const definitionIds = values.map((value) => value.definitionId);
  await client.query(
    `delete from app.client_custom_field_values value
     using app.client_custom_field_definitions definition
     where value.definition_id = definition.id
       and value.entity_type = definition.entity_type
       and value.entity_type = $1 and value.entity_id = $2
       and not definition.is_system
       and definition.is_active and definition.deleted_at is null
       and not (value.definition_id = any($3::uuid[]))`,
    [entityType, entityId, definitionIds],
  );
  await saveTypedClientValues(client, entityType, entityId, values);
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
     and definition.entity_type = value.entity_type
    where value.entity_type = ${entityTypeExpression}
      and value.entity_id = ${entityIdExpression}
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
     and definition.entity_type = value.entity_type
    where value.entity_type = '${entityType}'
      and value.entity_id = ${entityIdExpression}
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
        select id, canonical_name, display_name, is_active, version,
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
        select id, canonical_name, display_name, is_active, version,
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
        returning id, canonical_name, display_name, is_active, version,
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
        returning id, canonical_name, display_name, is_active, version,
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
          select id, entity_type, field_key, label, value_type, is_required,
            is_active, is_system, options, version, created_at, updated_at,
            deleted_at, category_key, category_label, sort_order, width, placements
          from app.client_custom_field_definitions
          where ($1::text is null or entity_type = $1)
            and ($2::boolean or (is_active and deleted_at is null))
          order by
            entity_type asc,
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
          select id, entity_type, field_key, label, value_type, is_required,
            is_active, is_system, options, version, created_at, updated_at,
            deleted_at
          from app.client_custom_field_definitions
          where entity_type = $1
            and id = any($2::uuid[])
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
          select id, entity_type, field_key, label, value_type, is_required,
            is_active, is_system, options, version, created_at, updated_at,
            deleted_at
          from app.client_custom_field_definitions
          where entity_type = $1
            and is_required
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
      entityType: ClientEntityType;
      key: string;
      label: string;
      valueType: ClientCustomValueType;
      required: boolean;
      options: string[];
    },
  ): Promise<ClientCustomFieldDefinitionRow> {
    const result = await client.query<ClientCustomFieldDefinitionRow>(
      `
          insert into app.client_custom_field_definitions (
            entity_type,
            field_key,
            label,
            value_type,
            is_required,
            options
          )
          values ($1, $2, $3, $4, $5, $6::jsonb)
          returning id, entity_type, field_key, label, value_type,
            is_required, is_active, is_system, options, version, created_at,
            updated_at, deleted_at
        `,
      [
        input.entityType,
        input.key,
        input.label,
        input.valueType,
        input.required,
        JSON.stringify(input.options),
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
          select id, entity_type, field_key, label, value_type, is_required,
            is_active, is_system, options, version, created_at, updated_at,
            deleted_at
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
            deleted_at = case
              when $6::boolean is true then null
              when $6::boolean is false then coalesce(deleted_at, now())
              else deleted_at
            end,
            version = version + 1,
            updated_at = now()
          where id = $1
            and version = $2
          returning id, entity_type, field_key, label, value_type,
            is_required, is_active, is_system, options, version, created_at,
            updated_at, deleted_at
        `,
      [
        definitionId,
        input.expectedVersion,
        input.label ?? null,
        input.valueType ?? null,
        input.required ?? null,
        input.isActive ?? null,
        input.options === undefined ? null : JSON.stringify(input.options),
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
    values: TypedClientCustomValue[],
  ): Promise<void> {
    await saveTypedClientValues(client, entityType, entityId, values);
  }
}
