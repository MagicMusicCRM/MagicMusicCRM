import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

describe("CRM configuration contract boundary", () => {
  it("keeps settlement catalog types outside the configuration service", () => {
    const crmRoot = join(process.cwd(), "src", "crm");
    const contractPath = join(crmRoot, "crm-configuration.contracts.ts");

    expect(existsSync(contractPath)).toBe(true);
    if (!existsSync(contractPath)) return;

    const contracts = readFileSync(contractPath, "utf8");
    const service = readFileSync(
      join(crmRoot, "crm-configuration.service.ts"),
      "utf8",
    );
    const settlementRepository = readFileSync(
      join(crmRoot, "commerce", "lesson-settlement.repository.ts"),
      "utf8",
    );

    expect(contracts).toContain("export interface LessonSettlementTypeConfig");
    expect(contracts).toContain(
      "export interface TeacherCompensationRuleConfig",
    );
    expect(service).toMatch(
      /from ["']\.\/crm-configuration\.contracts["'];/,
    );
    expect(settlementRepository).toMatch(
      /import type \{[\s\S]*LessonSettlementTypeConfig[\s\S]*TeacherCompensationRuleConfig[\s\S]*\} from ["']\.\.\/crm-configuration\.contracts["'];/,
    );
    expect(settlementRepository).not.toMatch(
      /from ["']\.\.\/crm-configuration\.service["'];/,
    );
  });
});
