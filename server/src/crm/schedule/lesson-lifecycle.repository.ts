import { Injectable } from "@nestjs/common";
import { PoolClient } from "pg";
import { DatabaseService } from "../../db/database.service";

export type LessonLifecycleState =
  | "scheduled"
  | "successfully_completed"
  | "cancelled"
  | "rescheduled";

export interface LessonSnapshotInput {
  lessonId: string;
  clientType: "lead" | "student";
  clientId: string;
  completionType: string;
  clientChargeType: "subscription" | "personal_account" | "none";
  clientChargeValue: number;
  teacherCompensationType: "fixed" | "hourly" | "none";
  teacherCompensationValue: number;
  subscriptionId?: string;
  trial: boolean;
}

export interface LessonTransitionInput {
  lessonId: string;
  toState: Exclude<LessonLifecycleState, "scheduled">;
  reasonCode: string;
  reasonText?: string;
  actorUserId?: string;
  workerId?: string;
  predecessorId?: string;
  successorId?: string;
  financialDecision?: Record<string, unknown>;
  clientFinancialFactId?: string;
  teacherFinancialFactId?: string;
}

@Injectable()
export class LessonLifecycleRepository {
  constructor(private readonly database: DatabaseService) {}

  get(lessonId: string) {
    return this.database.query(
      `
        select
          lesson.id,
          lesson.lifecycle_state,
          lesson.version,
          lesson.predecessor_id,
          lesson.successor_id,
          row_to_json(snapshot.*) as snapshot,
          coalesce(
            (
              select jsonb_agg(to_jsonb(transition.*)
                order by transition.created_at, transition.id)
              from app.lesson_transitions transition
              where transition.lesson_id = lesson.id
            ),
            '[]'::jsonb
          ) as transitions,
          (
            select row_to_json(reservation.*)
            from app.lesson_reservations reservation
            where reservation.lesson_id = lesson.id
              and reservation.state = 'reserved'
            limit 1
          ) as active_reservation
        from app.lessons lesson
        left join app.lesson_snapshots snapshot
          on snapshot.lesson_id = lesson.id
        where lesson.id = $1
      `,
      [lessonId],
    );
  }

  createSnapshot(client: PoolClient, input: LessonSnapshotInput) {
    return client.query(
      `
        insert into app.lesson_snapshots (
          lesson_id,
          client_type,
          client_id,
          completion_type,
          client_charge_type,
          client_charge_value,
          teacher_compensation_type,
          teacher_compensation_value,
          subscription_id,
          trial,
          duration_minutes
        )
        values (
          $1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
          (select duration_minutes from app.lessons where id = $1)
        )
        returning *
      `,
      [
        input.lessonId,
        input.clientType,
        input.clientId,
        input.completionType,
        input.clientChargeType,
        input.clientChargeValue,
        input.teacherCompensationType,
        input.teacherCompensationValue,
        input.subscriptionId ?? null,
        input.trial,
      ],
    );
  }

  appendTransition(client: PoolClient, input: LessonTransitionInput) {
    return client.query(
      `
        insert into app.lesson_transitions (
          lesson_id,
          from_state,
          to_state,
          reason_code,
          reason_text,
          actor_user_id,
          worker_id,
          predecessor_id,
          successor_id,
          financial_decision,
          client_financial_fact_id,
          teacher_financial_fact_id
        )
        values (
          $1, 'scheduled', $2, $3, $4, $5, $6, $7, $8, $9::jsonb, $10, $11
        )
        returning *
      `,
      [
        input.lessonId,
        input.toState,
        input.reasonCode,
        input.reasonText ?? null,
        input.actorUserId ?? null,
        input.workerId ?? null,
        input.predecessorId ?? null,
        input.successorId ?? null,
        JSON.stringify(input.financialDecision ?? {}),
        input.clientFinancialFactId ?? null,
        input.teacherFinancialFactId ?? null,
      ],
    );
  }

  createReservation(
    client: PoolClient,
    input: {
      lessonId: string;
      subscriptionId: string;
      units: number;
    },
  ) {
    return client.query(
      `
        insert into app.lesson_reservations (
          lesson_id, subscription_id, units
        )
        values ($1, $2, $3)
        returning *
      `,
      [input.lessonId, input.subscriptionId, input.units],
    );
  }
}
