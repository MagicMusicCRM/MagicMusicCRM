import type { QueryResult, QueryResultRow } from "pg";

interface LessonSettlementLockExecutor {
  query<T extends QueryResultRow = QueryResultRow>(
    query: string,
    params?: unknown[],
  ): Promise<QueryResult<T>>;
}

export const lessonSettlementLockKey = (lessonId: string) =>
  `commerce:lesson-settlement:${lessonId}`;

// Keep the established key string so mixed-version transactions coordinate
// during a rolling deployment. The gate covers archive discovery, every
// reschedule path, and transitions that lock multiple lessons.
const lessonSettlementCoordinationGateKey =
  "commerce:multi-lesson-settlement";

export async function acquireLessonSettlementCoordinationGate(
  executor: LessonSettlementLockExecutor,
): Promise<void> {
  await executor.query(
    "select pg_advisory_xact_lock(hashtextextended($1::text, 0))",
    [lessonSettlementCoordinationGateKey],
  );
}

/** Single-lesson terminal transitions never discover additional lesson locks. */
export async function acquireSingleLessonSettlementGate(
  executor: LessonSettlementLockExecutor,
): Promise<void> {
  await executor.query(
    "select pg_advisory_xact_lock_shared(hashtextextended($1::text, 0))",
    [lessonSettlementCoordinationGateKey],
  );
}

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

export async function acquireStableLessonSettlementLocks(
  executor: LessonSettlementLockExecutor,
  discoverLessonIds: () => Promise<string[]>,
  acquireCreationBarrier: () => Promise<void>,
): Promise<string[]> {
  // Multi-round discovery can find a lower id after locking a higher id.
  // Share one gate with multi-lesson transitions and every reschedule before
  // either side acquires its first per-lesson settlement lock.
  await acquireLessonSettlementCoordinationGate(executor);
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
