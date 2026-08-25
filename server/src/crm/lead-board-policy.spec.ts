import { assembleLeadBoard } from "./lead-board-assembler";
import { buildLeadBoardFilter, decodeLeadCursor } from "./lead-board-filter";
import { LeadBoardRow } from "./lead-model";

const statusA = "11111111-1111-4111-8111-111111111111";
const statusB = "22222222-2222-4222-8222-222222222222";

function boardRow(
  id: string,
  statusId: string | null,
  timestamp: string,
): LeadBoardRow {
  return {
    id,
    status_id: statusId,
    status_name: statusId ? `Status ${statusId.slice(0, 4)}` : null,
    status_color: null,
    status_sort_order: statusId === statusA ? 0 : 1,
    first_name: id,
    last_name: null,
    phone: null,
    email: null,
    source: null,
    notes: null,
    assigned_to: null,
    assigned_first_name: null,
    assigned_last_name: null,
    branch_id: null,
    branch_name: null,
    linked_student_id: null,
    linked_user_id: null,
    open_tasks_count: "0",
    comments_count: "0",
    trial_lessons_count: "0",
    custom_data: {},
    created_by: null,
    created_at: timestamp,
    cursor_created_at: timestamp,
    updated_at: timestamp,
  };
}

describe("lead board policy", () => {
  it("rejects malformed cursors without adding pagination parameters", () => {
    expect(decodeLeadCursor("not-a-cursor")).toBeNull();
    const filter = buildLeadBoardFilter(
      { cursor: "2026-08-25T10:00:00.000000Z|not-a-uuid" },
      "manager-a",
    );
    expect(filter.params).toEqual([]);
    expect(filter.where).not.toContain("l.created_at, l.id");
  });

  it("uses the oldest-first comparator for a valid scoped cursor", () => {
    const cursor = `2026-08-25T10:00:00.123456Z|${statusA}`;
    const filter = buildLeadBoardFilter(
      { cursor, statusId: statusB, sort: "oldest" },
      "manager-a",
    );
    expect(filter.params).toEqual([
      statusB,
      "2026-08-25T10:00:00.123456Z",
      statusA,
    ]);
    expect(filter.where).toContain("(l.created_at, l.id) >");
  });

  it("paginates each column independently and keeps the legacy boundary", () => {
    const rows = [
      boardRow(statusA, statusA, "2026-08-25T10:00:00.000001Z"),
      boardRow(
        "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        statusA,
        "2026-08-25T09:00:00.000001Z",
      ),
      boardRow(statusB, statusB, "2026-08-25T08:00:00.000001Z"),
      boardRow(
        "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
        statusB,
        "2026-08-25T07:00:00.000001Z",
      ),
    ];
    const result = assembleLeadBoard({
      statuses: [
        {
          id: statusA,
          stage_key: "new",
          name: "Новый",
          color: null,
          sort_order: 0,
          created_at: rows[0]!.created_at,
        },
        {
          id: statusB,
          stage_key: "work",
          name: "В работе",
          color: null,
          sort_order: 1,
          created_at: rows[0]!.created_at,
        },
      ],
      counts: [
        { status_id: statusA, count: "2" },
        { status_id: statusB, count: "2" },
      ],
      rows,
      stages: [],
      limit: 1,
      requestedColumnId: null,
      unassignedSort: null,
    });
    expect(result.columns.map((column) => column.items.length)).toEqual([1, 1]);
    expect(result.columns.every((column) => column.nextCursor)).toBe(true);
    expect(result.nextCursor).toBe(
      "2026-08-25T08:00:00.000001Z|22222222-2222-4222-8222-222222222222",
    );
  });

  it("returns an empty targeted unassigned column", () => {
    const result = assembleLeadBoard({
      statuses: [],
      counts: [],
      rows: [],
      stages: [],
      limit: 25,
      requestedColumnId: "unassigned",
      unassignedSort: 7,
    });
    expect(result.columns).toEqual([
      expect.objectContaining({
        id: "unassigned",
        sortOrder: 7,
        items: [],
        nextCursor: null,
      }),
    ]);
    expect(result.nextCursor).toBeNull();
  });
});
