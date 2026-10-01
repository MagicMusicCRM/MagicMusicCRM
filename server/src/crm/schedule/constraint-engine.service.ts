import { Injectable } from "@nestjs/common";
import {
  evaluateReferenceConstraints,
  halfOpenIntervalsOverlap,
  parseConstraintInterval,
  sortConstraintViolations,
  violation,
} from "./constraint-engine.rules";
import { ConstraintEngineRepository } from "./constraint-engine.repository";
import {
  ConstraintValidationResult,
  ConstraintViolation,
  LessonConstraintDraft,
  LessonConflict,
  ConstraintTransaction,
  ResolvedConstraintReference,
} from "./constraint-engine.types";
import {
  groupScheduleConflicts,
  rankScheduleSuggestions,
  ScheduleConflictGroup,
  ScheduleSuggestion,
  ScheduleSuggestionKind,
  UnrankedScheduleSuggestion,
} from "./schedule-analyzer";

export interface ScheduleAnalysisResult extends ConstraintValidationResult {
  conflicts: ScheduleConflictGroup[];
  suggestions: ScheduleSuggestion[];
}

interface PreparedConstraintValidation {
  transaction: ConstraintTransaction;
  branchId: string;
  teacherId: string;
  roomId: string;
  startAt: Date;
  endAt: Date;
  reference: ResolvedConstraintReference;
  roomMatchesBranch: boolean;
  conflicts: Map<string, Promise<LessonConflict[]>>;
}

@Injectable()
export class ScheduleConstraintEngine {
  constructor(private readonly repository: ConstraintEngineRepository) {}

  async prepareValidation(draft: LessonConstraintDraft, transaction: ConstraintTransaction): Promise<PreparedConstraintValidation | undefined> {
    const interval = parseConstraintInterval(draft.startAt, draft.endAt);
    if (!interval) return undefined;
    const reference = await this.repository.resolveReference(draft, interval.startAt, interval.endAt, transaction);
    // A partial assignment needs the original per-occurrence lookup.
    if (!reference?.teacherBranchAssigned) return undefined;
    const roomMatchesBranch = await this.repository.roomMatchesBranch(draft.roomId, draft.branchId, transaction);
    return {transaction, branchId:draft.branchId,teacherId:draft.teacherId,roomId:draft.roomId,...interval,reference,roomMatchesBranch,conflicts: new Map()};
  }

  async validate(
    draft: LessonConstraintDraft,
    transaction?: ConstraintTransaction,
    prepared?: PreparedConstraintValidation,
  ): Promise<ConstraintValidationResult> {
    const interval = parseConstraintInterval(draft.startAt, draft.endAt);
    if (!interval) {
      return {
        valid: false,
        violations: [
          violation("INVALID_INTERVAL", {
            type: "interval",
            id: "lesson",
          }),
        ],
      };
    }

    const reusable = prepared && prepared.transaction === transaction &&
      prepared.branchId === draft.branchId && prepared.teacherId === draft.teacherId &&
      prepared.roomId === draft.roomId && interval.startAt >= prepared.startAt && interval.endAt <= prepared.endAt;
    const loadReference = () => reusable ? Promise.resolve({...prepared.reference,
      teacherRules: prepared.reference.teacherRules.filter(rule => {
        const bounds = parseConstraintInterval(rule.startsAt, rule.endsAt ?? new Date(8_640_000_000_000_000));
        return bounds !== null && halfOpenIntervalsOverlap(bounds, interval);
      }),
    }) :
      this.repository.resolveReference(
        draft,
        interval.startAt,
        interval.endAt,
        transaction,
      );
    const loadRoomMatch = () => reusable ? Promise.resolve(prepared.roomMatchesBranch) :
      this.repository.roomMatchesBranch(
        draft.roomId,
        draft.branchId,
        transaction,
      );
    const loadConflicts = async () => {
      if (!reusable) return this.repository.findConflicts(draft, interval.startAt, interval.endAt, transaction);
      const key = JSON.stringify([draft.clientRef, draft.excludeLessonId, draft.excludeScheduleSeriesIds]);
      let pending = prepared.conflicts.get(key);
      if (!pending) {
        pending = this.repository.findConflicts(draft, prepared.startAt, prepared.endAt, transaction);
        prepared.conflicts.set(key, pending);
      }
      return (await pending).filter(conflict => {
        const bounds = conflict.startsAt && conflict.endsAt ? parseConstraintInterval(conflict.startsAt, conflict.endsAt) : null;
        return bounds !== null && halfOpenIntervalsOverlap(bounds, interval);
      });
    };
    // A pg PoolClient may execute only one query at a time. Keep read-only
    // previews parallel on the pool, but serialize checks inside commit paths.
    const [reference, roomMatchesBranch, conflicts] = transaction
      ? [await loadReference(), await loadRoomMatch(), await loadConflicts()]
      : await Promise.all([loadReference(), loadRoomMatch(), loadConflicts()]);
    const violations = [
      ...evaluateReferenceConstraints(interval, reference, {
        branchId: draft.branchId,
        teacherId: draft.teacherId,
      }),
      ...(!roomMatchesBranch
        ? [
            violation("ROOM_BRANCH_MISMATCH", {
              type: "room",
              id: draft.roomId,
            }),
          ]
        : []),
      ...this.groupConflicts(conflicts),
    ];
    const sorted = sortConstraintViolations(violations);
    return { valid: sorted.length === 0, violations: sorted };
  }

  async analyze(
    draft: LessonConstraintDraft,
    transaction?: ConstraintTransaction,
  ): Promise<ScheduleAnalysisResult> {
    const validation = await this.validate(draft, transaction);
    const conflicts = groupScheduleConflicts(
      validation.violations.map((violation) => ({ violation })),
    );
    return {
      ...validation,
      conflicts,
      suggestions: validation.valid
        ? []
        : await this.suggest(draft, conflicts, transaction),
    };
  }

  private async suggest(
    draft: LessonConstraintDraft,
    conflicts: ScheduleConflictGroup[],
    transaction?: ConstraintTransaction,
  ): Promise<ScheduleSuggestion[]> {
    const interval = parseConstraintInterval(draft.startAt, draft.endAt);
    if (!interval) return [];
    const [rooms, teachers] = transaction
      ? [
          await this.repository.listAlternativeRooms(
            draft.branchId,
            draft.roomId,
            transaction,
          ),
          await this.repository.listAlternativeTeachers(
            draft.teacherId,
            draft.branchId,
            interval.startAt,
            transaction,
          ),
        ]
      : await Promise.all([
          this.repository.listAlternativeRooms(draft.branchId, draft.roomId),
          this.repository.listAlternativeTeachers(
            draft.teacherId,
            draft.branchId,
            interval.startAt,
          ),
        ]);
    const resolves = conflicts.map((conflict) => conflict.fingerprint);
    const suggestions: UnrankedScheduleSuggestion[] = [];
    const tryCandidate = async (
      kind: ScheduleSuggestionKind,
      score: number,
      changes: UnrankedScheduleSuggestion["changes"],
    ) => {
      const startAt = changes.startAt ?? interval.startAt.toISOString();
      const endAt = changes.endAt ?? interval.endAt.toISOString();
      const result = await this.validate(
        {
          ...draft,
          teacherId: changes.teacherId ?? draft.teacherId,
          roomId: changes.roomId ?? draft.roomId,
          startAt,
          endAt,
        },
        transaction,
      );
      if (result.valid) suggestions.push({ kind, score, changes, resolves });
    };

    for (const room of rooms.slice(0, 3)) {
      await tryCandidate("SAME_TIME_ROOM", 1_000, {
        roomId: room.id,
        roomName: room.name,
      });
    }

    const offsets = [
      15,
      -15,
      30,
      -30,
      45,
      -45,
      60,
      -60,
      90,
      -90,
      120,
      -120,
      180,
      -180,
      240,
      -240,
      1_440,
      -1_440,
      2_880,
      -2_880,
      10_080,
      -10_080,
    ];
    for (const offset of offsets) {
      const startAt = new Date(interval.startAt.getTime() + offset * 60_000);
      const endAt = new Date(interval.endAt.getTime() + offset * 60_000);
      await tryCandidate("NEAREST_TIME", 950 - Math.abs(offset), {
        startAt: startAt.toISOString(),
        endAt: endAt.toISOString(),
        startOffsetMinutes: offset,
      });
      if (suggestions.filter((item) => item.kind === "NEAREST_TIME").length >= 3) {
        break;
      }
    }

    for (const teacher of teachers.slice(0, 3)) {
      await tryCandidate(
        "SAME_SPECIALIZATION_TEACHER",
        900 + Math.min(teacher.sharedDisciplineCount, 5),
        { teacherId: teacher.id, teacherName: teacher.name },
      );
    }

    for (const teacher of teachers.slice(0, 2)) {
      for (const room of rooms.slice(0, 2)) {
        await tryCandidate("COMBINED", 800, {
          teacherId: teacher.id,
          teacherName: teacher.name,
          roomId: room.id,
          roomName: room.name,
        });
      }
    }

    if (rooms[0]) {
      for (const offset of offsets.slice(0, 4)) {
        const startAt = new Date(interval.startAt.getTime() + offset * 60_000);
        const endAt = new Date(interval.endAt.getTime() + offset * 60_000);
        await tryCandidate("COMBINED", 780 - Math.abs(offset), {
          roomId: rooms[0].id,
          roomName: rooms[0].name,
          startAt: startAt.toISOString(),
          endAt: endAt.toISOString(),
          startOffsetMinutes: offset,
        });
      }
    }

    return rankScheduleSuggestions(suggestions);
  }

  private groupConflicts(conflicts: LessonConflict[]): ConstraintViolation[] {
    const grouped = new Map<string, ConstraintViolation>();
    for (const conflict of conflicts) {
      const key = [
        conflict.code,
        conflict.resource.type,
        conflict.resource.id,
      ].join(":");
      const current = grouped.get(key);
      if (current) {
        current.conflictingLessonIds.push(conflict.lessonId);
      } else {
        grouped.set(
          key,
          violation(
            conflict.code,
            conflict.resource,
            [],
            [conflict.lessonId],
          ),
        );
      }
    }
    return [...grouped.values()];
  }
}
