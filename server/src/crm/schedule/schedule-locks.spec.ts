import {
  acquireScheduleLockKeys,
  lockSchedulePlanSeries,
} from "./schedule-locks";

describe("schedule locks", () => {
  it("canonicalizes and orders advisory resource keys", async () => {
    const query = jest.fn().mockResolvedValue({ rows: [] });

    await acquireScheduleLockKeys({ query }, [
      "teacher:ABC-DEF",
      "teacher:abc-def",
      "room:ROOM-A",
    ]);

    expect(query.mock.calls.map((call) => call[1][0])).toEqual([
      "room:room-a",
      "teacher:abc-def",
    ]);
  });

  it("uses the same deterministic keys for Plan series", async () => {
    const query = jest.fn().mockResolvedValue({ rows: [] });

    await lockSchedulePlanSeries({ query }, [
      "series-b",
      "series-a",
      "series-a",
    ]);

    expect(query.mock.calls.map((call) => call[1][0])).toEqual([
      "series:series-a",
      "series:series-b",
    ]);
  });
});
