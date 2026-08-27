import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import * as ts from "typescript";

const readSource = (name: string) => {
  const path = resolve(__dirname, name);
  return existsSync(path) ? readFileSync(path, "utf8") : "";
};

const sources = {
  facade: readSource("lesson-command.service.ts"),
  repository: readSource("lesson-command.repository.ts"),
  preview: readSource("lesson-constraint-preview.service.ts"),
  write: readSource("lesson-write-command.service.ts"),
  settlement: readSource("lesson-planned-settlement-command.service.ts"),
  integrity: readSource("lesson-command-integrity.ts"),
} as const;

const parse = (name: string, source: string) =>
  ts.createSourceFile(
    name,
    source,
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );

const identifierName = (node: ts.Node | undefined) =>
  node && ts.isIdentifier(node) ? node.text : null;

const sourceNloc = (source: string) =>
  source
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split(/\r?\n/)
    .filter((line) => {
      const trimmed = line.trim();
      return trimmed.length > 0 && !trimmed.startsWith("//");
    }).length;

const calleeIdentity = (
  expression: ts.LeftHandSideExpression,
): string | null => {
  if (ts.isIdentifier(expression)) return expression.text;
  if (ts.isPropertyAccessExpression(expression)) return expression.name.text;
  if (
    ts.isElementAccessExpression(expression) &&
    expression.argumentExpression &&
    ts.isStringLiteralLike(expression.argumentExpression)
  ) {
    return expression.argumentExpression.text;
  }
  if (ts.isParenthesizedExpression(expression)) {
    return calleeIdentity(expression.expression as ts.LeftHandSideExpression);
  }
  return null;
};

const callCount = (source: string, callee: string) => {
  const file = parse("lesson-command-boundary-input.ts", source);
  let count = 0;
  const visit = (node: ts.Node): void => {
    if (
      ts.isCallExpression(node) &&
      calleeIdentity(node.expression) === callee
    ) {
      count += 1;
    }
    ts.forEachChild(node, visit);
  };
  visit(file);
  return count;
};

const serviceClass = (source: string, name: string) => {
  const file = parse(`${name}.ts`, source);
  return {
    file,
    declaration: file.statements.find(
      (statement): statement is ts.ClassDeclaration =>
        ts.isClassDeclaration(statement) && statement.name?.text === name,
    ),
  };
};

const isInjectable = (declaration: ts.ClassDeclaration | undefined) =>
  Boolean(
    declaration &&
    ts.getDecorators(declaration)?.some((decorator) => {
      const expression = decorator.expression;
      return (
        ts.isCallExpression(expression) &&
        ts.isIdentifier(expression.expression) &&
        expression.expression.text === "Injectable"
      );
    }),
  );

const facadeContracts = [
  {
    method: "previewConstraints",
    owner: "preview",
    parameters: ["actor", "dto"],
  },
  {
    method: "create",
    owner: "write",
    parameters: ["actor", "dto", "metadata"],
  },
  {
    method: "update",
    owner: "write",
    parameters: ["actor", "lessonId", "dto", "metadata"],
  },
  {
    method: "previewSettlementPlan",
    owner: "settlement",
    parameters: ["actor", "lessonId", "dto"],
  },
  {
    method: "updateSettlementPlan",
    owner: "settlement",
    parameters: ["actor", "lessonId", "dto", "metadata"],
  },
] as const;

describe("LessonCommandService semantic boundary", () => {
  it("provides every focused lesson command owner", () => {
    expect(
      Object.entries(sources)
        .filter(([name]) => name !== "facade")
        .filter(([, source]) => source.length === 0)
        .map(([name]) => name),
    ).toEqual([]);
  });

  it("keeps the exact three-owner, five-delegation facade", () => {
    const { file, declaration } = serviceClass(
      sources.facade,
      "LessonCommandService",
    );
    expect(declaration).toBeDefined();
    const constructor = declaration!.members.find(ts.isConstructorDeclaration)!;
    expect(
      constructor.parameters.map((parameter) => ({
        modifiers: ts.getModifiers(parameter)?.map((modifier) => modifier.kind),
        name: identifierName(parameter.name),
        type: parameter.type?.getText(file),
      })),
    ).toEqual([
      {
        modifiers: [
          ts.SyntaxKind.PrivateKeyword,
          ts.SyntaxKind.ReadonlyKeyword,
        ],
        name: "preview",
        type: "LessonConstraintPreviewService",
      },
      {
        modifiers: [
          ts.SyntaxKind.PrivateKeyword,
          ts.SyntaxKind.ReadonlyKeyword,
        ],
        name: "write",
        type: "LessonWriteCommandService",
      },
      {
        modifiers: [
          ts.SyntaxKind.PrivateKeyword,
          ts.SyntaxKind.ReadonlyKeyword,
        ],
        name: "settlement",
        type: "LessonPlannedSettlementCommandService",
      },
    ]);

    const methods = declaration!.members.filter(ts.isMethodDeclaration);
    expect(methods.map((method) => identifierName(method.name))).toEqual(
      facadeContracts.map(({ method }) => method),
    );
    methods.forEach((method, index) => {
      const contract = facadeContracts[index]!;
      expect(method.body?.statements).toHaveLength(1);
      const statement = method.body!.statements[0];
      expect(ts.isReturnStatement(statement)).toBe(true);
      const call = (statement as ts.ReturnStatement).expression;
      expect(call && ts.isCallExpression(call)).toBe(true);
      const methodAccess = (call as ts.CallExpression).expression;
      expect(ts.isPropertyAccessExpression(methodAccess)).toBe(true);
      expect((methodAccess as ts.PropertyAccessExpression).name.text).toBe(
        contract.method,
      );
      const ownerAccess = (methodAccess as ts.PropertyAccessExpression)
        .expression;
      expect(ts.isPropertyAccessExpression(ownerAccess)).toBe(true);
      expect((ownerAccess as ts.PropertyAccessExpression).name.text).toBe(
        contract.owner,
      );
      expect((call as ts.CallExpression).arguments.map(identifierName)).toEqual(
        contract.parameters,
      );
    });
  });

  it("keeps all focused owners injectable and within architecture budgets", () => {
    const owners = [
      ["LessonCommandRepository", sources.repository, 280],
      ["LessonConstraintPreviewService", sources.preview, 100],
      ["LessonWriteCommandService", sources.write, 350],
      ["LessonPlannedSettlementCommandService", sources.settlement, 350],
    ] as const;
    for (const [name, source, nloc] of owners) {
      const { declaration } = serviceClass(source, name);
      expect({ name, injectable: isInjectable(declaration) }).toEqual({
        name,
        injectable: true,
      });
      expect({ name, nloc: sourceNloc(source) }).toEqual({
        name,
        nloc: expect.any(Number),
      });
      expect(sourceNloc(source)).toBeLessThanOrEqual(nloc);
    }
    expect(sourceNloc(sources.facade)).toBeLessThanOrEqual(100);
    expect(sourceNloc(sources.integrity)).toBeLessThanOrEqual(120);
  });

  it("keeps exactly three complete versioned mutation envelopes in command owners", () => {
    expect(callCount(sources.write, "executeVersionedMutation")).toBe(2);
    expect(callCount(sources.settlement, "executeVersionedMutation")).toBe(1);
    expect(
      callCount(
        [
          sources.facade,
          sources.repository,
          sources.preview,
          sources.integrity,
        ].join("\n"),
        "executeVersionedMutation",
      ),
    ).toBe(0);
    expect(sources.facade).not.toMatch(/\.transaction\s*\(|app\.[a-z_]+/i);
    expect(sources.repository).not.toMatch(/\.transaction\s*\(/);
  });

  it("preserves metadata, audit, outbox, lock and savepoint topology", () => {
    expect(sources.facade).toMatch(
      /import type \{ LessonCommandMetadata \} from "\.\/lesson-command-metadata";/,
    );
    expect(sources.facade).toMatch(
      /export type \{ LessonCommandMetadata \} from "\.\/lesson-command-metadata";/,
    );
    expect(sources.write).toMatch(/operation: "schedule\.lesson\.create"/);
    expect(sources.write).toMatch(/operation: "schedule\.lesson\.update"/);
    expect(sources.write).toMatch(/action: "crm\.lesson_created"/);
    expect(sources.write).toMatch(/action: "crm\.lesson_updated"/);
    expect(sources.write).toMatch(/pg_advisory_xact_lock/);
    expect(sources.settlement).toMatch(
      /operation: "schedule\.lesson\.settlement-plan\.update"/,
    );
    expect(sources.settlement).toMatch(
      /action: "crm\.lesson_settlement_plan_updated"/,
    );
    expect(sources.settlement).toMatch(/lesson_planned_settlement_preview/);
    expect(sources.settlement).toMatch(/lesson_planned_financial_preview/);
    expect([sources.write, sources.settlement].join("\n")).toMatch(
      /type: "schedule\.lesson\.changed"/,
    );
  });

  it("counts real mutation calls and ignores comments and strings", () => {
    expect(
      callCount(
        `
          integrity.executeVersionedMutation({});
          integrity.executeVersionedMutation<Result>({});
          integrity?.executeVersionedMutation?.({});
          // integrity.executeVersionedMutation({});
          const decoy = "integrity.executeVersionedMutation({})";
        `,
        "executeVersionedMutation",
      ),
    ).toBe(3);
  });
});
