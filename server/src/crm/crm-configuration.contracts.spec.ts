import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import type { ConfigSnapshot } from "./crm-configuration.contracts";

const contractSnapshot: ConfigSnapshot = {
  categories: [],
  fields: [],
  optionSets: [],
  businessSettings: [],
  lessonSettlementTypes: [],
  teacherCompensationRules: [],
};

describe("CRM configuration contract boundary", () => {
  it("owns the complete configuration snapshot contract", () => {
    expect(Object.keys(contractSnapshot).sort()).toEqual([
      "businessSettings",
      "categories",
      "fields",
      "lessonSettlementTypes",
      "optionSets",
      "teacherCompensationRules",
    ]);
  });

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
    const settlementCatalog = readFileSync(
      join(crmRoot, "commerce", "lesson-settlement-catalog.ts"),
      "utf8",
    );

    expect(contracts).toContain("export interface LessonSettlementTypeConfig");
    expect(contracts).toContain(
      "export interface TeacherCompensationRuleConfig",
    );
    expect(service).toMatch(
      /from ["']\.\/crm-configuration\.contracts["'];/,
    );
    expect(settlementCatalog).toMatch(
      /import type \{[\s\S]*LessonSettlementTypeConfig[\s\S]*TeacherCompensationRuleConfig[\s\S]*\} from ["']\.\.\/crm-configuration\.contracts["'];/,
    );
    expect(settlementCatalog).not.toMatch(
      /from ["']\.\.\/crm-configuration\.service["'];/,
    );
  });
});
