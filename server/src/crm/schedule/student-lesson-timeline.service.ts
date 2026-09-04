import { Injectable, UnprocessableEntityException } from "@nestjs/common";
import type { ActorContext } from "../../common/security/actor-context";
import type { StudentLessonTimelineQuery } from "../dto/student-lesson-timeline.query";
import {
  StudentLessonTimelineRepository,
  type StudentLessonTimelineCursor,
  type StudentLessonTimelineRow,
} from "./student-lesson-timeline.repository";

export interface StudentLessonTimelineItem {
  id: string;
  version: number;
  scheduledAt: string;
  durationMinutes: number;
  lifecycleState:
    | "scheduled"
    | "settlement_pending"
    | "successfully_completed"
    | "cancelled"
    | "rescheduled";
  student: { id: string; name: string };
  group: { id: string; name: string } | null;
  teacher: { id: string; name: string } | null;
  room: { id: string; name: string } | null;
  branch: { id: string; name: string } | null;
  origin: {
    kind: "manual" | "generated" | "one_off_exception";
    planId: string | null;
    seriesId: string | null;
  };
  settlement: {
    coveredBySubscription: boolean;
    settlementTypeKey: string | null;
  };
  reschedule: {
    predecessorId: string | null;
    successorId: string | null;
    actionableLessonId: string;
  };
}

export interface StudentLessonTimelinePage {
  items: StudentLessonTimelineItem[];
  previousCursor: string | null;
  nextCursor: string | null;
  hasPrevious: boolean;
  hasNext: boolean;
}

@Injectable()
export class StudentLessonTimelineService {
  constructor(private readonly repository: StudentLessonTimelineRepository) {}

  async list(
    actor: ActorContext,
    studentId: string,
    query: StudentLessonTimelineQuery,
  ): Promise<StudentLessonTimelinePage> {
    const limit = Math.max(1, Math.min(query.limit ?? 24, 40));
    if (!query.cursor) return this.aroundNow(actor, studentId, limit);

    const cursor = this.decodeCursor(query.cursor);
    const direction = query.direction ?? "next";
    const rows = await this.repository.listPage(
      actor,
      studentId,
      direction,
      cursor,
      limit,
    );
    const hasMore = rows.length > limit;
    const page = rows.slice(0, limit);
    if (direction === "previous") page.reverse();
    return this.projectPage(
      page,
      direction === "previous" ? hasMore : page.length > 0,
      direction === "next" ? hasMore : page.length > 0,
    );
  }

  private async aroundNow(
    actor: ActorContext,
    studentId: string,
    limit: number,
  ): Promise<StudentLessonTimelinePage> {
    const anchor: StudentLessonTimelineCursor = {
      scheduledAt: new Date().toISOString(),
      id: "00000000-0000-0000-0000-000000000000",
    };
    const [previousRows, nextRows] = await Promise.all([
      this.repository.listPage(
        actor,
        studentId,
        "previous",
        anchor,
        limit,
      ),
      this.repository.listPage(
        actor,
        studentId,
        "next",
        anchor,
        limit,
        true,
      ),
    ]);
    const previousLimit = Math.min(
      previousRows.length,
      Math.max(Math.floor(limit / 2), limit - nextRows.length),
    );
    const nextLimit = limit - previousLimit;
    return this.projectPage(
      [
        ...previousRows.slice(0, previousLimit).reverse(),
        ...nextRows.slice(0, nextLimit),
      ],
      previousRows.length > previousLimit,
      nextRows.length > nextLimit,
    );
  }

  private projectPage(
    rows: StudentLessonTimelineRow[],
    hasPrevious: boolean,
    hasNext: boolean,
  ): StudentLessonTimelinePage {
    const items = rows.map((row) => this.projectItem(row));
    return {
      items,
      hasPrevious,
      hasNext,
      previousCursor:
        hasPrevious && items[0]
          ? this.encodeCursor(items[0].scheduledAt, items[0].id)
          : null,
      nextCursor:
        hasNext && items.at(-1)
          ? this.encodeCursor(items.at(-1)!.scheduledAt, items.at(-1)!.id)
          : null,
    };
  }

  private projectItem(row: StudentLessonTimelineRow): StudentLessonTimelineItem {
    return {
      id: row.id,
      version: Number(row.version),
      scheduledAt: new Date(row.scheduled_at).toISOString(),
      durationMinutes: row.duration_minutes,
      lifecycleState: row.lifecycle_state,
      student: { id: row.student_id, name: row.student_name ?? "" },
      group: row.group_id
        ? { id: row.group_id, name: row.group_name ?? "" }
        : null,
      teacher: row.teacher_id
        ? { id: row.teacher_id, name: row.teacher_name ?? "" }
        : null,
      room: row.room_id ? { id: row.room_id, name: row.room_name ?? "" } : null,
      branch: row.branch_id
        ? { id: row.branch_id, name: row.branch_name ?? "" }
        : null,
      origin: {
        kind: row.origin_kind,
        planId: row.plan_id,
        seriesId: row.series_id,
      },
      settlement: {
        coveredBySubscription: row.covered_by_subscription,
        settlementTypeKey: row.settlement_type_key,
      },
      reschedule: {
        predecessorId: row.predecessor_id,
        successorId: row.successor_id,
        actionableLessonId: row.actionable_lesson_id || row.id,
      },
    };
  }

  private encodeCursor(scheduledAt: string, id: string): string {
    return Buffer.from(JSON.stringify({ scheduledAt, id }), "utf8").toString(
      "base64url",
    );
  }

  private decodeCursor(cursor: string): StudentLessonTimelineCursor {
    try {
      const bytes = Buffer.from(cursor, "base64url");
      if (bytes.toString("base64url") !== cursor) throw new Error("invalid");
      const value: unknown = JSON.parse(bytes.toString("utf8"));
      if (!this.validCursor(value)) throw new Error("invalid");
      return { scheduledAt: value.scheduledAt, id: value.id };
    } catch {
      throw new UnprocessableEntityException({
        code: "STUDENT_TIMELINE_CURSOR_INVALID",
        fields: ["cursor"],
      });
    }
  }

  private validCursor(
    value: unknown,
  ): value is { scheduledAt: string; id: string } {
    if (value === null || typeof value !== "object" || Array.isArray(value)) {
      return false;
    }
    const cursor = value as Record<string, unknown>;
    if (typeof cursor.scheduledAt !== "string") return false;
    const scheduledAt = new Date(cursor.scheduledAt);
    return (
      Object.keys(cursor).length === 2 &&
      Number.isFinite(scheduledAt.getTime()) &&
      scheduledAt.toISOString() === cursor.scheduledAt &&
      typeof cursor.id === "string" &&
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
        cursor.id,
      )
    );
  }
}
