import type { QueryResult, QueryResultRow } from "pg";

export interface ScheduleQueryExecutor {
  query<T extends QueryResultRow = QueryResultRow>(
    query: string,
    params?: unknown[],
  ): Promise<QueryResult<T>>;
}

export async function acquireScheduleLockKeys(
  executor: ScheduleQueryExecutor,
  keys: Array<string | null | undefined>,
): Promise<void> {
  const resources = [
    ...new Set(
      keys
        .filter((resource): resource is string => typeof resource === "string")
        .map((resource) => resource.toLowerCase()),
    ),
  ].sort();
  for (const resource of resources) {
    await executor.query(
      "select pg_advisory_xact_lock(hashtextextended($1::text, 0))",
      [resource],
    );
  }
}

export function acquireScheduleResourceLocks(
  executor: ScheduleQueryExecutor,
  teacherId: string | null,
  roomId: string | null,
): Promise<void> {
  return acquireScheduleLockKeys(executor, [
    teacherId ? `teacher:${teacherId}` : null,
    roomId ? `room:${roomId}` : null,
  ]);
}

export function acquireScheduleSeriesLock(
  executor: ScheduleQueryExecutor,
  seriesId: string,
): Promise<void> {
  return acquireScheduleLockKeys(executor, [`series:${seriesId}`]);
}

export function lockSchedulePlanSeries(
  executor: ScheduleQueryExecutor,
  seriesIds: string[],
): Promise<void> {
  return acquireScheduleLockKeys(
    executor,
    seriesIds.map((seriesId) => `series:${seriesId}`),
  );
}
