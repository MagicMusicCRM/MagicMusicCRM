import { attachStudentToLead } from "./lead-student-link";

describe("attachStudentToLead", () => {
  it("version-bumps the Student when its lead projection changes", async () => {
    const query = jest.fn().mockResolvedValue({
      rows: [{ id: "student-a" }],
      rowCount: 1,
    });

    await attachStudentToLead(
      { query } as never,
      "student-a",
      "lead-a",
    );

    const sql = String(query.mock.calls[0]?.[0]);
    expect(sql).toContain("version = case");
    expect(sql).toContain("version + 1");
  });
});
