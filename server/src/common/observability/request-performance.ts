import { AsyncLocalStorage } from 'node:async_hooks';
import { performance } from 'node:perf_hooks';

export interface RequestPerformance {
  requestId: string;
  operationId?: string;
  startedAt: number;
  dbQueryCount: number;
  dbQueryMs: number;
  dbMaxQueryMs: number;
  dbErrorCount: number;
  dbAcquireCount: number;
  dbAcquireMs: number;
  dbMaxWaiting: number;
  closed: boolean;
}

export const requestPerformance = new AsyncLocalStorage<RequestPerformance>();

export function newRequestPerformance(requestId: string, operationId?: string): RequestPerformance {
  return { requestId, operationId, startedAt: performance.now(), dbQueryCount: 0,
    dbQueryMs: 0, dbMaxQueryMs: 0, dbErrorCount: 0, dbAcquireCount: 0,
    dbAcquireMs: 0, dbMaxWaiting: 0, closed: false };
}

/** Only numeric measurements are retained; SQL, parameters and results never enter telemetry. */
export async function measureDatabase<T>(kind: 'query' | 'acquire', work: () => Promise<T>, waiting = 0): Promise<T> {
  const context = requestPerformance.getStore();
  if (!context || context.closed) return work();
  const startedAt = performance.now();
  if (kind === 'acquire') context.dbMaxWaiting = Math.max(context.dbMaxWaiting, waiting);
  try {
    return await work();
  } catch (error) {
    if (!context.closed) context.dbErrorCount++;
    throw error;
  } finally {
    if (!context.closed) {
      const elapsed = performance.now() - startedAt;
      if (kind === 'query') {
        context.dbQueryCount++;
        context.dbQueryMs += elapsed;
        context.dbMaxQueryMs = Math.max(context.dbMaxQueryMs, elapsed);
      } else {
        context.dbAcquireCount++;
        context.dbAcquireMs += elapsed;
      }
    }
  }
}

export const milliseconds = (value: number): number => Math.round(value * 100) / 100;

export function performanceFields(context: RequestPerformance) {
  return {
    requestId: context.requestId, operationId: context.operationId,
    durationMs: milliseconds(performance.now() - context.startedAt),
    dbQueryCount: context.dbQueryCount, dbQueryMs: milliseconds(context.dbQueryMs),
    dbMaxQueryMs: milliseconds(context.dbMaxQueryMs), dbErrorCount: context.dbErrorCount,
    dbAcquireCount: context.dbAcquireCount, dbAcquireMs: milliseconds(context.dbAcquireMs),
    dbMaxWaiting: context.dbMaxWaiting,
  };
}
