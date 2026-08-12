import { DatabaseService } from "../db/database.service";
import { audienceForLesson, clientFinanceAudienceForStudent } from "./audience";

describe("clientFinanceAudienceForStudent", () => {
  it("returns only ids proven to be active Client application accounts", async () => {
    const query = jest.fn().mockResolvedValue({
      rows: [{ user_id: "client-a" }, { user_id: "client-parent" }],
    });

    await expect(
      clientFinanceAudienceForStudent(
        { query } as unknown as DatabaseService,
        "student-a",
      ),
    ).resolves.toEqual(["client-a", "client-parent"]);

    expect(query).toHaveBeenCalledTimes(1);
    expect(query.mock.calls[0][1]).toEqual(["student-a"]);
    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("join app.users recipient");
    expect(sql).toContain("recipient.deleted_at is null");
    expect(sql).toContain("recipient.role = 'client'");
    expect(sql).toContain("recipient.is_app_account = true");
    expect(sql).toContain("app.user_crm_links");
    expect(sql).toContain("account_member.role in ('parent', 'payer')");
  });

  it("does not query or produce a room without a student id", async () => {
    const query = jest.fn();

    await expect(
      clientFinanceAudienceForStudent(
        { query } as unknown as DatabaseService,
        null,
      ),
    ).resolves.toEqual([]);
    expect(query).not.toHaveBeenCalled();
  });
});

describe("audienceForLesson", () => {
  it("uses the frozen group snapshot and only active application accounts", async () => {
    const query = jest.fn().mockResolvedValue({
      rows: [{ user_id: "client-a" }, { user_id: "teacher-a" }],
    });

    await expect(
      audienceForLesson(
        { query } as unknown as DatabaseService,
        {
          id: "lesson-a",
          student_id: null,
          group_id: "group-a",
          lead_id: null,
          teacher_id: "teacher-a",
        },
      ),
    ).resolves.toEqual(["client-a", "teacher-a"]);

    expect(query.mock.calls[0][1]).toEqual([
      null,
      null,
      "group-a",
      "teacher-a",
      "lesson-a",
    ]);
    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("app.lesson_snapshot_participants");
    expect(sql).toContain("not exists");
    expect(sql).toContain("join app.users recipient");
    expect(sql).toContain("recipient.deleted_at is null");
    expect(sql).toContain("recipient.is_app_account = true");
  });
});
