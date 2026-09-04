import { Injectable } from "@nestjs/common";
import { PoolClient, QueryResult, QueryResultRow } from "pg";
import type { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { managerBranchScopeSql } from "../branch-scope";

export type LessonLifecycleState =
  | "scheduled"
  | "settlement_pending"
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
  fromState?: "scheduled" | "settlement_pending" | "successfully_completed";
  toState: Exclude<LessonLifecycleState, "scheduled" | "settlement_pending">;
  reasonCode: string;
  reasonText?: string;
  actorUserId?: string;
  workerId?: string;
  predecessorId?: string;
  successorId?: string;
  financialDecision?: Record<string, unknown>;
  clientFinancialFactId?: string;
  clientFinancialFactIds?: string[];
  teacherFinancialFactId?: string;
}

export interface LessonActionableChainRow {
  chain_ids: string[];
  invalid: boolean;
  scope_violation: boolean;
}

type LessonLifecycleQueryable = Pick<PoolClient, "query"> | DatabaseService;

function runLifecycleQuery<T extends QueryResultRow>(
  queryable: LessonLifecycleQueryable,
  text: string,
  params: unknown[],
): Promise<QueryResult<T>> {
  return (
    queryable.query as (
      query: string,
      values?: unknown[],
    ) => Promise<QueryResult<T>>
  )(text, params);
}

@Injectable()
export class LessonLifecycleRepository {
  constructor(private readonly database: DatabaseService) {}

  async resolveActionableChain(
    actor: ActorContext,
    lessonId: string,
    client?: PoolClient,
  ): Promise<LessonActionableChainRow | null> {
    const queryable: LessonLifecycleQueryable = client ?? this.database;
    const result = await runLifecycleQuery<LessonActionableChainRow>(
      queryable,
      `
        with recursive scope_actor as (
          select actor.id, actor.role
          from app.users actor
          where actor.id = $2
            and actor.deleted_at is null
            and actor.is_app_account = true
            and actor.role in ('admin', 'manager', 'director', 'system_admin')
        ), lesson_rows as (
          select lesson.id, lesson.predecessor_id, lesson.successor_id,
            lesson.lifecycle_state, lesson.deleted_at,
            (
              scope_actor.id is not null
              and ${managerBranchScopeSql({
                roleExpression: "scope_actor.role",
                userIdExpression: "scope_actor.id",
                branchExpression: "lesson.branch_id::text",
              })}
            ) as in_scope
          from app.lessons lesson
          left join scope_actor on true
        ), requested as (
          select *
          from lesson_rows
          where id = $1
            and deleted_at is null
            and in_scope
        ), walk (
          id, predecessor_id, successor_id, lifecycle_state, deleted_at,
          in_scope, phase, depth, path, cycle_detected, overlong,
          missing_link, deleted_link, scope_violation, broken_link
        ) as (
          select requested.id, requested.predecessor_id, requested.successor_id,
            requested.lifecycle_state, requested.deleted_at,
            requested.in_scope, 'backward'::text, 0,
            array[requested.id]::uuid[], false, false, false, false, false, false
          from requested

          union all

          select target.id, target.predecessor_id, target.successor_id,
            target.lifecycle_state, target.deleted_at, target.in_scope,
            step.next_phase,
            case when step.switch_to_forward then 0 else walk.depth + 1 end,
            case when step.switch_to_forward then array[walk.id]::uuid[]
              else walk.path || step.next_id end,
            (not step.switch_to_forward and step.next_id = any(walk.path)),
            (not step.switch_to_forward and walk.depth >= 64),
            target.id is null,
            target.deleted_at is not null,
            target.id is not null and not target.in_scope,
            case
              when step.switch_to_forward then false
              when walk.phase = 'backward'
                then target.successor_id is distinct from walk.id
              else target.predecessor_id is distinct from walk.id
            end
          from walk
          cross join lateral (
            select
              case
                when walk.phase = 'backward' and walk.predecessor_id is not null
                  then walk.predecessor_id
                when walk.phase = 'backward' then walk.id
                else walk.successor_id
              end as next_id,
              case
                when walk.phase = 'backward' and walk.predecessor_id is null
                  then 'forward'::text
                else walk.phase
              end as next_phase,
              walk.phase = 'backward' and walk.predecessor_id is null
                as switch_to_forward
          ) step
          left join lesson_rows target on target.id = step.next_id
          where not walk.cycle_detected
            and not walk.overlong
            and not walk.missing_link
            and not walk.deleted_link
            and not walk.scope_violation
            and not walk.broken_link
            and (
              walk.phase = 'backward'
              or walk.successor_id is not null
            )
        ), summary as (
          select
            coalesce(
              array_agg(id order by depth) filter (
                where phase = 'forward'
                  and id is not null
                  and not cycle_detected
              ),
              array[]::uuid[]
            ) as chain_ids,
            coalesce(bool_or(scope_violation), false) as scope_violation,
            coalesce(bool_or(
              cycle_detected or overlong or missing_link or deleted_link
              or broken_link
            ), false)
            or exists (
              select 1
              from walk current_node
              where current_node.phase = 'forward'
                and current_node.id is not null
                and (
                  (
                    select count(*)
                    from app.lessons child
                    where child.predecessor_id = current_node.id
                  ) > 1
                  or (
                    current_node.successor_id is null
                    and exists (
                      select 1 from app.lessons child
                      where child.predecessor_id = current_node.id
                    )
                  )
                  or (
                    current_node.successor_id is not null
                    and not exists (
                      select 1 from app.lessons child
                      where child.id = current_node.successor_id
                        and child.predecessor_id = current_node.id
                    )
                  )
                  or (
                    current_node.lifecycle_state = 'rescheduled'
                    and current_node.successor_id is null
                  )
                )
            ) as invalid
          from walk
        )
        select chain_ids, invalid, scope_violation
        from summary
        where exists (select 1 from requested)
      `,
      [lessonId, actor.userId],
    );
    return result.rows[0] ?? null;
  }

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
              select jsonb_agg(to_jsonb(participant.*)
                order by participant.student_id)
              from app.lesson_snapshot_participants participant
              where participant.lesson_id = lesson.id
            ),
            '[]'::jsonb
          ) as snapshot_participants,
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

  async createGroupSnapshot(
    client: PoolClient,
    input: {
      lessonId: string;
      groupId: string;
      completionType: string;
      teacherCompensationType: "fixed" | "hourly" | "none";
      teacherCompensationValue: number;
      trial: boolean;
      participants: Array<{
        studentId: string;
        chargeType: "subscription" | "personal_account" | "none";
        chargeValue: number;
        subscriptionId?: string;
      }>;
    },
  ) {
    const snapshot = await client.query(
      `
        insert into app.lesson_snapshots (
          lesson_id, group_id, completion_type,
          client_charge_type, client_charge_value,
          teacher_compensation_type, teacher_compensation_value,
          trial, duration_minutes
        ) values (
          $1, $2, $3, 'none', 0, $4, $5, $6,
          (select duration_minutes from app.lessons where id = $1)
        )
        returning *
      `,
      [
        input.lessonId,
        input.groupId,
        input.completionType,
        input.teacherCompensationType,
        input.teacherCompensationValue,
        input.trial,
      ],
    );
    for (const participant of input.participants) {
      await client.query(
        `
          insert into app.lesson_snapshot_participants (
            lesson_id, student_id, charge_type, charge_value, subscription_id
          ) values ($1, $2, $3, $4, $5)
        `,
        [
          input.lessonId,
          participant.studentId,
          participant.chargeType,
          participant.chargeValue,
          participant.subscriptionId ?? null,
        ],
      );
    }
    return snapshot;
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
          client_financial_fact_ids,
          teacher_financial_fact_id
        )
        values (
          $1, $2, $3, $4, $5, $6, $7, $8, $9, $10::jsonb,
          $11, $12::uuid[], $13
        )
        returning *
      `,
      [
        input.lessonId,
        input.fromState ?? "scheduled",
        input.toState,
        input.reasonCode,
        input.reasonText ?? null,
        input.actorUserId ?? null,
        input.workerId ?? null,
        input.predecessorId ?? null,
        input.successorId ?? null,
        JSON.stringify(input.financialDecision ?? {}),
        input.clientFinancialFactId ?? null,
        input.clientFinancialFactIds ?? [],
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
