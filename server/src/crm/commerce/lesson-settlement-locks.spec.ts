import { acquireLessonSettlementLocks } from "./lesson-settlement-locks";

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
});
