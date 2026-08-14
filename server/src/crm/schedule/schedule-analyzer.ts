import {
  ConstraintResourceRef,
  ConstraintViolation,
  ConstraintViolationCode,
} from "./constraint-engine.types";

export interface ScheduleConflictScope {
  rowIndex?: number;
  studentId?: string;
  localDate?: string;
}

export interface ScopedConstraintViolation {
  violation: ConstraintViolation;
  scope?: ScheduleConflictScope;
}

export interface ScheduleConflictGroup {
  fingerprint: string;
  code: ConstraintViolationCode;
  resource: ConstraintResourceRef;
  occurrences: number;
  conflictingLessonIds: string[];
  ruleIds: string[];
  scopes: ScheduleConflictScope[];
}

export type ScheduleSuggestionKind =
  | "SAME_TIME_ROOM"
  | "NEAREST_TIME"
  | "SAME_SPECIALIZATION_TEACHER"
  | "COMBINED";

export interface ScheduleSuggestionChanges {
  roomId?: string;
  roomName?: string;
  teacherId?: string;
  teacherName?: string;
  startAt?: string;
  endAt?: string;
  startOffsetMinutes?: number;
}

export interface UnrankedScheduleSuggestion {
  kind: ScheduleSuggestionKind;
  score: number;
  changes: ScheduleSuggestionChanges;
  resolves: string[];
}

export interface ScheduleSuggestion extends UnrankedScheduleSuggestion {
  rank: number;
}

export function scheduleConflictFingerprint(
  violation: Pick<ConstraintViolation, "code" | "resource">,
): string {
  return [
    violation.code,
    violation.resource.type,
    violation.resource.id,
  ].join(":");
}

export function groupScheduleConflicts(
  items: ScopedConstraintViolation[],
): ScheduleConflictGroup[] {
  const grouped = new Map<
    string,
    ScheduleConflictGroup & {
      lessonIds: Set<string>;
      rules: Set<string>;
      scopeKeys: Set<string>;
    }
  >();

  for (const item of items) {
    const fingerprint = scheduleConflictFingerprint(item.violation);
    const current = grouped.get(fingerprint) ?? {
      fingerprint,
      code: item.violation.code,
      resource: item.violation.resource,
      occurrences: 0,
      conflictingLessonIds: [],
      ruleIds: [],
      scopes: [],
      lessonIds: new Set<string>(),
      rules: new Set<string>(),
      scopeKeys: new Set<string>(),
    };
    current.occurrences += 1;
    item.violation.conflictingLessonIds.forEach((id) =>
      current.lessonIds.add(id),
    );
    item.violation.ruleIds.forEach((id) => current.rules.add(id));
    if (item.scope) {
      const scopeKey = [
        item.scope.rowIndex ?? "",
        item.scope.studentId ?? "",
        item.scope.localDate ?? "",
      ].join(":");
      if (!current.scopeKeys.has(scopeKey)) {
        current.scopeKeys.add(scopeKey);
        current.scopes.push(item.scope);
      }
    }
    grouped.set(fingerprint, current);
  }

  return [...grouped.values()]
    .sort((left, right) => left.fingerprint.localeCompare(right.fingerprint))
    .map(({ lessonIds, rules, scopeKeys: _scopeKeys, ...group }) => ({
      ...group,
      conflictingLessonIds: [...lessonIds].sort(),
      ruleIds: [...rules].sort(),
      scopes: [...group.scopes].sort(compareScopes),
    }));
}

export function rankScheduleSuggestions(
  suggestions: UnrankedScheduleSuggestion[],
  limit = 8,
): ScheduleSuggestion[] {
  const unique = new Map<string, UnrankedScheduleSuggestion>();
  for (const suggestion of suggestions) {
    const key = JSON.stringify({
      kind: suggestion.kind,
      changes: suggestion.changes,
    });
    const current = unique.get(key);
    if (!current || current.score < suggestion.score) unique.set(key, suggestion);
  }
  return [...unique.values()]
    .sort(
      (left, right) =>
        right.score - left.score ||
        left.kind.localeCompare(right.kind) ||
        JSON.stringify(left.changes).localeCompare(JSON.stringify(right.changes)),
    )
    .slice(0, limit)
    .map((suggestion, index) => ({ ...suggestion, rank: index + 1 }));
}

function compareScopes(left: ScheduleConflictScope, right: ScheduleConflictScope) {
  return (
    (left.rowIndex ?? -1) - (right.rowIndex ?? -1) ||
    (left.localDate ?? "").localeCompare(right.localDate ?? "") ||
    (left.studentId ?? "").localeCompare(right.studentId ?? "")
  );
}
