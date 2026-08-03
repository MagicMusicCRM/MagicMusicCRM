import { Injectable } from "@nestjs/common";
import { PoolClient } from "pg";
import { DatabaseService } from "../../db/database.service";
import {
  LessonCompletionClaim,
  LessonCompletionWorkerMetrics,
} from "./completion-worker.types";

interface ClaimRow {
  lesson_id: string;
  lesson_version: number | string;
  scheduled_end_at: Date | string;
  attempts: number | string;
  claimed_at: Date | string;
  claimed_by: string;
}

interface CompletionSourceRow {
  id: string;
  version: number | string;
  lifecycle_state:
    | "scheduled"
    | "successfully_completed"
    | "cancelled"
    | "rescheduled";
}

@Injectable()
export class LessonCompletionWorkerRepository {
  constructor(private readonly database: DatabaseService) {}

  claimDue(
    workerId: string,
    options: {
      limit: number;
      leaseSeconds: number;
      maxAttempts: number;
    },
  ): Promise<LessonCompletionClaim[]> {
    const limit = positiveInteger(options.limit, 25);
    const leaseSeconds = positiveInteger(options.leaseSeconds, 60);
    const maxAttempts = positiveInteger(options.maxAttempts, 5);
    return this.database.transaction(async (client) => {
      // If a process dies after taking its final allowed lease, there is no
      // catch block left to classify the row. Promote that expired lease to a
      // visible poison state before looking for more work.
      await client.query(
        `
          update app.lesson_completion_work
          set state = 'poison',
              claimed_at = null,
              claimed_by = null,
              completed_at = null,
              last_error = coalesce(
                last_error,
                'LessonCompletionLeaseExhausted'
              ),
              updated_at = now()
          where state = 'claimed'
            and attempts >= $1
            and claimed_at < now() - make_interval(secs => $2)
        `,
        [maxAttempts, leaseSeconds],
      );
      const result = await client.query<ClaimRow>(
        `
          with candidates as (
            select
              lesson.id,
              lesson.version,
              lesson.scheduled_at
                + make_interval(mins => lesson.duration_minutes)
                as scheduled_end_at
            from app.lessons lesson
            left join app.lesson_completion_work work
              on work.lesson_id = lesson.id
            where lesson.deleted_at is null
              and lesson.lifecycle_state = 'scheduled'
              and lesson.scheduled_at
                    + make_interval(mins => lesson.duration_minutes) <= now()
              and coalesce(work.attempts, 0) < $4
              and (
                work.lesson_id is null
                or (
                  work.state = 'retry'
                  and work.available_at <= now()
                )
                or (
                  work.state = 'claimed'
                  and work.claimed_at
                        < now() - make_interval(secs => $3)
                )
              )
            order by scheduled_end_at, lesson.id
            for update of lesson skip locked
            limit $2
          )
          insert into app.lesson_completion_work (
            lesson_id,
            state,
            lesson_version,
            scheduled_end_at,
            attempts,
            available_at,
            claimed_at,
            claimed_by,
            completed_at,
            transition_id,
            client_financial_fact_id,
            teacher_financial_fact_id,
            terminal_state,
            updated_at
          )
          select
            candidate.id,
            'claimed',
            candidate.version,
            candidate.scheduled_end_at,
            1,
            now(),
            now(),
            $1,
            null,
            null,
            null,
            null,
            null,
            now()
          from candidates candidate
          on conflict (lesson_id) do update
          set state = 'claimed',
              lesson_version = excluded.lesson_version,
              scheduled_end_at = excluded.scheduled_end_at,
              attempts = app.lesson_completion_work.attempts + 1,
              available_at = now(),
              claimed_at = now(),
              claimed_by = excluded.claimed_by,
              completed_at = null,
              transition_id = null,
              client_financial_fact_id = null,
              client_financial_fact_ids = '{}'::uuid[],
              teacher_financial_fact_id = null,
              terminal_state = null,
              updated_at = now()
          where (
              app.lesson_completion_work.state = 'retry'
              and app.lesson_completion_work.available_at <= now()
            )
            or (
              app.lesson_completion_work.state = 'claimed'
              and app.lesson_completion_work.claimed_at
                    < now() - make_interval(secs => $3)
            )
          returning
            lesson_id,
            lesson_version,
            scheduled_end_at,
            attempts,
            claimed_at,
            claimed_by
        `,
        [workerId, limit, leaseSeconds, maxAttempts],
      );
      return result.rows.map(mapClaim);
    });
  }

  async lockClaimAndLesson(
    client: PoolClient,
    claim: LessonCompletionClaim,
  ): Promise<CompletionSourceRow> {
    const owned = await client.query(
      `
        select lesson_id
        from app.lesson_completion_work
        where lesson_id = $1
          and state = 'claimed'
          and claimed_by = $2
          and attempts = $3
        for update
      `,
      [claim.lessonId, claim.workerId, claim.attempts],
    );
    if (!owned.rows[0]) {
      throw workerError("LESSON_COMPLETION_CLAIM_NOT_OWNED");
    }

    const source = await client.query<CompletionSourceRow>(
      `
        select
          id,
          version,
          lifecycle_state
        from app.lessons
        where id = $1 and deleted_at is null
        for update
      `,
      [claim.lessonId],
    );
    const row = source.rows[0];
    if (!row) throw workerError("LESSON_COMPLETION_SOURCE_MISSING");
    return row;
  }

  async markCompleted(
    client: PoolClient,
    input: {
      claim: LessonCompletionClaim;
      transitionId: string;
      clientFinancialFactId: string;
      clientFinancialFactIds: string[];
      teacherFinancialFactId: string;
    },
  ): Promise<void> {
    const updated = await client.query(
      `
        update app.lesson_completion_work
        set state = 'completed',
            claimed_at = null,
            claimed_by = null,
            completed_at = now(),
            transition_id = $4,
            client_financial_fact_id = $5,
            client_financial_fact_ids = $6::uuid[],
            teacher_financial_fact_id = $7,
            terminal_state = 'successfully_completed',
            last_error = null,
            updated_at = now()
        where lesson_id = $1
          and state = 'claimed'
          and claimed_by = $2
          and attempts = $3
      `,
      [
        input.claim.lessonId,
        input.claim.workerId,
        input.claim.attempts,
        input.transitionId,
        input.clientFinancialFactId,
        input.clientFinancialFactIds,
        input.teacherFinancialFactId,
      ],
    );
    if (updated.rowCount !== 1) {
      throw workerError("LESSON_COMPLETION_CLAIM_NOT_OWNED");
    }
  }

  async markTerminalObserved(claim: LessonCompletionClaim): Promise<boolean> {
    const result = await this.database.query(
      `
        update app.lesson_completion_work work
        set state = 'completed',
            claimed_at = null,
            claimed_by = null,
            completed_at = now(),
            terminal_state = lesson.lifecycle_state,
            last_error = null,
            updated_at = now()
        from app.lessons lesson
        where work.lesson_id = $1
          and work.claimed_by = $2
          and work.attempts = $3
          and work.state = 'claimed'
          and lesson.id = work.lesson_id
          and lesson.lifecycle_state <> 'scheduled'
      `,
      [claim.lessonId, claim.workerId, claim.attempts],
    );
    return result.rowCount === 1;
  }

  async markFailed(
    claim: LessonCompletionClaim,
    error: unknown,
    options: {
      baseSeconds: number;
      capSeconds: number;
      maxAttempts: number;
    },
  ): Promise<"retry" | "poison" | "not-owned"> {
    const maxAttempts = positiveInteger(options.maxAttempts, 5);
    const retryAfterSeconds = computeCompletionBackoffSeconds(
      claim.attempts,
      options.baseSeconds,
      options.capSeconds,
    );
    const result = await this.database.query<{ state: "retry" | "poison" }>(
      `
        update app.lesson_completion_work
        set state = case when attempts >= $5 then 'poison' else 'retry' end,
            available_at = now() + make_interval(secs => $4),
            claimed_at = null,
            claimed_by = null,
            completed_at = null,
            last_error = $6,
            updated_at = now()
        where lesson_id = $1
          and state = 'claimed'
          and claimed_by = $2
          and attempts = $3
        returning state
      `,
      [
        claim.lessonId,
        claim.workerId,
        claim.attempts,
        retryAfterSeconds,
        maxAttempts,
        safeFailureName(error),
      ],
    );
    return result.rows[0]?.state ?? "not-owned";
  }

  async metrics(): Promise<LessonCompletionWorkerMetrics> {
    const result = await this.database.query<{
      due: number | string;
      claimed: number | string;
      retry: number | string;
      poison: number | string;
      completed: number | string;
      oldest_due_seconds: number | string | null;
      max_attempts: number | string | null;
    }>(
      `
        select
          (
            select count(*)
            from app.lessons lesson
            where lesson.deleted_at is null
              and lesson.lifecycle_state = 'scheduled'
              and lesson.scheduled_at
                    + make_interval(mins => lesson.duration_minutes) <= now()
          ) as due,
          count(*) filter (where work.state = 'claimed') as claimed,
          count(*) filter (where work.state = 'retry') as retry,
          count(*) filter (where work.state = 'poison') as poison,
          count(*) filter (where work.state = 'completed') as completed,
          (
            select floor(extract(epoch from (
              now() - min(
                lesson.scheduled_at
                  + make_interval(mins => lesson.duration_minutes)
              )
            )))
            from app.lessons lesson
            where lesson.deleted_at is null
              and lesson.lifecycle_state = 'scheduled'
              and lesson.scheduled_at
                    + make_interval(mins => lesson.duration_minutes) <= now()
          ) as oldest_due_seconds,
          max(work.attempts) as max_attempts
        from app.lesson_completion_work work
      `,
    );
    const row = result.rows[0]!;
    return {
      due: Number(row.due),
      claimed: Number(row.claimed),
      retry: Number(row.retry),
      poison: Number(row.poison),
      completed: Number(row.completed),
      oldestDueSeconds:
        row.oldest_due_seconds === null
          ? null
          : Number(row.oldest_due_seconds),
      maxAttempts: Number(row.max_attempts ?? 0),
    };
  }
}

export function computeCompletionBackoffSeconds(
  attempts: number,
  baseSeconds = 5,
  capSeconds = 300,
): number {
  const safeAttempts = Math.max(1, Math.floor(attempts));
  const safeBase = positiveInteger(baseSeconds, 5);
  const safeCap = Math.max(safeBase, positiveInteger(capSeconds, 300));
  return Math.min(safeCap, safeBase * 2 ** (safeAttempts - 1));
}

function positiveInteger(value: number, fallback: number): number {
  if (!Number.isFinite(value)) return fallback;
  return Math.max(1, Math.floor(value));
}

function safeFailureName(error: unknown): string {
  if (error instanceof Error && error.name) {
    return error.name.slice(0, 120);
  }
  return "LessonCompletionFailure";
}

function workerError(code: string): Error {
  const error = new Error(code);
  error.name = code;
  return error;
}

function mapClaim(row: ClaimRow): LessonCompletionClaim {
  return {
    lessonId: row.lesson_id,
    lessonVersion: Number(row.lesson_version),
    scheduledEndAt: new Date(row.scheduled_end_at),
    attempts: Number(row.attempts),
    claimedAt: new Date(row.claimed_at),
    workerId: row.claimed_by,
  };
}
