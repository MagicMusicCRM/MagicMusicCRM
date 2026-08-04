import { Injectable, UnprocessableEntityException } from "@nestjs/common";
import { isEmail } from "class-validator";
import { normalizePhoneRu } from "../phone.util";
import {
  ClientCustomFieldInputDto,
  ClientCustomValueType,
  ClientEntityType,
  StrictCreateLeadDto,
  StrictCreateStudentDto,
} from "../dto/client-config.dto";
import {
  ClientConfigRepository,
  ClientCustomFieldDefinitionRow,
  TypedClientCustomValue,
} from "./client-config.repository";

export interface ClientValidationWarning {
  field: string;
  code: "PHONE_NORMALIZED";
  normalizedValue: string;
}

export interface ValidatedLeadCreate {
  firstName: string;
  lastName: string;
  phone: string;
  sourceId: string;
  sourceCanonicalName: string;
  sourceDisplayName: string;
  customFields: TypedClientCustomValue[];
  warnings: ClientValidationWarning[];
}

export interface ValidatedStudentCreate {
  firstName: string;
  lastName: string;
  phone: string;
  branchId: string;
  status: string;
  customFields: TypedClientCustomValue[];
  warnings: ClientValidationWarning[];
}

@Injectable()
export class ClientWriteValidator {
  constructor(private readonly repository: ClientConfigRepository) {}

  async validateLeadCreate(
    dto: StrictCreateLeadDto,
  ): Promise<ValidatedLeadCreate> {
    const firstName = this.requiredText(dto.firstName, "firstName");
    const lastName = this.requiredText(dto.lastName, "lastName");
    const phone = this.normalizeRequiredPhone(dto.phone, "phone");
    const source = await this.repository.findActiveSource(dto.sourceId);
    if (!source) {
      this.fail("sourceId", "SOURCE_INACTIVE", "Выберите активный источник.");
    }
    const custom = await this.validateCustomFields(
      "lead",
      dto.customFields ?? [],
    );
    return {
      firstName,
      lastName,
      phone: phone.value,
      sourceId: source.id,
      sourceCanonicalName: source.canonical_name,
      sourceDisplayName: source.display_name,
      customFields: custom.values,
      warnings: [...phone.warnings, ...custom.warnings],
    };
  }

  async validateStudentCreate(
    dto: StrictCreateStudentDto,
  ): Promise<ValidatedStudentCreate> {
    const firstName = this.requiredText(dto.firstName, "firstName");
    const lastName = this.requiredText(dto.lastName, "lastName");
    const phone = this.normalizeRequiredPhone(dto.phone, "phone");
    const status = this.requiredText(dto.status, "status");
    if (!(await this.repository.branchExists(dto.branchId))) {
      this.fail("branchId", "BRANCH_INACTIVE", "Выберите активный филиал.");
    }
    const custom = await this.validateCustomFields(
      "student",
      dto.customFields ?? [],
    );
    return {
      firstName,
      lastName,
      phone: phone.value,
      branchId: dto.branchId,
      status,
      customFields: custom.values,
      warnings: [...phone.warnings, ...custom.warnings],
    };
  }

  async validateCustomFields(
    entityType: ClientEntityType,
    inputs: ClientCustomFieldInputDto[],
  ): Promise<{
    values: TypedClientCustomValue[];
    warnings: ClientValidationWarning[];
  }> {
    const ids = inputs.map((input) => input.definitionId);
    if (new Set(ids).size !== ids.length) {
      this.fail(
        "customFields",
        "DUPLICATE_FIELD",
        "Дополнительное поле передано больше одного раза.",
      );
    }
    const [definitions, required] = await Promise.all([
      this.repository.findDefinitionsByIds(entityType, ids),
      this.repository.listRequiredCustomDefinitions(entityType),
    ]);
    const byId = new Map(
      definitions.map((definition) => [definition.id, definition]),
    );
    for (const definition of required) {
      if (!ids.includes(definition.id)) {
        this.fail(
          `customFields.${definition.field_key}`,
          "REQUIRED_CUSTOM_FIELD",
          `Поле «${definition.label}» обязательно.`,
        );
      }
    }

    const values: TypedClientCustomValue[] = [];
    const warnings: ClientValidationWarning[] = [];
    for (const input of inputs) {
      const definition = byId.get(input.definitionId);
      if (
        !definition ||
        definition.is_system ||
        !definition.is_active ||
        definition.deleted_at !== null
      ) {
        this.fail(
          "customFields",
          "FIELD_INACTIVE",
          "Дополнительное поле не найдено или архивировано.",
        );
      }
      const converted = this.convertValue(definition, input.value);
      values.push(converted.value);
      warnings.push(...converted.warnings);
    }
    return { values, warnings };
  }

  private convertValue(
    definition: ClientCustomFieldDefinitionRow,
    raw: unknown,
  ): {
    value: TypedClientCustomValue;
    warnings: ClientValidationWarning[];
  } {
    const empty: TypedClientCustomValue = {
      definitionId: definition.id,
      valueText: null,
      valueNumber: null,
      valueBoolean: null,
      valueDate: null,
      valueJson: null,
    };
    const field = `customFields.${definition.field_key}`;
    const type = definition.value_type;

    if (type === "number" || type === "money" || type === "duration") {
      if (typeof raw !== "number" || !Number.isFinite(raw)) {
        this.invalidType(field, type);
      }
      return {
        value: { ...empty, valueNumber: raw },
        warnings: [],
      };
    }
    if (type === "boolean" || type === "toggle") {
      if (typeof raw !== "boolean") {
        this.invalidType(field, type);
      }
      return {
        value: { ...empty, valueBoolean: raw },
        warnings: [],
      };
    }

    if (type === "multi_select" || type === "checkbox_group") {
      if (!Array.isArray(raw) || raw.some((item) => typeof item !== "string")) {
        this.invalidType(field, type);
      }
      const options = Array.isArray(definition.options)
        ? definition.options.filter(
            (option): option is string => typeof option === "string",
          )
        : [];
      const selected = [...new Set(raw as string[])];
      if (selected.some((item) => !options.includes(item))) {
        this.fail(
          field,
          "OPTION_INACTIVE",
          `Значение поля «${definition.label}» отсутствует в справочнике.`,
        );
      }
      return { value: { ...empty, valueJson: selected }, warnings: [] };
    }

    if (typeof raw !== "string" || !raw.trim()) {
      this.invalidType(field, type);
    }
    const text = raw.trim();
    if (type === "date") {
      if (!this.isIsoDate(text)) {
        this.invalidType(field, type);
      }
      return {
        value: { ...empty, valueDate: text },
        warnings: [],
      };
    }
    if (type === "datetime" && Number.isNaN(Date.parse(text))) {
      this.invalidType(field, type);
    }
    if (type === "email" && !isEmail(text)) {
      this.invalidType(field, type);
    }
    if (type === "select" || type === "radio") {
      const options = Array.isArray(definition.options)
        ? definition.options.filter(
            (option): option is string => typeof option === "string",
          )
        : [];
      if (!options.includes(text)) {
        this.fail(
          field,
          "OPTION_INACTIVE",
          `Значение поля «${definition.label}» отсутствует в справочнике.`,
        );
      }
    }
    if (type === "phone") {
      const phone = this.normalizeRequiredPhone(text, field);
      return {
        value: { ...empty, valueText: phone.value },
        warnings: phone.warnings,
      };
    }
    if (type === "url") {
      try {
        const parsed = new URL(text);
        if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
          this.invalidType(field, type);
        }
      } catch {
        this.invalidType(field, type);
      }
    }
    return {
      value: { ...empty, valueText: text },
      warnings: [],
    };
  }

  private normalizeRequiredPhone(
    raw: string,
    field: string,
  ): { value: string; warnings: ClientValidationWarning[] } {
    const normalized = normalizePhoneRu(raw);
    if (!normalized.canonical) {
      this.fail(
        field,
        "INVALID_PHONE",
        "Укажите корректный российский номер телефона.",
      );
    }
    const trimmed = raw.trim();
    return {
      value: normalized.canonical,
      warnings:
        trimmed === normalized.canonical
          ? []
          : [
              {
                field,
                code: "PHONE_NORMALIZED",
                normalizedValue: normalized.canonical,
              },
            ],
    };
  }

  private requiredText(value: string, field: string): string {
    const trimmed = value?.trim();
    if (!trimmed) {
      this.fail(field, "REQUIRED", "Обязательное поле не заполнено.");
    }
    return trimmed;
  }

  private isIsoDate(value: string): boolean {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
    const date = new Date(`${value}T00:00:00.000Z`);
    return (
      Number.isFinite(date.getTime()) &&
      date.toISOString().slice(0, 10) === value
    );
  }

  private invalidType(field: string, type: ClientCustomValueType): never {
    return this.fail(
      field,
      "INVALID_FIELD_TYPE",
      `Значение не соответствует типу ${type}.`,
    );
  }

  private fail(field: string, code: string, message: string): never {
    throw new UnprocessableEntityException({
      code,
      field,
      message,
    });
  }
}
