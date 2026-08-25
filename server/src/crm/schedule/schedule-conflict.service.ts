import {
  BadRequestException,
  ConflictException,
  Injectable,
} from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { CrmPolicy } from "../crm.policy";
import { ScheduleConflictsQuery } from "../dto/schedule-conflicts.query";
import {
  acquireScheduleResourceLocks,
  ScheduleQueryExecutor,
} from "./schedule-locks";

interface ConflictRow {
  lesson_id: string;
  title: string;
  starts_at: Date | string;
  ends_at: Date | string;
  room_name: string | null;
  teacher_name: string | null;
  teacher_hit: boolean;
  room_hit: boolean;
}

export interface ScheduleConflictParams {
  teacherId: string | null;
  roomId: string | null;
  startsAt: string | Date;
  durationMinutes: number;
  excludeLessonId?: string | null;
  groupId?: string | null;
}

@Injectable()
export class ScheduleConflictService {
  constructor(
    private readonly database: DatabaseService,
    private readonly policy: CrmPolicy,
  ) {}

  async getScheduleConflicts(
    actor: ActorContext,
    query: ScheduleConflictsQuery,
  ) {
    this.policy.assertManagerOnly(actor);
    const startsAt = new Date(query.startsAt);
    const endsAt = new Date(query.endsAt);
    if (
      Number.isNaN(startsAt.getTime()) ||
      Number.isNaN(endsAt.getTime()) ||
      startsAt.getTime() >= endsAt.getTime()
    ) {
      throw new BadRequestException(
        "Время окончания должно быть позже времени начала.",
      );
    }
    const rows = await this.queryConflicts({
      teacherId: query.teacherId ?? null,
      roomId: query.roomId ?? null,
      startsAt: startsAt.toISOString(),
      endsAt: endsAt.toISOString(),
      excludeLessonId: query.excludeLessonId ?? null,
      groupId: null,
    });
    return {
      teacherBusy: rows.some((row) => row.teacher_hit),
      roomBusy: rows.some((row) => row.room_hit),
      conflicts: rows.map((row) => this.toConflictDto(row)),
    };
  }

  async assertNoScheduleConflicts(
    params: ScheduleConflictParams,
    executor: ScheduleQueryExecutor,
  ): Promise<void> {
    await acquireScheduleResourceLocks(
      executor,
      params.teacherId,
      params.roomId,
    );
    if (!params.teacherId && !params.roomId) return;
    const startsAt = new Date(params.startsAt);
    if (Number.isNaN(startsAt.getTime())) return;
    const endsAt = new Date(
      startsAt.getTime() + params.durationMinutes * 60_000,
    );
    const rows = await this.queryConflicts(
      {
        teacherId: params.teacherId,
        roomId: params.roomId,
        startsAt: startsAt.toISOString(),
        endsAt: endsAt.toISOString(),
        excludeLessonId: params.excludeLessonId ?? null,
        groupId: params.groupId ?? null,
      },
      executor,
    );
    if (!rows.length) return;
    throw new ConflictException({
      message: "Преподаватель или аудитория заняты в это время.",
      conflicts: rows.map((row) => this.toConflictDto(row)),
    });
  }

  private toConflictDto(row: ConflictRow) {
    return {
      lessonId: row.lesson_id,
      title: row.title,
      startsAt: row.starts_at,
      endsAt: row.ends_at,
      roomName: row.room_name ?? null,
      teacherName: row.teacher_name || null,
    };
  }

  private async queryConflicts(
    params: {
      teacherId: string | null;
      roomId: string | null;
      startsAt: string | Date;
      endsAt: string | Date;
      excludeLessonId: string | null;
      groupId: string | null;
    },
    executor: ScheduleQueryExecutor = this.database,
  ): Promise<ConflictRow[]> {
    if (!params.teacherId && !params.roomId) return [];
    const result = await executor.query<ConflictRow>(
      `
        select l.id as lesson_id,
          l.scheduled_at as starts_at,
          l.scheduled_at + l.duration_minutes * interval '1 minute' as ends_at,
          ($1::uuid is not null and l.teacher_id = $1) as teacher_hit,
          ($2::uuid is not null and l.room_id = $2) as room_hit,
          r.name as room_name,
          trim(coalesce(tp.first_name, '') || ' ' || coalesce(tp.last_name, '')) as teacher_name,
          coalesce(
            nullif(g.name, ''),
            nullif(trim(coalesce(sp.first_name, '') || ' ' || coalesce(sp.last_name, '')), ''),
            nullif(trim(coalesce(ld.first_name, '') || ' ' || coalesce(ld.last_name, '')), ''),
            'Занятие'
          ) as title
        from app.lessons l
        left join app.rooms r on r.id = l.room_id and r.deleted_at is null
        left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        left join app.students s on s.id = l.student_id and s.deleted_at is null
        left join app.profiles sp on sp.id = s.profile_id and sp.deleted_at is null
        left join app.groups g on g.id = l.group_id and g.deleted_at is null
        left join app.leads ld on ld.id = l.lead_id and ld.deleted_at is null
        where l.deleted_at is null
          and l.lifecycle_state in ('scheduled', 'settlement_pending', 'successfully_completed')
          and ($5::uuid is null or l.id <> $5)
          and l.scheduled_at < $4::timestamptz
          and l.scheduled_at > $3::timestamptz - interval '24 hours'
          and tstzrange(l.scheduled_at, l.scheduled_at + l.duration_minutes * interval '1 minute', '[)')
              && tstzrange($3::timestamptz, $4::timestamptz, '[)')
          and (l.group_id is null or $6::uuid is null or l.group_id <> $6)
          and (
            ($1::uuid is not null and l.teacher_id = $1)
            or ($2::uuid is not null and l.room_id = $2)
          )
        order by l.scheduled_at asc, l.id asc
        limit 20
      `,
      [
        params.teacherId,
        params.roomId,
        params.startsAt,
        params.endsAt,
        params.excludeLessonId,
        params.groupId,
      ],
    );
    return result.rows;
  }
}
