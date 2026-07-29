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
  expires_at: Date | string | null;
}

interface ReservationRow {
  id: string;
  subscription_id: string;
  state: "reserved" | "consumed" | "released" | "cancelled";
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
      chargeType: "subscription" | "personal_account" | "none";
      subscriptionId: string | null;
      units: number;
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
      subscription.status !== "active" ||
      subscription.student_id !== input.clientId ||
      (subscription.expires_at !== null &&
        new Date(subscription.expires_at).getTime() < Date.now())
    ) {
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
                from app.lesson_client_charge_facts fact
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
      this.capacityViolation(
        input.subscriptionId,
        input.units,
        Math.max(0, available).toFixed(2),
      );
    }

    await client.query(
      `
        insert into app.lesson_reservations (
          lesson_id,
          subscription_id,
          units
        )
        values ($1, $2, $3)
      `,
      [input.lessonId, input.subscriptionId, input.units],
    );
  }

  async lockSettlementCoverage(
    client: PoolClient,
    lessonId: string,
  ): Promise<void> {
    const candidate = await client.query<{
      snapshot_subscription_id: string | null;
      reservation_subscription_id: string | null;
    }>(
      `
        select
          snapshot.subscription_id as snapshot_subscription_id,
          reservation.subscription_id as reservation_subscription_id
        from app.lesson_snapshots snapshot
        left join lateral (
          select subscription_id
          from app.lesson_reservations
          where lesson_id = snapshot.lesson_id
            and state = 'reserved'
          order by created_at desc, id desc
          limit 1
        ) reservation on true
        where snapshot.lesson_id = $1
      `,
      [lessonId],
    );
    const firstSubscriptionId =
      candidate.rows[0]?.reservation_subscription_id ??
      candidate.rows[0]?.snapshot_subscription_id ??
      null;
    if (firstSubscriptionId) {
      await this.lockSubscription(client, firstSubscriptionId);
    }

    const reservation = await client.query<ReservationRow>(
      `
        select id, subscription_id, state
        from app.lesson_reservations
        where lesson_id = $1
        order by created_at desc, id desc
        limit 1
        for update
      `,
      [lessonId],
    );
    const currentSubscriptionId =
      reservation.rows[0]?.state === "reserved"
        ? reservation.rows[0].subscription_id
        : null;
    if (
      currentSubscriptionId &&
      currentSubscriptionId !== firstSubscriptionId
    ) {
      await this.lockSubscription(client, currentSubscriptionId);
    }
  }

  async terminalize(
    client: PoolClient,
    settled: LessonSettlementResult,
  ): Promise<void> {
    const result = await client.query(
      `
        update app.lesson_reservations
        set state = case
              when $2 = 'subscription' then 'consumed'
              else 'released'
            end,
            financial_fact_id = case
              when $2 = 'subscription' then $3::uuid
              else null
            end
        where lesson_id = $1 and state = 'reserved'
      `,
      [
        settled.lessonId,
        settled.clientFact.chargeType,
        settled.clientFact.id,
      ],
    );
    if (
      settled.clientFact.chargeType === "subscription" &&
      result.rowCount !== 1
    ) {
      throw new UnprocessableEntityException({
        code: "SUBSCRIPTION_RESERVATION_LOST",
        lessonId: settled.lessonId,
      });
    }
  }

  async publishPostCommit(input: {
    studentId: string;
    subscriptionId: string;
    lessonId?: string;
  }): Promise<void> {
    try {
      const userIds = await this.clientUserIds(input.studentId);
      this.realtime.emitCrmChanged({
        entity: "lesson",
        action: "updated",
        id: input.lessonId ?? null,
        affectedUserIds: userIds,
      });
      this.realtime.emitCrmChanged({
        entity: "subscription",
        action: "updated",
        id: input.subscriptionId,
        affectedUserIds: userIds,
      });
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
        student_id: string | null;
        subscription_id: string | null;
      }>(
        `
          select
            lesson.student_id,
            fact.subscription_id
          from app.lessons lesson
          left join app.lesson_client_charge_facts fact
            on fact.lesson_id = lesson.id
          where lesson.id = $1
        `,
        [lessonId],
      );
      const row = result.rows[0];
      if (!row) return;
      const userIds = row.student_id
        ? await this.clientUserIds(row.student_id)
        : [];
      this.realtime.emitCrmChanged({
        entity: "lesson",
        action: "updated",
        id: lessonId,
        affectedUserIds: userIds,
      });
      if (row.subscription_id) {
        this.realtime.emitCrmChanged({
          entity: "subscription",
          action: "updated",
          id: row.subscription_id,
          affectedUserIds: userIds,
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
          expires_at
        from app.subscriptions
        where id = $1
        for update
      `,
      [subscriptionId],
    );
    return result.rows[0] ?? null;
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
