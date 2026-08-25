import { assembleLeadBoard } from "./lead-board-assembler";

describe("lead board assembler", () => {
  it("returns a targeted empty unassigned column with its configured order", () => {
    const result = assembleLeadBoard({
      statuses: [],
      counts: [{ status_id: null, count: "0" }],
      rows: [],
      stages: [],
      limit: 25,
      requestedColumnId: "unassigned",
      unassignedSort: 4,
    });

    expect(result).toEqual({
      columns: [
        expect.objectContaining({
          id: "unassigned",
          sortOrder: 4,
          totalCount: 0,
          items: [],
          nextCursor: null,
        }),
      ],
      totalCount: 0,
      nextCursor: null,
    });
  });
});
