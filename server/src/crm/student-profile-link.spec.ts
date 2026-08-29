import { mergeAndAssignStudentProfile } from "./student-profile-link";

describe("mergeAndAssignStudentProfile", () => {
  it("locks and version-bumps the Student whose card projection changes", async () => {
    const query = jest.fn().mockResolvedValue({
      rows: [{ id: "student-a" }],
      rowCount: 1,
    });

    await expect(
      mergeAndAssignStudentProfile(
        { query } as never,
        "student-a",
        "profile-a",
      ),
    ).resolves.toBe(true);

    const sql = String(query.mock.calls[0]?.[0]);
    expect(sql).toContain("for update");
    expect(sql).toContain("version = student.version + 1");
  });
});
