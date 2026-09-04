import type { QueryResult, QueryResultRow } from "pg";

interface LessonSettlementLockExecutor {
  query<T extends QueryResultRow = QueryResultRow>(
    query: string,
    params?: unknown[],
  ): Promise<QueryResult<T>>;
}

export const lessonSettlementLockKey = (lessonId: string) =>
  `commerce:lesson-settlement:${lessonId}`;

const clientArchiveLessonDiscoveryLockKey =
  "commerce:client-archive:lesson-discovery";

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

export async function acquireStableArchiveLessonLocks(
  executor: LessonSettlementLockExecutor,
  discoverLessonIds: () => Promise<string[]>,
  acquireCreationBarrier: () => Promise<void>,
): Promise<string[]> {
  // Client archives can overlap on group lessons. Serialize their multi-round
  // discovery so a newly discovered lower id cannot invert the lesson order.
  await executor.query(
    "select pg_advisory_xact_lock(hashtextextended($1::text, 0))",
    [clientArchiveLessonDiscoveryLockKey],
  );
  const locked = new Set<string>();
  const lockUntilStable = async () => {
    while (true) {
      const missing = (await discoverLessonIds())
        .filter((lessonId) => !locked.has(lessonId))
        .sort();
      if (missing.length === 0) return;
      await acquireLessonSettlementLocks(executor, missing);
      missing.forEach((lessonId) => locked.add(lessonId));
    }
  };
  await lockUntilStable();
  // Lesson creators use client schedule keys before persisting snapshots.
  // Acquire that key after lesson locks, matching transition lesson->client
  // order, then re-scan for work that committed while the archive waited.
  await acquireCreationBarrier();
  await lockUntilStable();
  return [...locked].sort();
}
