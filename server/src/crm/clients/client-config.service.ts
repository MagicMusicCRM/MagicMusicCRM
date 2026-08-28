import {
  ConflictException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { AuditService } from "../../audit/audit.service";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import {
  ClientConfigListQuery,
  CreateClientCustomFieldDto,
  CreateLeadSourceDto,
  UpdateClientCustomFieldDto,
  UpdateLeadSourceDto,
} from "../dto/client-config.dto";
import { CrmPolicy } from "../crm.policy";
import {
  ClientConfigRepository,
  ClientCustomFieldDefinitionRow,
  LeadSourceRow,
} from "./client-config.repository";

type FieldUpdateClient = Parameters<ClientConfigRepository["findDefinitionForUpdate"]>[0]; type FieldUpdateResult = { before: ClientCustomFieldDefinitionRow; updated: ClientCustomFieldDefinitionRow };

function changesFieldType(before: ClientCustomFieldDefinitionRow, dto: UpdateClientCustomFieldDto) { return dto.valueType !== undefined && dto.valueType !== before.value_type; }
function removesLeadVisibility(before: ClientCustomFieldDefinitionRow, dto: UpdateClientCustomFieldDto) { return dto.visibleOnLead === false && before.visible_on_lead; }
function removesStudentVisibility(before: ClientCustomFieldDefinitionRow, dto: UpdateClientCustomFieldDto) { return dto.visibleOnStudent === false && before.visible_on_student; }

function isUniqueViolation(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    (error as { code?: string }).code === "23505"
  );
}

@Injectable()
export class ClientConfigService {
  constructor(
    private readonly database: DatabaseService,
    private readonly repository: ClientConfigRepository,
    private readonly policy: CrmPolicy,
    private readonly audit: AuditService,
  ) {}

  async listSources(actor: ActorContext, query: ClientConfigListQuery) {
    this.policy.assertCanReadOperationalData(actor);
    return {
      items: (
        await this.repository.listSources(query.includeArchived ?? false)
      ).map((row) => this.toSourceDto(row)),
    };
  }

  async createSource(actor: ActorContext, dto: CreateLeadSourceDto) {
    this.policy.assertCanManageClientConfiguration(actor);
    const canonicalName = dto.canonicalName.trim().toLowerCase();
    const displayName = this.requiredText(dto.displayName, "displayName");
    let source: LeadSourceRow;
    try {
      source = await this.database.transaction((client) =>
        this.repository.createSource(client, {
          canonicalName,
          displayName,
        }),
      );
    } catch (error) {
      if (isUniqueViolation(error)) {
        throw new ConflictException("Источник с таким ключом уже существует.");
      }
      throw error;
    }
    await this.audit.record({
      actor,
      action: "crm.lead_source_created",
      entityType: "lead_source",
      entityId: source.id,
      metadata: { canonicalName },
    });
    return this.toSourceDto(source);
  }

  async updateSource(
    actor: ActorContext,
    sourceId: string,
    dto: UpdateLeadSourceDto,
  ) {
    this.policy.assertCanManageClientConfiguration(actor);
    let source: { before: LeadSourceRow; updated: LeadSourceRow };
    try {
      source = await this.database.transaction(async (client) => {
        const current = await client.query<LeadSourceRow>(
          `
            select id, canonical_name, display_name, is_active, is_system, version,
              created_at, updated_at, deleted_at
            from app.lead_sources
            where id = $1
            for update
          `,
          [sourceId],
        );
        const before = current.rows[0];
        if (!before) throw new NotFoundException("Источник не найден.");
        if (Number(before.version) !== dto.expectedVersion) {
          throw new ConflictException("Источник уже изменён в другой вкладке.");
        }
        if (
          before.is_system &&
          ((dto.canonicalName !== undefined &&
            dto.canonicalName.trim().toLowerCase() !== before.canonical_name) ||
            (dto.displayName !== undefined &&
              dto.displayName.trim() !== before.display_name) ||
            dto.isActive === false)
        ) {
          throw new UnprocessableEntityException({
            code: "SYSTEM_SOURCE_IMMUTABLE",
            field: "sourceId",
            message:
              "Системный источник «Приложение» нельзя переименовать или архивировать.",
          });
        }
        const updated = await this.repository.updateSource(client, sourceId, {
          expectedVersion: dto.expectedVersion,
          canonicalName: dto.canonicalName?.trim().toLowerCase(),
          displayName:
            dto.displayName === undefined
              ? undefined
              : this.requiredText(dto.displayName, "displayName"),
          isActive: dto.isActive,
        });
        if (!updated) {
          throw new ConflictException("Источник уже изменён в другой вкладке.");
        }
        return { before, updated };
      });
    } catch (error) {
      if (isUniqueViolation(error)) {
        throw new ConflictException("Источник с таким ключом уже существует.");
      }
      throw error;
    }
    await this.audit.record({
      actor,
      action: source.updated.is_active
        ? "crm.lead_source_updated"
        : "crm.lead_source_archived",
      entityType: "lead_source",
      entityId: sourceId,
      metadata: {
        beforeVersion: Number(source.before.version),
        afterVersion: Number(source.updated.version),
      },
    });
    return this.toSourceDto(source.updated);
  }

  async listFields(actor: ActorContext, query: ClientConfigListQuery) {
    this.policy.assertCanReadOperationalData(actor);
    return {
      items: (
        await this.repository.listDefinitions(
          query.entityType,
          query.includeArchived ?? false,
        )
      ).map((row) => this.toFieldDto(row)),
    };
  }

  async createField(actor: ActorContext, dto: CreateClientCustomFieldDto) {
    this.policy.assertCanManageClientConfiguration(actor);
    const label = this.requiredText(dto.label, "label");
    const options = this.normalizeOptions(dto.valueType, dto.options);
    const visibility = this.visibility(
      dto.visibleOnLead,
      dto.visibleOnStudent,
    );
    let field: ClientCustomFieldDefinitionRow;
    try {
      field = await this.database.transaction((client) =>
        this.repository.createDefinition(client, {
          key: dto.key.trim(),
          label,
          valueType: dto.valueType,
          required: dto.required ?? false,
          options,
          ...visibility,
        }),
      );
    } catch (error) {
      if (isUniqueViolation(error)) {
        throw new ConflictException(
          "Поле с таким ключом уже существует.",
        );
      }
      throw error;
    }
    await this.audit.record({
      actor,
      action: "crm.client_custom_field_created",
      entityType: "client_custom_field",
      entityId: field.id,
      metadata: {
        visibility: {
          lead: field.visible_on_lead,
          student: field.visible_on_student,
        },
        key: field.field_key,
        valueType: field.value_type,
        required: field.is_required,
      },
    });
    return this.toFieldDto(field);
  }

  async updateField(
    actor: ActorContext,
    definitionId: string,
    dto: UpdateClientCustomFieldDto,
  ) {
    this.policy.assertCanManageClientConfiguration(actor);
    const result = await this.database.transaction((client) =>
      this.updateFieldInTransaction(client, definitionId, dto),
    );
    await this.recordFieldUpdateAudit(actor, definitionId, result);
    return this.toFieldDto(result.updated);
  }

  private async updateFieldInTransaction(
    client: FieldUpdateClient,
    definitionId: string,
    dto: UpdateClientCustomFieldDto,
  ): Promise<FieldUpdateResult> {
    const before = this.requireFieldDefinition(
      await this.repository.findDefinitionForUpdate(client, definitionId),
    );
    if (Number(before.version) !== dto.expectedVersion) {
      throw new ConflictException(
        "Дополнительное поле уже изменено в другой вкладке.",
      );
    }
    this.assertSystemFieldUpdate(before, dto);
    await this.assertFieldTypeMigration(client, definitionId, before, dto);
    const updated = await this.repository.updateDefinition(
      client,
      definitionId,
      this.fieldUpdatePatch(before, dto),
    );
    if (!updated) {
      throw new ConflictException(
        "Дополнительное поле уже изменено в другой вкладке.",
      );
    }
    return { before, updated };
  }

  private requireFieldDefinition(before: ClientCustomFieldDefinitionRow | null): ClientCustomFieldDefinitionRow {
    if (!before) throw new NotFoundException("Дополнительное поле не найдено.");
    return before;
  }

  private assertSystemFieldUpdate(before: ClientCustomFieldDefinitionRow,
    dto: UpdateClientCustomFieldDto): void {
    if (!before.is_system) return;
    const lockedChanges = [
      () => dto.required === false,
      () => dto.isActive === false,
      () => changesFieldType(before, dto),
      () => dto.options !== undefined,
      () => removesLeadVisibility(before, dto),
      () => removesStudentVisibility(before, dto),
    ];
    if (!lockedChanges.some((isLocked) => isLocked())) return;
    throw new UnprocessableEntityException({
      code: "SYSTEM_FIELD_LOCKED",
      field: "field",
      message: "Системное обязательное поле нельзя архивировать, сделать необязательным или изменить его тип.",
    });
  }

  private async assertFieldTypeMigration(
    client: FieldUpdateClient,
    definitionId: string,
    before: ClientCustomFieldDefinitionRow,
    dto: UpdateClientCustomFieldDto,
  ): Promise<void> {
    if (dto.valueType === undefined) return;
    if (dto.valueType === before.value_type) return;
    const count = await this.repository.countDefinitionValues(client, definitionId);
    if (count <= 0) return;
    throw new UnprocessableEntityException({
      code: "FIELD_TYPE_MIGRATION_REQUIRED",
      field: "valueType",
      message: "Тип поля с существующими значениями меняется только отдельной миграцией.",
    });
  }

  private fieldUpdatePatch(
    before: ClientCustomFieldDefinitionRow,
    dto: UpdateClientCustomFieldDto,
  ) {
    const options =
      dto.options === undefined
        ? undefined
        : this.normalizeOptions(
            dto.valueType ?? before.value_type,
            dto.options,
          );
    this.assertFieldUpdateVisibility(before, dto);
    return {
      expectedVersion: dto.expectedVersion,
      label:
        dto.label === undefined
          ? undefined
          : this.requiredText(dto.label, "label"),
      valueType: dto.valueType,
      required: dto.required,
      isActive: dto.isActive,
      options,
      visibleOnLead: dto.visibleOnLead,
      visibleOnStudent: dto.visibleOnStudent,
    };
  }

  private assertFieldUpdateVisibility(
    before: ClientCustomFieldDefinitionRow,
    dto: UpdateClientCustomFieldDto,
  ): void {
    const nextVisibleOnLead = dto.visibleOnLead ?? before.visible_on_lead;
    const nextVisibleOnStudent = dto.visibleOnStudent ?? before.visible_on_student;
    if (
      (dto.isActive ?? before.is_active) &&
      !nextVisibleOnLead &&
      !nextVisibleOnStudent
    ) {
      throw new UnprocessableEntityException({
        code: "FIELD_VISIBILITY_REQUIRED",
        field: "visibility",
        message:
          "Активное поле должно быть видно хотя бы в карточке лида или ученика.",
      });
    }
  }

  private async recordFieldUpdateAudit(actor: ActorContext, definitionId: string,
    result: FieldUpdateResult): Promise<void> {
    await this.audit.record({
      actor,
      action: result.updated.is_active
        ? "crm.client_custom_field_updated"
        : "crm.client_custom_field_archived",
      entityType: "client_custom_field",
      entityId: definitionId,
      metadata: {
        beforeVersion: Number(result.before.version),
        afterVersion: Number(result.updated.version),
        valueType: result.updated.value_type,
        required: result.updated.is_required,
      },
    });
  }

  private normalizeOptions(
    valueType: string,
    values: string[] | undefined,
  ): string[] {
    const selectionTypes = new Set([
      "select",
      "radio",
      "multi_select",
      "checkbox_group",
    ]);
    if (!selectionTypes.has(valueType)) {
      if (values && values.length > 0) {
        throw new UnprocessableEntityException({
          code: "OPTIONS_ONLY_FOR_SELECT",
          field: "options",
          message: "Варианты допустимы только для поля типа select.",
        });
      }
      return [];
    }
    const normalized = [
      ...new Set((values ?? []).map((value) => value.trim()).filter(Boolean)),
    ];
    if (normalized.length === 0) {
      throw new UnprocessableEntityException({
        code: "SELECT_OPTIONS_REQUIRED",
        field: "options",
        message: "Для поля типа select нужен хотя бы один вариант.",
      });
    }
    return normalized;
  }

  private requiredText(value: string, field: string): string {
    const trimmed = value.trim();
    if (!trimmed) {
      throw new UnprocessableEntityException({
        code: "REQUIRED",
        field,
        message: "Обязательное поле не заполнено.",
      });
    }
    return trimmed;
  }

  private visibility(
    visibleOnLead: boolean | undefined,
    visibleOnStudent: boolean | undefined,
  ): { visibleOnLead: boolean; visibleOnStudent: boolean } {
    const visibility = {
      visibleOnLead: visibleOnLead ?? true,
      visibleOnStudent: visibleOnStudent ?? true,
    };
    if (!visibility.visibleOnLead && !visibility.visibleOnStudent) {
      throw new UnprocessableEntityException({
        code: "FIELD_VISIBILITY_REQUIRED",
        field: "visibility",
        message:
          "Поле должно быть видно хотя бы в карточке лида или ученика.",
      });
    }
    return visibility;
  }

  private toSourceDto(row: LeadSourceRow) {
    return {
      id: row.id,
      canonicalName: row.canonical_name,
      displayName: row.display_name,
      isActive: row.is_active && row.deleted_at === null,
      isSystem: row.is_system,
      version: Number(row.version),
      archivedAt: row.deleted_at,
    };
  }

  private toFieldDto(row: ClientCustomFieldDefinitionRow) {
    return {
      id: row.id,
      key: row.field_key,
      label: row.label,
      valueType: row.value_type,
      required: row.is_required,
      isActive: row.is_active && row.deleted_at === null,
      isSystem: row.is_system,
      options: Array.isArray(row.options) ? row.options : [],
      version: Number(row.version),
      archivedAt: row.deleted_at,
      categoryKey: row.category_key ?? "general",
      categoryLabel: row.category_label ?? "Основная информация",
      order: Number(row.sort_order ?? 0),
      width: row.width ?? "full",
      placements: Array.isArray(row.placements)
        ? row.placements
        : ["create", "edit", "card"],
      visibility: {
        lead: row.visible_on_lead,
        student: row.visible_on_student,
      },
      visibleOnLead: row.visible_on_lead,
      visibleOnStudent: row.visible_on_student,
    };
  }
}
