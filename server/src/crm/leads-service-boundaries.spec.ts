import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

describe("lead service ownership boundaries", () => {
  const crmRoot = resolve(process.cwd(), "src", "crm");
  const owners = [
    "lead-model.ts",
    "lead-board-filter.ts",
    "lead-board-assembler.ts",
    "lead-board.service.ts",
    "lead-card.service.ts",
    "lead-directory.service.ts",
    "lead-write.repository.ts",
    "lead-command.service.ts",
  ];

  it("keeps every lead responsibility in a named semantic owner", () => {
    for (const owner of owners) {
      expect(existsSync(resolve(crmRoot, owner))).toBe(true);
    }
  });

  it("keeps LeadsService as a small SQL-free application facade", () => {
    const source = readFileSync(resolve(crmRoot, "leads.service.ts"), "utf8");
    const nloc = source
      .split(/\r?\n/)
      .filter((line) => line.trim() && !line.trim().startsWith("//")).length;

    expect(nloc).toBeLessThanOrEqual(120);
    expect(source).not.toContain("this.database");
    expect(source).not.toContain("app.leads");
    expect(source).not.toContain("database.query");
    expect(source).toContain("LeadBoardService");
    expect(source).toContain("LeadCardService");
    expect(source).toContain("LeadDirectoryService");
    expect(source).toContain("LeadCommandService");
  });
});
