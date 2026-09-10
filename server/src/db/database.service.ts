import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Pool, PoolClient, QueryConfig, QueryResult, QueryResultRow } from 'pg';
import { measureDatabase, requestPerformance } from '../common/observability/request-performance';

type QueryInput = string | QueryConfig<unknown[]>;

@Injectable()
export class DatabaseService implements OnModuleDestroy {
  private readonly pool: Pool;

  constructor(config: ConfigService) {
    const connectionString = config.getOrThrow<string>('DATABASE_URL');
    // Per-process budget. Keep the existing default; increasing it must account
    // for all replicas, background workers and PostgreSQL's connection reserve.
    const max = Number(config.get?.('DATABASE_POOL_MAX', 10) ?? 10);
    if (!Number.isInteger(max) || max < 1 || max > 50) {
      throw new Error('DATABASE_POOL_MAX must be an integer between 1 and 50');
    }
    this.pool = new Pool({
      connectionString,
      max,
      idleTimeoutMillis: 30_000,
      connectionTimeoutMillis: 5_000
    });
  }

  async query<T extends QueryResultRow = QueryResultRow>(
    query: QueryInput,
    params?: unknown[]
  ): Promise<QueryResult<T>> {
    if (!requestPerformance.getStore()) return this.pool.query<T>(query, params);
    const client = await this.connect();
    let failure: Error | undefined;
    try {
      return await measureDatabase('query', () => client.query<T>(query, params));
    } catch (error) {
      failure = error instanceof Error ? error : new Error('Database query failed');
      throw error;
    } finally {
      // Match pg Pool.query: failed single-query connections are discarded.
      client.release(failure);
    }
  }

  async transaction<T>(work: (client: PoolClient) => Promise<T>): Promise<T> {
    const rawClient = await this.connect();
    const client = this.measuredClient(rawClient);
    let rollbackFailure: Error | undefined;
    try {
      await client.query('begin');
      const result = await work(client);
      await client.query('commit');
      return result;
    } catch (error) {
      try {
        await client.query('rollback');
      } catch (rollbackError) {
        rollbackFailure = rollbackError instanceof Error ? rollbackError : new Error('Rollback failed');
      }
      throw error;
    } finally {
      rawClient.release(rollbackFailure);
    }
  }

  private connect(): Promise<PoolClient> {
    return measureDatabase('acquire', () => this.pool.connect(), this.pool.waitingCount);
  }

  private measuredClient(client: PoolClient): PoolClient {
    if (!requestPerformance.getStore()) return client;
    // Do not mutate a pooled client's query method: it may be reused by a
    // different request. Promise queries are the application's transaction API.
    return new Proxy(client, {
      get(target, property) {
        if (property === 'query') {
          return (...args: unknown[]) => {
            // Preserve pg's callback/stream overloads; the current application
            // uses promises. Do not turn those overloads into promises.
            const config = args[0] as { callback?: unknown; submit?: unknown } | undefined;
            if (args.some(arg => typeof arg === 'function') || config?.callback || config?.submit) {
              return Reflect.apply(target.query, target, args);
            }
            return measureDatabase('query', () => Reflect.apply(target.query, target, args));
          };
        }
        const value = Reflect.get(target, property);
        return typeof value === 'function' ? value.bind(target) : value;
      }
    });
  }

  async onModuleDestroy() {
    await this.pool.end();
  }
}
