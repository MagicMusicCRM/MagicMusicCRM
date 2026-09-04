import type { QueryResult, QueryResultRow } from "pg";

interface LessonSettlementLockExecutor {
  query<T extends QueryResultRow = QueryResultRow>(
    query: string,
    params?: unknown[],
  ): Promise<QueryResult<T>>;
}

export const lessonSettlementLockKey = (lessonId: string) =>
  `commerce:lesson-settlement:${lessonId}`;

export async function acquireLessonSettlementLocks(
  executor: LessonSettlementLockExecutor,
  lessonIds: string[],
): Promise<void> {
  const orderedIds = [...new Set(lessonIds)].sort();
  for (const lessonId of orderedIds) {
    await executor.query(
      "select pg_advisory_xact_lock(hashtextextended($1::text, 0))",
      [lessonSettlementLockKey(lessonId)],
    );
  }
}
