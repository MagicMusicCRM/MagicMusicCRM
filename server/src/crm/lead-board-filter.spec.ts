import { buildLeadBoardFilter, decodeLeadCursor } from "./lead-board-filter";

describe("lead board filter", () => {
  it("keeps cursor parameters scoped after identity filters", () => {
    const statusId = "11111111-1111-4111-8111-111111111111";
    const cursorId = "22222222-2222-4222-8222-222222222222";
    const cursor = `2026-08-25T10:00:00.123456Z|${cursorId}`;
    const filter = buildLeadBoardFilter(
      { statusId, cursor, sort: "oldest" },
      "manager-a",
    );

    expect(decodeLeadCursor(cursor)).toEqual({
      createdAt: "2026-08-25T10:00:00.123456Z",
      id: cursorId,
    });
    expect(filter.params).toEqual([
      statusId,
      "2026-08-25T10:00:00.123456Z",
      cursorId,
    ]);
    expect(filter.where).toContain("(l.created_at, l.id) >");
  });
});
