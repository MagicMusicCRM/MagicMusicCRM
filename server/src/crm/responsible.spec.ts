import { DatabaseService } from "../db/database.service";
import { ensureResponsible, ensureResponsibleSafe } from "./responsible";
import {
  ACTIVE_RESPONSIBLE_STAFF_STATUSES,
  RESPONSIBLE_AUTH_ROLES,
} from "./responsible-eligibility";

describe("responsible ownership", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  it("uses leads.assigned_to as canonical and only mirrors custom_data", async () => {
    const query = jest.fn().mockResolvedValue({ rows: [], rowCount: 1 });
    await ensureResponsible(
      { query } as unknown as DatabaseService,
      actor,
      "lead",
      "lead-a",
    );

    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("with eligible_actor as");
    expect(sql).toContain("join app.staff_members");
    expect(sql).toContain("l.assigned_to is null");
    expect(sql).toContain("set assigned_to = eligible_actor.user_id");
    expect(sql).toContain("version = l.version + 1");
    expect(sql.match(/l\.assigned_to is null/g)).toHaveLength(2);
    expect(sql.match(/l\.custom_data->>'responsible'/g)).toHaveLength(2);
    expect(sql).toContain("'responsibleUserId'");
    // An imported display-only value prevents an automatic overwrite.
    expect(sql).toContain("l.custom_data->>'responsible'");
    expect(query.mock.calls[0][1]).toEqual([
      "lead-a",
      "manager-a",
      [...RESPONSIBLE_AUTH_ROLES],
      [...ACTIVE_RESPONSIBLE_STAFF_STATUSES],
    ]);
  });

  it("keeps the established student custom_data contract", async () => {
    const query = jest.fn().mockResolvedValue({ rows: [], rowCount: 1 });
    await ensureResponsible(
      { query } as unknown as DatabaseService,
      actor,
      "student",
      "student-a",
    );

    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("update app.students");
    expect(sql).toContain("version = s.version + 1");
    expect(sql).toContain("coalesce(s.custom_data->>'responsible', '') = ''");
    expect(sql).not.toContain("assigned_to");
    expect(query.mock.calls[0][1]).toEqual([
      "student-a",
      "manager-a",
      [...RESPONSIBLE_AUTH_ROLES],
      [...ACTIVE_RESPONSIBLE_STAFF_STATUSES],
    ]);
  });

  it("does not auto-claim for teacher or system_admin actors", async () => {
    for (const role of ["teacher", "system_admin"] as const) {
      const query = jest.fn();
      await ensureResponsible(
        { query } as unknown as DatabaseService,
        { userId: `${role}-a`, role },
        "lead",
        "lead-a",
      );
      expect(query).not.toHaveBeenCalled();
    }
  });

  it("awaits the compatibility write before resolving", async () => {
    let release!: () => void;
    const query = jest.fn(
      () =>
        new Promise<{ rows: []; rowCount: number }>((resolve) => {
          release = () => resolve({ rows: [], rowCount: 1 });
        }),
    );
    let settled = false;
    const pending = ensureResponsibleSafe(
      { query } as unknown as DatabaseService,
      actor,
      "student",
      "student-a",
    ).then(() => {
      settled = true;
    });

    await Promise.resolve();
    expect(settled).toBe(false);
    release();
    await pending;
    expect(settled).toBe(true);
  });
});
