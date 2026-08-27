import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import * as ts from "typescript";

const sourceText = readFileSync(resolve(__dirname, "crm.module.ts"), "utf8");
const source = ts.createSourceFile(
  "crm.module.ts",
  sourceText,
  ts.ScriptTarget.Latest,
  true,
  ts.ScriptKind.TS,
);

const finalOwners = [
  "ExpenseService",
  "FinancePaymentService",
  "StudentAccountTransferService",
  "StudentFinanceQueryService",
  "LessonCommandRepository",
  "LessonConstraintPreviewService",
  "LessonWriteCommandService",
  "LessonPlannedSettlementCommandService",
  "StudentFunnelRepository",
  "StudentFunnelResolverService",
  "StudentFunnelQueryService",
  "StudentFunnelRevisionService",
  "StudentFunnelTransitionPolicy",
] as const;

const moduleDecorator = source.statements
  .filter(ts.isClassDeclaration)
  .flatMap((declaration) => ts.getDecorators(declaration) ?? [])
  .find(
    (decorator) =>
      ts.isCallExpression(decorator.expression) &&
      ts.isIdentifier(decorator.expression.expression) &&
      decorator.expression.expression.text === "Module",
  );

const moduleMetadata = (() => {
  if (!moduleDecorator || !ts.isCallExpression(moduleDecorator.expression)) {
    return undefined;
  }
  const [argument] = moduleDecorator.expression.arguments;
  return argument && ts.isObjectLiteralExpression(argument)
    ? argument
    : undefined;
})();

const identifierArray = (propertyName: string) => {
  const property = moduleMetadata?.properties.find(
    (candidate): candidate is ts.PropertyAssignment =>
      ts.isPropertyAssignment(candidate) &&
      ts.isIdentifier(candidate.name) &&
      candidate.name.text === propertyName,
  );
  if (!property || !ts.isArrayLiteralExpression(property.initializer))
    return [];
  return property.initializer.elements
    .filter(ts.isIdentifier)
    .map((identifier) => identifier.text);
};

describe("final backend owner module boundary", () => {
  it("imports and registers every focused owner exactly once", () => {
    const imports = source.statements
      .filter(ts.isImportDeclaration)
      .flatMap((declaration) =>
        declaration.importClause?.namedBindings &&
        ts.isNamedImports(declaration.importClause.namedBindings)
          ? declaration.importClause.namedBindings.elements.map(
              (element) => element.name.text,
            )
          : [],
      );
    const providers = identifierArray("providers");

    for (const owner of finalOwners) {
      expect(imports.filter((name) => name === owner)).toHaveLength(1);
      expect(providers.filter((name) => name === owner)).toHaveLength(1);
    }
  });

  it("keeps extracted owners private to CrmModule", () => {
    const exports = identifierArray("exports");

    expect(
      exports.filter((name) => finalOwners.includes(name as never)),
    ).toEqual([]);
  });

  it("registers each owner group before its compatibility facade", () => {
    const providers = identifierArray("providers");
    const assertBefore = (owners: readonly string[], facade: string) => {
      const facadeIndex = providers.indexOf(facade);
      expect(facadeIndex).toBeGreaterThan(-1);
      for (const owner of owners) {
        expect(providers.indexOf(owner)).toBeGreaterThan(-1);
        expect(providers.indexOf(owner)).toBeLessThan(facadeIndex);
      }
    };

    assertBefore(finalOwners.slice(0, 4), "FinanceService");
    assertBefore(finalOwners.slice(4, 8), "LessonCommandService");
    assertBefore(finalOwners.slice(8), "StudentFunnelService");
  });
});
