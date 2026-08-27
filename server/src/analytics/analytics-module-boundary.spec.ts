import { MODULE_METADATA } from "@nestjs/common/constants";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import * as ts from "typescript";
import { CrmAnalyticsSupportModule } from "../crm/crm-analytics-support.module";
import { CrmPolicy } from "../crm/crm.policy";
import { CrmModule } from "../crm/crm.module";
import { DashboardService } from "../crm/dashboard.service";
import { AnalyticsModule } from "./analytics.module";

function metadata<T>(key: string, target: object): T[] {
  return (Reflect.getMetadata(key, target) as T[] | undefined) ?? [];
}

function importsOf(relativePath: string): string[] {
  const path = resolve(__dirname, relativePath);
  const source = ts.createSourceFile(
    path,
    readFileSync(path, "utf8"),
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );

  return source.statements.flatMap((statement) => {
    if (
      ts.isImportDeclaration(statement) &&
      ts.isStringLiteral(statement.moduleSpecifier)
    ) {
      return [statement.moduleSpecifier.text];
    }
    return [];
  });
}

describe("analytics module boundary", () => {
  it("imports the narrow CRM analytics support module instead of CrmModule", () => {
    const imports = importsOf("analytics.module.ts");

    expect(imports).toContain("../crm/crm-analytics-support.module");
    expect(imports).not.toContain("../crm/crm.module");
  });

  it("keeps CrmModule on the same narrow support boundary", () => {
    expect(importsOf("../crm/crm.module.ts")).toContain(
      "./crm-analytics-support.module",
    );
  });

  it.each([CrmPolicy, DashboardService])(
    "%p is registered and exported only by the support module",
    (provider) => {
      const modules = [
        CrmAnalyticsSupportModule,
        CrmModule,
        AnalyticsModule,
      ];
      const owners = modules.filter((module) =>
        metadata(MODULE_METADATA.PROVIDERS, module).includes(provider),
      );

      expect(owners).toEqual([CrmAnalyticsSupportModule]);
      expect(
        metadata(MODULE_METADATA.EXPORTS, CrmAnalyticsSupportModule),
      ).toContain(provider);
    },
  );

  it("re-exports the support module through the CRM public boundary", () => {
    expect(metadata(MODULE_METADATA.IMPORTS, CrmModule)).toContain(
      CrmAnalyticsSupportModule,
    );
    expect(metadata(MODULE_METADATA.EXPORTS, CrmModule)).toContain(
      CrmAnalyticsSupportModule,
    );
  });
});
