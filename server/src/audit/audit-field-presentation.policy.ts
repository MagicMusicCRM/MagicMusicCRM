import { findDefaultCrmField } from '../settings/crm-custom-field-catalog';
import {
  AuditChangeDisplayMode,
  AuditFieldChangeInput,
  AuditFieldValueType,
  AuditPresentationChange,
} from './audit-presentation.types';

interface AuditFieldPresentationPolicy {
  label: string;
  valueType: AuditFieldValueType;
  displayMode: AuditChangeDisplayMode;
}

const REDACTION_MARKERS = new Set(['[REDACTED]', '[PRIVATE]', '[PII]', '[EMAIL]']);
const TECHNICAL_KEY = /password|token|secret|authorization|credential|otp|hash|session|refresh|cookie|privatekey|fingerprint/i;
const VALUE_TYPES = new Set<AuditFieldValueType>([
  'text', 'date', 'datetime', 'boolean', 'list', 'contact_list', 'reference', 'technical',
]);
const DISPLAY_MODES = new Set<AuditChangeDisplayMode>([
  'values', 'changed_only', 'count', 'hidden',
]);

const CORE_FIELD_ALIASES: Record<string, AuditFieldPresentationPolicy> = {
  first_name: { label: 'Имя', valueType: 'text', displayMode: 'values' },
  last_name: { label: 'Фамилия', valueType: 'text', displayMode: 'values' },
  phone: { label: 'Телефон', valueType: 'text', displayMode: 'values' },
  email: { label: 'Электронная почта', valueType: 'text', displayMode: 'values' },
  source: { label: 'Источник', valueType: 'text', displayMode: 'values' },
  notes: { label: 'Заметки', valueType: 'text', displayMode: 'values' },
  status: { label: 'Статус', valueType: 'text', displayMode: 'values' },
  status_id: { label: 'Статус', valueType: 'reference', displayMode: 'changed_only' },
  assigned_to: { label: 'Ответственный', valueType: 'reference', displayMode: 'changed_only' },
  branch_id: { label: 'Филиал', valueType: 'reference', displayMode: 'changed_only' },
};

const LEGACY_FIELD_ALIASES: Record<string, AuditFieldPresentationPolicy> = {
  disciplines: { label: 'Направления', valueType: 'list', displayMode: 'values' },
  contactPersons: { label: 'Контактные лица', valueType: 'contact_list', displayMode: 'count' },
  visitDateTime: { label: 'Дата и время визита', valueType: 'datetime', displayMode: 'values' },
};

function customDataKey(field: string): string | null {
  const match = /^(?:custom_data|customData)[._](.+)$/.exec(field);
  return match?.[1]?.trim() || null;
}

function isTechnicalField(field: string): boolean {
  const segments = field
    .replace(/([a-zа-я0-9])([A-ZА-Я])/g, '$1.$2')
    .split(/[._:\-\s]+/)
    .filter(Boolean)
    .map((segment) => segment.toLowerCase());
  const collapsed = segments.join('');
  return segments.some((segment) => ['id', 'ids', 'uuid', 'version', 'versions', 'closedby'].includes(segment))
    || collapsed === 'closedby'
    || collapsed === 'bodylength'
    || TECHNICAL_KEY.test(field)
    || TECHNICAL_KEY.test(collapsed);
}

function valueTypeForCatalogField(type: string): AuditFieldValueType {
  if (type === 'date') return 'date';
  if (type === 'boolean') return 'boolean';
  return 'text';
}

function validLabel(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function validValueType(value: unknown): value is AuditFieldValueType {
  return typeof value === 'string' && VALUE_TYPES.has(value as AuditFieldValueType);
}

function validDisplayMode(value: unknown): value is AuditChangeDisplayMode {
  return typeof value === 'string' && DISPLAY_MODES.has(value as AuditChangeDisplayMode);
}

function resolveAuditField(input: AuditFieldChangeInput): AuditFieldPresentationPolicy | null {
  if (!input.field.trim() || isTechnicalField(input.field)) return null;

  const customKey = customDataKey(input.field);
  const catalogField = customKey ? findDefaultCrmField(customKey) : null;
  const legacyAlias = customKey
    ? LEGACY_FIELD_ALIASES[customKey]
    : LEGACY_FIELD_ALIASES[input.field];
  const fallback: AuditFieldPresentationPolicy = CORE_FIELD_ALIASES[input.field]
    ?? (catalogField
      ? {
        label: catalogField.label,
        valueType: valueTypeForCatalogField(catalogField.type),
        displayMode: 'values',
      }
      : legacyAlias ?? { label: 'Дополнительное поле', valueType: 'text', displayMode: 'values' });

  return {
    label: validLabel(input.label) ? input.label : fallback.label,
    valueType: validValueType(input.valueType) ? input.valueType : fallback.valueType,
    displayMode: validDisplayMode(input.displayMode) ? input.displayMode : fallback.displayMode,
  };
}

function isRedactionMarker(value: unknown): boolean {
  return typeof value === 'string' && REDACTION_MARKERS.has(value.trim().toUpperCase());
}

function scalarValue(value: unknown): string | number | boolean | null {
  if (value === null || value === undefined || isRedactionMarker(value)) return null;
  if (value instanceof Date) return value.toISOString();
  if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
    return value === '' ? null : value;
  }
  return null;
}

function primitiveList(value: unknown): (string | number | boolean)[] | null {
  const candidate = typeof value === 'string' && value.trim().startsWith('[')
    ? parseJson(value)
    : value;
  if (!Array.isArray(candidate)) return null;
  if (candidate.some((item) => !['string', 'number', 'boolean'].includes(typeof item))) return null;
  return candidate;
}

function parseJson(value: string): unknown {
  try {
    return JSON.parse(value);
  } catch {
    return undefined;
  }
}

function contactCount(value: unknown): number | null {
  if (typeof value === 'number' && Number.isInteger(value) && value >= 0) return value;
  const candidate = typeof value === 'string' && value.trim().startsWith('[')
    ? parseJson(value)
    : value;
  return Array.isArray(candidate) ? candidate.length : null;
}

function safeStorageValue(value: unknown, valueType: AuditFieldValueType): unknown {
  if (valueType === 'list') return primitiveList(value);
  return scalarValue(value);
}

function hasUnsupportedValue(value: unknown, valueType: AuditFieldValueType): boolean {
  if (value === null || value === undefined || isRedactionMarker(value)) return false;
  return valueType === 'list'
    ? primitiveList(value) === null
    : scalarValue(value) === null;
}

function validIsoDate(value: string): RegExpExecArray | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return null;
  const date = new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])));
  return date.getUTCFullYear() === Number(match[1])
    && date.getUTCMonth() === Number(match[2]) - 1
    && date.getUTCDate() === Number(match[3])
    ? match
    : null;
}

function formatDate(value: string): string {
  const match = validIsoDate(value);
  return match ? `${match[3]}.${match[2]}.${match[1]}` : value;
}

function formatDateTime(value: string): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:\d{2})$/.exec(value);
  if (!match || !validIsoDate(`${match[1]}-${match[2]}-${match[3]}`)) return value;
  const hours = Number(match[4]);
  const minutes = Number(match[5]);
  return hours < 24 && minutes < 60
    ? `${match[3]}.${match[2]}.${match[1]} ${match[4]}:${match[5]}`
    : value;
}

function formatValue(value: unknown, valueType: AuditFieldValueType): string | null {
  if (valueType === 'list') {
    const list = primitiveList(value);
    if (!list) return null;
    const values = list
      .map((item) => scalarValue(item))
      .filter((item): item is string | number | boolean => item !== null);
    return values.length === 0 ? null : values.map(String).join(', ');
  }

  const scalar = scalarValue(value);
  if (scalar === null) return null;
  if (valueType === 'boolean' && typeof scalar === 'boolean') return scalar ? 'Да' : 'Нет';
  if (valueType === 'date' && typeof scalar === 'string') return formatDate(scalar);
  if (valueType === 'datetime' && typeof scalar === 'string') return formatDateTime(scalar);
  return String(scalar);
}

function countLabel(count: number): string {
  return `Контактных лиц: ${count}`;
}

export function createSafeAuditChange(
  input: AuditFieldChangeInput,
): AuditFieldChangeInput | null {
  const policy = resolveAuditField(input);
  if (!policy || policy.displayMode === 'hidden' || policy.valueType === 'technical') return null;

  if (policy.displayMode === 'changed_only') {
    return {
      field: input.field,
      from: null,
      to: null,
      label: policy.label,
      valueType: policy.valueType,
      displayMode: 'changed_only',
    };
  }

  if (policy.valueType === 'contact_list' || policy.displayMode === 'count') {
    const from = contactCount(input.from);
    const to = contactCount(input.to);
    if (from === null || to === null) {
      return {
        field: input.field,
        from: null,
        to: null,
        label: policy.label,
        valueType: policy.valueType,
        displayMode: 'changed_only',
      };
    }
    return {
      field: input.field,
      from,
      to,
      label: policy.label,
      valueType: policy.valueType,
      displayMode: 'count',
    };
  }

  if (hasUnsupportedValue(input.from, policy.valueType) || hasUnsupportedValue(input.to, policy.valueType)) {
    return {
      field: input.field,
      from: null,
      to: null,
      label: policy.label,
      valueType: policy.valueType,
      displayMode: 'changed_only',
    };
  }

  return {
    field: input.field,
    from: safeStorageValue(input.from, policy.valueType),
    to: safeStorageValue(input.to, policy.valueType),
    label: policy.label,
    valueType: policy.valueType,
    displayMode: policy.displayMode,
  };
}

export function presentAuditFieldChange(
  input: AuditFieldChangeInput,
): AuditPresentationChange | null {
  const policy = resolveAuditField(input);
  if (!policy || policy.displayMode === 'hidden' || policy.valueType === 'technical') return null;

  if (policy.displayMode === 'changed_only') {
    return { key: input.field, label: policy.label, before: null, after: null };
  }

  if (policy.valueType === 'contact_list' || policy.displayMode === 'count') {
    const from = contactCount(input.from);
    const to = contactCount(input.to);
    return {
      key: input.field,
      label: policy.label,
      before: from === null ? null : countLabel(from),
      after: to === null ? null : countLabel(to),
    };
  }

  const before = formatValue(input.from, policy.valueType);
  const after = formatValue(input.to, policy.valueType);
  if (hasUnsupportedValue(input.from, policy.valueType) || hasUnsupportedValue(input.to, policy.valueType)) {
    return { key: input.field, label: policy.label, before: null, after: null };
  }
  return { key: input.field, label: policy.label, before, after };
}
