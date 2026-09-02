import {
  Injectable,
  Logger,
  UnprocessableEntityException,
} from "@nestjs/common";
import { PoolClient } from "pg";
import { DatabaseService } from "../../db/database.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { LessonSettlementResult } from "./lesson-settlement.port";

interface LockedSubscriptionRow {
  id: string;
  student_id: string;
  status: string;
  lessons_total: string;
  lessons_used: string;
  starts_at: Date | string | null;
  expires_at: Date | string | null;
}

interface ReservationRow {
  id: string;
  subscription_id: string;
  state: "reserved" | "consumed" | "released" | "cancelled";
  version: number | string;
  units: string;
}

export interface LessonSettlementCoverageSnapshot {
  reservations: Array<{
    id: string;
    subscriptionId: string;
    state: ReservationRow["state"];
    version: number;
    units: string;
  }>;
  subscriptions: Array<{
    id: string;
    version: number;
    status: string;
    lessonsTotal: string;
    lessonsUsed: string;
    settledUnits: string;
    reservedUnits: string;
    expiresAt: string | null;
  }>;
}

@Injectable()
export class SubscriptionReservationService {
  private readonly logger = new Logger(SubscriptionReservationService.name);

  constructor(
    private readonly database: DatabaseService,
    private readonly realtime: RealtimeBus,
  ) {}

  async allocate(
    client: PoolClient,
    input: {
      lessonId: string;
      clientType: "lead" | "student";
      clientId: string;
      payerStudentId?: string;
      chargeType: "subscription" | "personal_account" | "none";
      subscriptionId: string | null;
      units: number;
      allowUncovered?: boolean;
    },
  ): Promise<void> {
    if (input.chargeType !== "subscription") return;
    if (
      input.clientType !== "student" ||
      !input.subscriptionId ||
      !Number.isFinite(input.units) ||
      input.units <= 0
    ) {
      this.capacityViolation(input.subscriptionId, input.units, "0");
    }

    const subscription = await this.lockSubscription(
      client,
      input.subscriptionId,
    );
    if (
      !subscription ||
      subscription.student_id !== (input.payerStudentId ?? input.clientId)
    ) {
      this.capacityViolation(input.subscriptionId, input.units, "0");
    }
    if (
      subscription.status !== "active" ||
      !(await this.coversLesson(
        client,
        input.subscriptionId,
        input.lessonId,
        input.clientId,
      ))
    ) {
      if (input.allowUncovered) return;
      this.capacityViolation(input.subscriptionId, input.units, "0");
    }

    const capacity = await client.query<{
      used_units: string;
      reserved_units: string;
    }>(
      `
        select
          (
            $2::numeric + coalesce(
              (
                select sum(fact.units)
                from app.lesson_client_charge_facts_effective fact
                where fact.subscription_id = $1
                  and fact.charge_type = 'subscription'
              ),
              0
            )
          )::text as used_units,
          coalesce(
            (
              select sum(reservation.units)
              from app.lesson_reservations reservation
              where reservation.subscription_id = $1
                and reservation.state = 'reserved'
            ),
            0
          )::text as reserved_units
      `,
      [input.subscriptionId, subscription.lessons_used],
    );
    const used = Number(capacity.rows[0]?.used_units ?? 0);
    const reserved = Number(capacity.rows[0]?.reserved_units ?? 0);
    const available = Number(subscription.lessons_total) - used - reserved;
    if (available + Number.EPSILON < input.units) {
      if (input.allowUncovered) return;
      this.capacityViolation(
        input.subscriptionId,
        input.units,
        Math.max(0, available).toFixed(2),
      );
    }

    const reservationWrite = await client.query(
      `
        insert into app.lesson_reservations (
          lesson_id,
          subscription_id,
          units
        )
        values ($1, $2, $3)
        on conflict (lesson_id, subscription_id) do update
          set units = excluded.units,
              state = 'reserved',
              financial_fact_id = null,
              terminal_at = null,
              version = app.lesson_reservations.version + 1,
              updated_at = now()
          where app.lesson_reservations.state = 'released'
        returning id
      `,
      [input.lessonId, input.subscriptionId, input.units],
    );
    if (!reservationWrite.rows[0]) {
      this.capacityViolation(input.subscriptionId, input.units, "0");
    }
  }

  async lockSettlementCoverage(
    client: PoolClient,
    lessonId: string,
    selectedSubscriptionIds: string[] = [],
  ): Promise<LessonSettlementCoverageSnapshot> {
    const candidates = await client.query<{ subscription_id: string }>(
      `
        select distinct source.subscription_id
        from (
          select subscription_id from app.lesson_snapshots where lesson_id = $1
          union all
          select subscription_id from app.lesson_snapshot_participants where lesson_id = $1
          union all
          select subscription_id from app.lesson_reservations where lesson_id = $1
          union all
          select unnest($2::uuid[])
        ) source
        where source.subscription_id is not null
        order by source.subscription_id
      `,
      [lessonId, [...new Set(selectedSubscriptionIds)].sort()],
    );
    for (const candidate of candidates.rows) {
      await this.lockSubscription(client, candidate.subscription_id);
    }

    const reservations = await client.query<ReservationRow>(
      `
        select id, subscription_id, state, version, units::text
        from app.lesson_reservations
        where lesson_id = $1
        order by subscription_id, created_at, id
        for update
      `,
      [lessonId],
    );
    const subscriptionIds = candidates.rows.map((row) => row.subscription_id);
    const subscriptions = await client.query<{
      id: string;
      version: number | string;
      status: string;
      lessons_total: string;
      lessons_used: string;
      settled_units: string;
      reserved_units: string;
      expires_at: Date | string | null;
    }>(
      `
        select subscription.id, subscription.version, subscription.status,
          subscription.lessons_total::text, subscription.lessons_used::text,
          coalesce((
            select sum(fact.units)
            from app.lesson_client_charge_facts_effective fact
            where fact.subscription_id = subscription.id
              and fact.charge_type = 'subscription'
          ), 0)::text as settled_units,
          coalesce((
            select sum(reservation.units)
            from app.lesson_reservations reservation
            where reservation.subscription_id = subscription.id
              and reservation.state = 'reserved'
          ), 0)::text as reserved_units,
          subscription.expires_at
        from app.subscriptions subscription
        where subscription.id = any($1::uuid[])
        order by subscription.id
      `,
      [subscriptionIds],
    );
    return {
      reservations: reservations.rows.map((row) => ({
        id: row.id,
        subscriptionId: row.subscription_id,
        state: row.state,
        version: Number(row.version),
        units: row.units,
      })),
      subscriptions: subscriptions.rows.map((row) => ({
        id: row.id,
        version: Number(row.version),
        status: row.status,
        lessonsTotal: row.lessons_total,
        lessonsUsed: row.lessons_used,
        settledUnits: row.settled_units,
        reservedUnits: row.reserved_units,
        expiresAt: row.expires_at === null
          ? null
          : new Date(row.expires_at).toISOString().slice(0, 10),
      })),
    };
  }

  async terminalize(
    client: PoolClient,
    settled: LessonSettlementResult,
  ): Promise<void> {
    let consumed = 0;
    for (const fact of settled.clientFacts) {
      if (
        fact.chargeType !== "subscription" ||
        !fact.subscriptionId ||
        Number(fact.units) <= 0
      ) continue;
      const result = await client.query(
        `
          update app.lesson_reservations
          set state = 'consumed', financial_fact_id = $3::uuid
          where lesson_id = $1 and subscription_id = $2 and state = 'reserved'
        `,
        [settled.lessonId, fact.subscriptionId, fact.id],
      );
      consumed += result.rowCount ?? 0;
    }
    await client.query(
      `
        update app.lesson_reservations
        set state = 'released', financial_fact_id = null
        where lesson_id = $1 and state = 'reserved'
      `,
      [settled.lessonId],
    );
    const expected = settled.clientFacts.filter(
      (fact) => fact.chargeType === "subscription" && Number(fact.units) > 0,
    ).length;
    if (consumed !== expected) {
      throw new UnprocessableEntityException({
        code: "SUBSCRIPTION_RESERVATION_LOST",
        lessonId: settled.lessonId,
      });
    }
  }

  async releaseForLessons(
    client: PoolClient,
    lessonIds: string[],
  ): Promise<number> {
    if (lessonIds.length === 0) return 0;
    const result = await client.query(
      `update app.lesson_reservations
       set state = 'released', financial_fact_id = null
       where lesson_id = any($1::uuid[]) and state = 'reserved'`,
      [lessonIds],
    );
    return result.rowCount ?? 0;
  }

  async publishPostCommit(input: {
    studentId: string;
    payerStudentId?: string;
    subscriptionId?: string | null;
    lessonId?: string;
  }): Promise<void> {
    try {
      const userIds = Array.from(
        new Set(
          (
            await Promise.all(
              [...new Set([input.studentId, input.payerStudentId])]
                .filter((id): id is string => Boolean(id))
                .map((id) => this.clientUserIds(id)),
            )
          ).flat(),
        ),
      );
      this.realtime.emitCrmChanged({
        entity: "lesson",
        action: "updated",
        id: input.lessonId ?? null,
        affectedUserIds: userIds,
      });
      if (input.subscriptionId) {
        this.realtime.emitCrmChanged({
          entity: "subscription",
          action: "updated",
          id: input.subscriptionId,
          affectedUserIds: userIds,
        });
      }
      this.realtime.emitFinanceChanged(userIds);
    } catch (error) {
      this.logger.warn(
        `Post-commit subscription invalidation failed: ${String(error)}`,
      );
    }
  }

  async publishLessonSettlementPostCommit(lessonId: string): Promise<void> {
    try {
      const result = await this.database.query<{
        student_id: string;
        subscription_id: string | null;
      }>(
        `
          select distinct
            target.student_id,
            fact.subscription_id
          from app.lesson_client_charge_facts_effective fact
          left join app.subscriptions subscription
            on subscription.id = fact.subscription_id
          cross join lateral (
            values (fact.client_id), (subscription.student_id)
          ) as target(student_id)
          where fact.lesson_id = $1
            and fact.client_type = 'student'
            and target.student_id is not null
        `,
        [lessonId],
      );
      const userIdsByStudent = new Map(
        await Promise.all(
          Array.from(new Set(result.rows.map((row) => row.student_id))).map(
            async (studentId) => [
              studentId,
              await this.clientUserIds(studentId),
            ] as const,
          ),
        ),
      );
      const affectedUserIds = (
        rows: Array<{ student_id: string }>,
      ): string[] => Array.from(
        new Set(
          rows.flatMap((row) => userIdsByStudent.get(row.student_id) ?? []),
        ),
      );
      const userIds = affectedUserIds(result.rows);
      this.realtime.emitCrmChanged({
        entity: "lesson",
        action: "updated",
        id: lessonId,
        affectedUserIds: userIds,
      });
      for (const subscriptionId of new Set(
        result.rows.map((row) => row.subscription_id).filter(Boolean),
      )) {
        const subscriptionUserIds = affectedUserIds(
          result.rows.filter((row) => row.subscription_id === subscriptionId),
        );
        this.realtime.emitCrmChanged({
          entity: "subscription",
          action: "updated",
          id: subscriptionId,
          affectedUserIds: subscriptionUserIds,
        });
      }
      this.realtime.emitFinanceChanged(userIds);
    } catch (error) {
      this.logger.warn(
        `Post-commit Lesson invalidation failed: ${String(error)}`,
      );
    }
  }

  private async lockSubscription(
    client: PoolClient,
    subscriptionId: string,
  ): Promise<LockedSubscriptionRow | null> {
    const result = await client.query<LockedSubscriptionRow>(
      `
        select
          id,
          student_id,
          status,
          lessons_total,
          lessons_used,
          starts_at,
          expires_at
        from app.subscriptions
        where id = $1
        for update
      `,
      [subscriptionId],
    );
    return result.rows[0] ?? null;
  }

  private async coversLesson(
    client: PoolClient,
    subscriptionId: string,
    lessonId: string,
    recipientStudentId: string,
  ): Promise<boolean> {
    const result = await client.query<{ covered: boolean }>(
      `select exists (
         select 1
         from app.subscriptions subscription
         join app.lessons lesson on lesson.id = $2
         join app.students owner
           on owner.id = subscription.student_id
          and owner.deleted_at is null
         join app.students recipient
           on recipient.id = $3
          and recipient.deleted_at is null
         left join app.schedule_series series on series.id = lesson.series_id
         left join app.branches branch on branch.id = lesson.branch_id
         left join app.subscription_packages package
           on package.id = subscription.package_id
         where subscription.id = $1
           and owner.branch_id = lesson.branch_id
           and recipient.branch_id = lesson.branch_id
           and (package.branch_id is null or package.branch_id = lesson.branch_id)
           and (subscription.starts_at is null or subscription.starts_at <=
             timezone(coalesce(series.timezone_name, branch.timezone_name, 'Europe/Moscow'),
               lesson.scheduled_at)::date)
           and (subscription.expires_at is null or subscription.expires_at >=
             timezone(coalesce(series.timezone_name, branch.timezone_name, 'Europe/Moscow'),
               lesson.scheduled_at)::date)
       ) as covered`,
      [subscriptionId, lessonId, recipientStudentId],
    );
    return result.rows[0]?.covered === true;
  }

  private async clientUserIds(studentId: string): Promise<string[]> {
    const result = await this.database.query<{ user_id: string | null }>(
      `
        select profile.user_id
        from app.students student
        join app.profiles profile
          on profile.id = student.profile_id
         and profile.deleted_at is null
        where student.id = $1
          and student.deleted_at is null
          and profile.user_id is not null
      `,
      [studentId],
    );
    return Array.from(
      new Set(
        result.rows
          .map((row) => row.user_id)
          .filter((value): value is string => Boolean(value)),
      ),
    );
  }

  private capacityViolation(
    subscriptionId: string | null,
    requestedUnits: number,
    availableUnits: string,
  ): never {
    throw new UnprocessableEntityException({
      code: "LESSON_CONSTRAINT_VIOLATIONS",
      message: "Lesson draft violates subscription capacity.",
      violations: [
        {
          code: "SUBSCRIPTION_CAPACITY",
          resourceType: "subscription",
          resourceId: subscriptionId,
          requestedUnits: String(requestedUnits),
          availableUnits,
        },
      ],
    });
  }
}
