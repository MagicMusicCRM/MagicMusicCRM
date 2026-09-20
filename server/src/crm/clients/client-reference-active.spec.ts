import type { PoolClient } from "pg";
import { assertActiveClientReferences } from "./client-reference.service";

describe("assertActiveClientReferences", () => {
  it("keeps requested ids typed as uuid and compares indexed uuid columns directly", async () => {
    const query = jest.fn().mockResolvedValue({ rows: [] });

    await assertActiveClientReferences({ query } as unknown as PoolClient, [
      { type: "student", id: "00000000-0000-4000-8000-000000000002" },
      { type: "lead", id: "00000000-0000-4000-8000-000000000001" },
      { type: "student", id: "00000000-0000-4000-8000-000000000002" },
    ]);

    const sql = String(query.mock.calls[0]![0]);
    expect(sql).toContain("as item(type text, id uuid)");
    expect(sql).toContain("student.id = requested.id");
    expect(sql).toContain("lead.id = requested.id");
    expect(sql).not.toMatch(/(?:student|lead)\.id::text/);
    expect(JSON.parse(query.mock.calls[0]![1][0])).toEqual([
      { type: "lead", id: "00000000-0000-4000-8000-000000000001" },
      { type: "student", id: "00000000-0000-4000-8000-000000000002" },
    ]);
  });
});
