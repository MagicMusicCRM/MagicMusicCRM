import {
  acquireLessonSettlementLocks,
  acquireStableArchiveLessonLocks,
} from "./lesson-settlement-locks";

describe("lesson settlement locks", () => {
  it("deduplicates lesson ids and acquires locks in deterministic order", async () => {
    const query = jest.fn().mockResolvedValue({ rows: [] });

    await acquireLessonSettlementLocks({ query }, [
      "lesson-b",
      "lesson-a",
      "lesson-b",
    ]);

    expect(query.mock.calls.map((call) => call[1][0])).toEqual([
      "commerce:lesson-settlement:lesson-a",
      "commerce:lesson-settlement:lesson-b",
    ]);
  });

  it("re-discovers until stable before and after the creation barrier", async () => {
    const events: string[] = [];
    const query = jest.fn().mockImplementation(
      async (_sql: string, params: unknown[]) => {
        events.push(`lock:${String(params[0])}`);
        return { rows: [] };
      },
    );
    const rounds = [
      ["lesson-b"],
      ["lesson-a", "lesson-b"],
      ["lesson-a", "lesson-b"],
      ["lesson-a", "lesson-b", "lesson-c"],
      ["lesson-a", "lesson-b", "lesson-c"],
    ];
    const discover = jest.fn().mockImplementation(async () => {
      events.push("discover");
      return rounds.shift()!;
    });

    await expect(acquireStableArchiveLessonLocks(
      { query },
      discover,
      async () => { events.push("creation-barrier"); },
    )).resolves.toEqual(["lesson-a", "lesson-b", "lesson-c"]);

    expect(events).toEqual([
      "lock:commerce:client-archive:lesson-discovery",
      "discover",
      "lock:commerce:lesson-settlement:lesson-b",
      "discover",
      "lock:commerce:lesson-settlement:lesson-a",
      "discover",
      "creation-barrier",
      "discover",
      "lock:commerce:lesson-settlement:lesson-c",
      "discover",
    ]);
  });
});
