import { measureDatabase, newRequestPerformance, requestPerformance } from './request-performance';

describe('request performance context', () => {
  it('isolates parallel request counters and records failures without swallowing them', async () => {
    const a = newRequestPerformance('a');
    const b = newRequestPerformance('b');
    const failure = new Error('private database detail');
    await Promise.all([
      requestPerformance.run(a, async () => {
        await measureDatabase('acquire', async () => undefined, 3);
        await measureDatabase('query', async () => new Promise(resolve => setTimeout(resolve, 15)));
      }),
      requestPerformance.run(b, async () => {
        await expect(measureDatabase('query', async () => { throw failure; })).rejects.toBe(failure);
        await measureDatabase('query', async () => 1);
      })
    ]);
    expect(a).toMatchObject({ dbQueryCount: 1, dbAcquireCount: 1, dbMaxWaiting: 3, dbErrorCount: 0 });
    expect(b).toMatchObject({ dbQueryCount: 2, dbAcquireCount: 0, dbErrorCount: 1 });
    expect(a.dbQueryMs).toBeGreaterThan(5);
    expect(JSON.stringify([a, b])).not.toContain('private');
    expect(requestPerformance.getStore()).toBeUndefined();
  });

  it('does not attribute detached work to a completed request', async () => {
    const context = newRequestPerformance('closed');
    await requestPerformance.run(context, () => measureDatabase('query', async () => { context.closed = true; }));
    expect(context.dbQueryCount).toBe(0);
  });
});
