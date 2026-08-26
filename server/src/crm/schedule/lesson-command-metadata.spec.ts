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

const metadataContract = (source: string) => {
  const declarations = parse(source).statements.filter(
    (statement): statement is ts.InterfaceDeclaration =>
      ts.isInterfaceDeclaration(statement) &&
      statement.name.text === "LessonCommandMetadata",
  );
  if (declarations.length !== 1) return null;
  const declaration = declarations[0]!;
  return {
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
  };
};

const hasDirectTypeImport = (
  source: string,
  importedName: string,
  moduleName: string,
) => parse(source).statements.some((statement) => {
  if (!ts.isImportDeclaration(statement)) return false;
  if (!ts.isStringLiteral(statement.moduleSpecifier)) return false;
  if (statement.moduleSpecifier.text !== moduleName) return false;
  const clause = statement.importClause;
  if (!clause?.isTypeOnly || !clause.namedBindings) return false;
  if (!ts.isNamedImports(clause.namedBindings)) return false;
  return clause.namedBindings.elements.some(
    (element) => element.name.text === importedName && !element.propertyName,
  );
});

const hasHistoricalTypeExport = (source: string) =>
  parse(source).statements.some((statement) => {
    if (!ts.isExportDeclaration(statement) || !statement.isTypeOnly) return false;
    if (!statement.moduleSpecifier || !ts.isStringLiteral(statement.moduleSpecifier)) {
      return false;
    }
    if (statement.moduleSpecifier.text !== "./lesson-command-metadata") return false;
    if (!statement.exportClause || !ts.isNamedExports(statement.exportClause)) {
      return false;
    }
    return statement.exportClause.elements.some(
      (element) => element.name.text === "LessonCommandMetadata" &&
        !element.propertyName,
    );
  });

describe("LessonCommandMetadata ownership", () => {
  it("keeps the neutral interface exported with exactly two required strings", () => {
    expect(metadataContract(readSource("lesson-command-metadata.ts"))).toEqual({
      exported: true,
      members: [
        { property: true, name: "idempotencyKey", optional: false, type: "string" },
        { property: true, name: "requestId", optional: false, type: "string" },
      ],
    });
  });

  it("keeps all five consumers on direct neutral type imports", () => {
    const consumers = [
      "lesson-command.service.ts",
      "lesson-series-command.service.ts",
      "lesson-settlement-correction.service.ts",
      "lesson-transition.service.ts",
      "schedule-plan.service.ts",
    ];
    for (const name of consumers) {
      expect(hasDirectTypeImport(
        readSource(name),
        "LessonCommandMetadata",
        "./lesson-command-metadata",
      )).toBe(true);
    }
  });

  it("retains only the historical type re-export from lesson command", () => {
    const lessonCommand = readSource("lesson-command.service.ts");
    const schedulePlan = readSource("schedule-plan.service.ts");
    expect(hasHistoricalTypeExport(lessonCommand)).toBe(true);
    expect(hasDirectTypeImport(
      schedulePlan,
      "LessonCommandMetadata",
      "./lesson-command.service",
    )).toBe(false);
  });

  it("ignores interface, import, and export decoys in comments and strings", () => {
    const decoys = `
      // export interface LessonCommandMetadata { idempotencyKey: string; requestId: string; }
      const importText = 'import type { LessonCommandMetadata } from "./lesson-command-metadata"';
      const exportText = 'export type { LessonCommandMetadata } from "./lesson-command-metadata"';
    `;
    expect(metadataContract(decoys)).toBeNull();
    expect(hasDirectTypeImport(
      decoys,
      "LessonCommandMetadata",
      "./lesson-command-metadata",
    )).toBe(false);
    expect(hasHistoricalTypeExport(decoys)).toBe(false);
  });

  it("rejects optional or non-string metadata fields", () => {
    expect(metadataContract(`
      export interface LessonCommandMetadata {
        idempotencyKey?: string;
        requestId: number;
      }
    `)).not.toEqual({
      exported: true,
      members: [
        { property: true, name: "idempotencyKey", optional: false, type: "string" },
        { property: true, name: "requestId", optional: false, type: "string" },
      ],
    });
  });
});
