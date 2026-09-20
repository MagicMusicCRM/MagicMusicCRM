import { Injectable } from "@nestjs/common";
import type { ActorContext } from "../../common/security/actor-context";
import type {
  SchedulePlanQuery,
  SchedulePlanTrayQuery,
} from "../dto/schedule-plan.dto";
import { failSchedulePlan } from "./schedule-plan-definition.service";
import {
  SchedulePlanRepository,
  type SchedulePlanTrayCursor,
} from "./schedule-plan.repository";
import { buildSchedulePlanTimeline } from "./schedule-plan-timeline";

export interface SchedulePlanTrayProjection {
  planId: string;
  items: Array<{
    id: string;
    scheduledAt: string;
    localDate: string;
    localTime: string;
    state: string;
    settlementMarkers: Array<Record<string, unknown>>;
    relationMarker: "source" | "successor" | "none";
    predecessorId: string | null;
    successorId: string | null;
    teacher: { id: string; name: string | null } | null;
    room: { id: string; name: string | null } | null;
  }>;
  hasPrevious: boolean;
  hasNext: boolean;
  previousCursor: string | null;
  nextCursor: string | null;
}

@Injectable()
export class SchedulePlanQueryService {
  constructor(private readonly repository: SchedulePlanRepository) {}

  async list(
    actor: ActorContext,
    query: SchedulePlanQuery,
  ) {
    const result = await this.repository.list(actor, query);
    const now = new Date();
    return {
      items: result.items.map(({ timelineInput, rowDefinitions, ...plan }) => {
        const timeline = buildSchedulePlanTimeline(timelineInput, now);
        const editableRuleIds = new Set(timeline.editableRuleIds);
        return {
          ...plan,
          rows: rowDefinitions.filter((row) => editableRuleIds.has(row.id)),
          ruleTimeline: timeline.entries,
          exceptions: timeline.exceptions,
        };
      }),
    };
  }

  async tray(
    actor: ActorContext,
    planId: string,
    query: SchedulePlanTrayQuery,
  ): Promise<SchedulePlanTrayProjection> {
    if (query.direction && !query.cursor) {
      failSchedulePlan("SCHEDULE_PLAN_TRAY_CURSOR_REQUIRED", ["cursor"]);
    }
    const limit = Math.max(1, Math.min(query.limit ?? 40, 40));
    return query.cursor
      ? this.cursorPage(actor, planId, query, limit)
      : this.aroundNow(actor, planId, limit);
  }

  private async cursorPage(
    actor: ActorContext,
    planId: string,
    query: SchedulePlanTrayQuery,
    limit: number,
  ) {
    const cursor = this.decodeTrayCursor(query.cursor!);
    const direction = query.direction ?? "next";
    const rows = await this.repository.trayPage(
      actor,
      planId,
      direction,
      cursor,
      limit,
    );
    const hasMore = rows.length > limit;
    const page = rows.slice(0, limit);
    if (direction === "previous") page.reverse();
    return this.trayProjection(
      planId,
      page,
      direction === "previous" ? hasMore : page.length > 0,
      direction === "next" ? hasMore : page.length > 0,
    );
  }

  private async aroundNow(actor: ActorContext, planId: string, limit: number) {
    const anchor: SchedulePlanTrayCursor = {
      scheduledAt: new Date().toISOString(),
      id: "00000000-0000-0000-0000-000000000000",
    };
    const [previousRows, nextRows] = await Promise.all([
      this.repository.trayPage(actor, planId, "previous", anchor, limit),
      this.repository.trayPage(actor, planId, "next", anchor, limit, true),
    ]);
    const previousLimit = Math.min(
      previousRows.length,
      Math.max(Math.floor(limit / 2), limit - nextRows.length),
    );
    const nextLimit = limit - previousLimit;
    const hasPrevious = previousRows.length > previousLimit;
    const hasNext = nextRows.length > nextLimit;
    const page = [
      ...previousRows.slice(0, previousLimit).reverse(),
      ...nextRows.slice(0, nextLimit),
    ];
    return this.trayProjection(planId, page, hasPrevious, hasNext);
  }

  private trayProjection(
    planId: string,
    rows: Awaited<ReturnType<SchedulePlanRepository["trayPage"]>>,
    hasPrevious: boolean,
    hasNext: boolean,
  ): SchedulePlanTrayProjection {
    const items = rows.map((row) => ({
      id: row.id,
      scheduledAt: new Date(row.scheduled_at).toISOString(),
      localDate: row.local_date,
      localTime: row.local_time,
      state: row.lifecycle_state,
      settlementMarkers: row.markers,
      relationMarker: row.successor_id
        ? ("source" as const)
        : row.predecessor_id
          ? ("successor" as const)
          : ("none" as const),
      predecessorId: row.predecessor_id,
      successorId: row.successor_id,
      teacher: row.teacher_id
        ? { id: row.teacher_id, name: row.teacher_name }
        : null,
      room: row.room_id ? { id: row.room_id, name: row.room_name } : null,
    }));
    return {
      planId,
      items,
      hasPrevious,
      hasNext,
      previousCursor:
        hasPrevious && items[0]
          ? this.encodeTrayCursor(items[0].scheduledAt, items[0].id)
          : null,
      nextCursor:
        hasNext && items.at(-1)
          ? this.encodeTrayCursor(items.at(-1)!.scheduledAt, items.at(-1)!.id)
          : null,
    };
  }

  private encodeTrayCursor(scheduledAt: string, id: string) {
    return Buffer.from(JSON.stringify({ scheduledAt, id }), "utf8").toString(
      "base64url",
    );
  }

  private decodeTrayCursor(cursor: string): SchedulePlanTrayCursor {
    try {
      const value = JSON.parse(
        Buffer.from(cursor, "base64url").toString("utf8"),
      ) as Record<string, unknown>;
      if (!this.validCursor(value)) throw new Error("invalid");
      return {
        scheduledAt: value.scheduledAt as string,
        id: value.id as string,
      };
    } catch {
      return failSchedulePlan("SCHEDULE_PLAN_TRAY_CURSOR_INVALID", ["cursor"]);
    }
  }

  private validCursor(value: Record<string, unknown>) {
    return (
      Object.keys(value).length === 2 &&
      typeof value.scheduledAt === "string" &&
      Number.isFinite(new Date(value.scheduledAt).getTime()) &&
      typeof value.id === "string" &&
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
        value.id,
      )
    );
  }
}
