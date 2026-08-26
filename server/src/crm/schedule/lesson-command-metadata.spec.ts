import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import * as ts from "typescript";

const readSource = (name: string) =>
  readFileSync(resolve(__dirname, name), "utf8");

const parse = (source: string) => ts.createSourceFile(
  "metadata-contract.ts",
  source,
  ts.ScriptTarget.Latest,
  true,
  ts.ScriptKind.TS,
);

const identifierName = (node: ts.Node | undefined) =>
  node && ts.isIdentifier(node) ? node.text : null;

const metadataInterfaces = (source: string) =>
  parse(source).statements.filter(
    (statement): statement is ts.InterfaceDeclaration =>
      ts.isInterfaceDeclaration(statement) &&
      statement.name.text === "LessonCommandMetadata",
  ).map((declaration) => ({
    exported: declaration.modifiers?.some(
      (modifier) => modifier.kind === ts.SyntaxKind.ExportKeyword,
    ) === true,
    members: declaration.members.map((member) => {
      const property = ts.isPropertySignature(member);
      return {
        property,
        name: identifierName(member.name),
        optional: property && member.questionToken !== undefined,
        type: property ? member.type?.getText() : undefined,
      };
    }),
  }));

const importDeclarationsFrom = (source: string, moduleName: string) =>
  parse(source).statements.filter(
    (statement): statement is ts.ImportDeclaration =>
      ts.isImportDeclaration(statement) &&
      ts.isStringLiteral(statement.moduleSpecifier) &&
      statement.moduleSpecifier.text === moduleName,
  ).map((declaration) => {
    const clause = declaration.importClause;
    const elements = clause?.namedBindings && ts.isNamedImports(clause.namedBindings)
      ? clause.namedBindings.elements.map((element) => ({
          imported: element.propertyName?.text ?? element.name.text,
          local: element.name.text,
          elementTypeOnly: element.isTypeOnly,
        }))
      : null;
    return { declarationTypeOnly: clause?.isTypeOnly === true, elements };
  });

const exportDeclarationsFrom = (source: string, moduleName: string) =>
  parse(source).statements.filter(
    (statement): statement is ts.ExportDeclaration =>
      ts.isExportDeclaration(statement) &&
      Boolean(statement.moduleSpecifier) &&
      ts.isStringLiteral(statement.moduleSpecifier!) &&
      statement.moduleSpecifier.text === moduleName,
  ).map((declaration) => ({
    declarationTypeOnly: declaration.isTypeOnly,
    elements: declaration.exportClause && ts.isNamedExports(declaration.exportClause)
      ? declaration.exportClause.elements.map((element) => ({
          imported: element.propertyName?.text ?? element.name.text,
          exported: element.name.text,
          elementTypeOnly: element.isTypeOnly,
        }))
      : null,
  }));

const importsMetadataFrom = (source: string, moduleName: string) =>
  importDeclarationsFrom(source, moduleName).some((declaration) =>
    declaration.elements?.some(
      (element) => element.imported === "LessonCommandMetadata",
    ) === true
  );

const consumerMetadataErrors = (source: string): string[] => {
  const errors: string[] = [];
  const neutralImports = importDeclarationsFrom(
    source,
    "./lesson-command-metadata",
  );
  if (neutralImports.length !== 1) errors.push("neutral-import-count");
  if (JSON.stringify(neutralImports[0]) !== JSON.stringify({
    declarationTypeOnly: true,
    elements: [{
      imported: "LessonCommandMetadata",
      local: "LessonCommandMetadata",
      elementTypeOnly: false,
    }],
  })) errors.push("neutral-import-contract");
  if (importsMetadataFrom(source, "./lesson-command.service")) {
    errors.push("legacy-import");
  }
  return errors;
};

const historicalOwnershipErrors = (source: string): string[] => {
  const errors = consumerMetadataErrors(source);
  if (metadataInterfaces(source).length !== 0) errors.push("local-interface");
  const exports = exportDeclarationsFrom(source, "./lesson-command-metadata");
  if (exports.length !== 1) errors.push("neutral-export-count");
  if (JSON.stringify(exports[0]) !== JSON.stringify({
    declarationTypeOnly: true,
    elements: [{
      imported: "LessonCommandMetadata",
      exported: "LessonCommandMetadata",
      elementTypeOnly: false,
    }],
  })) errors.push("neutral-export-contract");
  return errors;
};

const expectedInterface = {
  exported: true,
  members: [
    { property: true, name: "idempotencyKey", optional: false, type: "string" },
    { property: true, name: "requestId", optional: false, type: "string" },
  ],
};

describe("LessonCommandMetadata ownership", () => {
  it("keeps one exact neutral interface", () => {
    expect(metadataInterfaces(readSource("lesson-command-metadata.ts"))).toEqual([
      expectedInterface,
    ]);
  });

  it("keeps exactly one exclusive direct import in all five consumers", () => {
    const consumers = [
      "lesson-command.service.ts",
      "lesson-series-command.service.ts",
      "lesson-settlement-correction.service.ts",
      "lesson-transition.service.ts",
      "schedule-plan.service.ts",
    ];
    for (const name of consumers) {
      expect({ name, errors: consumerMetadataErrors(readSource(name)) }).toEqual({
        name,
        errors: [],
      });
    }
  });

  it("keeps exactly one historical type re-export and no local interface", () => {
    expect(historicalOwnershipErrors(
      readSource("lesson-command.service.ts"),
    )).toEqual([]);
  });

  it("ignores interface, import, and export decoys in comments and strings", () => {
    const decoys = `
      // export interface LessonCommandMetadata { idempotencyKey: string; requestId: string; }
      const importText = 'import type { LessonCommandMetadata } from "./lesson-command-metadata"';
      const exportText = 'export type { LessonCommandMetadata } from "./lesson-command-metadata"';
    `;
    expect(metadataInterfaces(decoys)).toEqual([]);
    expect(importDeclarationsFrom(decoys, "./lesson-command-metadata")).toEqual([]);
    expect(exportDeclarationsFrom(decoys, "./lesson-command-metadata")).toEqual([]);
  });

  it("rejects legacy imports, aliases, and duplicate ownership", () => {
    const validImport = `
      import type { LessonCommandMetadata } from "./lesson-command-metadata";
    `;
    expect(consumerMetadataErrors(`${validImport}
      import type { LessonCommandMetadata } from "./lesson-command.service";
    `)).toContain("legacy-import");
    expect(consumerMetadataErrors(`
      import type { LessonCommandMetadata as Metadata } from "./lesson-command-metadata";
    `)).toContain("neutral-import-contract");
    expect(consumerMetadataErrors(`${validImport}${validImport}`)).toContain(
      "neutral-import-count",
    );
    expect(metadataInterfaces(`
      export interface LessonCommandMetadata { idempotencyKey: string; requestId: string; }
      export interface LessonCommandMetadata { idempotencyKey: string; requestId: string; }
    `)).not.toEqual([expectedInterface]);
    expect(historicalOwnershipErrors(`${validImport}
      export type { LessonCommandMetadata } from "./lesson-command-metadata";
      export type { LessonCommandMetadata } from "./lesson-command-metadata";
      interface LessonCommandMetadata { idempotencyKey: string; requestId: string; }
    `)).toEqual(expect.arrayContaining([
      "local-interface",
      "neutral-export-count",
    ]));
  });
});
