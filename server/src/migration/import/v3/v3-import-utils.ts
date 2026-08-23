import { createHash } from 'node:crypto';
import { deterministicUuid } from '../../import-id';

export type SourceRow = Record<string, unknown>;

export interface TargetRow {
  table: string;
  data: Record<string, unknown>;
  conflictColumns: string[];
}

export interface ImportWarning {
  code: string;
  message: string;
  source?: string;
  rowId?: string;
}

export function asString(value: unknown): string | undefined {
  if (typeof value !== 'string') return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

export function asBoolean(value: unknown): boolean | undefined {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'string') {
    if (value.toLowerCase() === 'true') return true;
    if (value.toLowerCase() === 'false') return false;
  }
  return undefined;
}

export function asNumber(value: unknown): number | undefined {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return undefined;
}

export function asJsonObject(value: unknown): Record<string, unknown> {
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return {};
}

export function isUuid(value: unknown): value is string {
  return typeof value === 'string'
    && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

export function nullableUuid(value: unknown): string | null {
  return isUuid(value) ? value : null;
}

export function normalizeRole(value: unknown): 'client' | 'teacher' | 'manager' | 'admin' | 'director' | 'system_admin' {
  const normalized = asString(value)?.toLowerCase();
  if (normalized === 'system_admin' || normalized === 'system-admin' || normalized === 'superadmin' || normalized === 'super_admin') return 'system_admin';
  if (normalized === 'director') return 'director';
  if (normalized === 'admin' || normalized === 'administrator' || normalized === 'owner') return 'admin';
  if (normalized === 'manager' || normalized === 'staff' || normalized === 'moderator') return 'manager';
  if (normalized === 'teacher' || normalized === 'instructor') return 'teacher';
  return 'client';
}

export function normalizeMessageType(value: unknown): 'text' | 'file' | 'voice' | 'system' {
  const normalized = asString(value)?.toLowerCase();
  if (normalized === 'voice' || normalized === 'audio') return 'voice';
  if (normalized === 'file' || normalized === 'image' || normalized === 'attachment') return 'file';
  if (normalized === 'system') return 'system';
  return 'text';
}

export function normalizeDeletionStatus(value: unknown): 'pending' | 'processing' | 'completed' | 'rejected' | 'cancelled' {
  const normalized = asString(value)?.toLowerCase();
  if (normalized === 'processing') return 'processing';
  if (normalized === 'completed' || normalized === 'done' || normalized === 'approved') return 'completed';
  if (normalized === 'rejected' || normalized === 'declined') return 'rejected';
  if (normalized === 'cancelled' || normalized === 'canceled') return 'cancelled';
  return 'pending';
}

export function normalizeLegalDocumentType(value: unknown): 'privacy_policy' | 'terms_of_use' | 'account_deletion' | undefined {
  const normalized = asString(value)?.toLowerCase();
  if (!normalized) return undefined;
  if (['privacy', 'privacy_policy', 'policy'].includes(normalized)) return 'privacy_policy';
  if (['terms', 'terms_of_use', 'offer', 'agreement'].includes(normalized)) return 'terms_of_use';
  if (['account_deletion', 'deletion', 'delete_account'].includes(normalized)) return 'account_deletion';
  return undefined;
}

// deterministicUuid жил здесь и был вынесен в ./import-id, когда этот файл
// удалили из дерева. Реэкспорт, а не вторая копия: схема id — то, чем импорт
// попадает в уже существующие записи, и разъехавшись, две копии задвоили бы всю
// базу.
// (import, а не `export ... from`: directChatId ниже зовёт её же.)
export { deterministicUuid };

export function sha256Hex(value: string): string {
  return createHash('sha256').update(value).digest('hex');
}

export function compactObject<T extends Record<string, unknown>>(value: T): T {
  return Object.fromEntries(
    Object.entries(value).filter(([, nested]) => nested !== undefined)
  ) as T;
}

export function splitFullName(row: SourceRow): { firstName?: string; lastName?: string } {
  const firstName = asString(row.first_name);
  const lastName = asString(row.last_name);
  if (firstName || lastName) return { firstName, lastName };

  const fullName = asString(row.name);
  if (!fullName) return {};
  const parts = fullName.split(/\s+/);
  return {
    firstName: parts[0],
    lastName: parts.length > 1 ? parts.slice(1).join(' ') : undefined
  };
}

export function directChatId(leftUserId: string, rightUserId: string): string {
  const participants = [leftUserId, rightUserId].sort().join(':');
  return deterministicUuid('legacy-direct-chat', participants);
}
