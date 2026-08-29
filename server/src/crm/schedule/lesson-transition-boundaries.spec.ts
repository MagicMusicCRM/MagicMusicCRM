import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import * as ts from "typescript";
import {
  bulkTransitionFingerprint,
  normalizeBulkTransitionItems,
} from "./lesson-transition.rules";

const readSource = (name: string) =>
  readFileSync(resolve(__dirname, name), "utf8");

const sources = {
  facade: readSource("lesson-transition.service.ts"),
  preparation: readSource("lesson-transition-preparation.service.ts"),
  financial: readSource("lesson-transition-financial.service.ts"),
  commit: readSource("lesson-transition-commit.service.ts"),
  preview: readSource("lesson-transition-preview.service.ts"),
  command: readSource("lesson-transition-command.service.ts"),
  bulk: readSource("lesson-bulk-transition.service.ts"),
};
const moduleSource = readFileSync(resolve(__dirname, "..", "crm.module.ts"), "utf8");
const otherNewSources = [
  readSource("lesson-command-metadata.ts"),
  readSource("lesson-transition-group-draft.ts"),
  readSource("lesson-transition.types.ts"),
  readSource("lesson-transition.rules.ts"),
];
const transitionTypesSource = readSource("lesson-transition.types.ts");
const requiredFieldValidatorSource = readSource("lesson-required-field.validator.ts");

const sourceNloc = (source: string) => {
  const withoutBlockComments = source.replace(/\/\*[\s\S]*?\*\//g, "");
  return withoutBlockComments.split(/\r?\n/).filter((line) => {
    const trimmed = line.trim();
    return trimmed.length > 0 && !trimmed.startsWith("//");
  }).length;
};

const calleeIdentity = (expression: ts.LeftHandSideExpression) => {
  if (ts.isIdentifier(expression)) return expression.text;
  if (ts.isPropertyAccessExpression(expression)) return expression.name.text;
  return null;
};

const callCount = (source: string, name: string) => {
  const sourceFile = ts.createSourceFile(
    "boundary-input.ts",
    source,
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );
  let count = 0;
  const visit = (node: ts.Node): void => {
    if (ts.isCallExpression(node) && calleeIdentity(node.expression) === name) {
      count += 1;
    }
    ts.forEachChild(node, visit);
  };
  visit(sourceFile);
  return count;
};

const maxCyclomaticComplexity = (fileName: string, source: string) => {
  const sourceFile = ts.createSourceFile(
    fileName,
    source,
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );
  let maximum = 1;
  const measure = (root: ts.Node) => {
    let complexity = 1;
    const visit = (node: ts.Node): void => {
      if (
        ts.isIfStatement(node) || ts.isForStatement(node) ||
        ts.isForInStatement(node) || ts.isForOfStatement(node) ||
        ts.isWhileStatement(node) || ts.isDoStatement(node) ||
        ts.isCaseClause(node) || ts.isCatchClause(node) ||
        ts.isConditionalExpression(node) ||
        (ts.isBinaryExpression(node) && [
          ts.SyntaxKind.AmpersandAmpersandToken,
          ts.SyntaxKind.BarBarToken,
          ts.SyntaxKind.QuestionQuestionToken,
        ].includes(node.operatorToken.kind))
      ) complexity += 1;
      ts.forEachChild(node, visit);
    };
    ts.forEachChild(root, visit);
    maximum = Math.max(maximum, complexity);
  };
  const visitDeclarations = (node: ts.Node): void => {
    if (
      ts.isMethodDeclaration(node) || ts.isFunctionDeclaration(node) ||
      ts.isArrowFunction(node)
    ) {
      measure(node);
      return;
    }
    ts.forEachChild(node, visitDeclarations);
  };
  ts.forEachChild(sourceFile, visitDeclarations);
  return maximum;
};

const identifierName = (node: ts.Node | undefined) =>
  node && ts.isIdentifier(node) ? node.text : null;

const classDeclaration = (source: string, name: string) => {
  const sourceFile = ts.createSourceFile(
    `${name}.ts`,
    source,
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );
  const declaration = sourceFile.statements.find(
    (statement): statement is ts.ClassDeclaration =>
      ts.isClassDeclaration(statement) && statement.name?.text === name,
  );
  if (!declaration) throw new Error(`Missing ${name}`);
  return declaration;
};

const moduleMetadataIdentifiers = (propertyName: "providers" | "exports") => {
  const sourceFile = ts.createSourceFile(
    "crm.module.ts",
    moduleSource,
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );
  const moduleClass = sourceFile.statements.find(
    (statement): statement is ts.ClassDeclaration =>
      ts.isClassDeclaration(statement) && statement.name?.text === "CrmModule",
  );
  const decorator = moduleClass && ts.getDecorators(moduleClass)?.find((item) => {
    const expression = item.expression;
    return ts.isCallExpression(expression) &&
      ts.isIdentifier(expression.expression) &&
      expression.expression.text === "Module";
  });
  const call = decorator?.expression as ts.CallExpression;
  const metadata = call.arguments[0] as ts.ObjectLiteralExpression;
  const property = metadata.properties.find(
    (item): item is ts.PropertyAssignment =>
      ts.isPropertyAssignment(item) && identifierName(item.name) === propertyName,
  );
  return (property!.initializer as ts.ArrayLiteralExpression).elements.map(
    (element) => identifierName(element),
  );
};

const facadeContracts = [
  { name: "previewReschedule", owner: "previews", target: "previewReschedule", args: ["actor", "lessonId", "dto"] },
  { name: "previewCancel", owner: "previews", target: "previewCancel", args: ["actor", "lessonId", "dto"] },
  { name: "previewSettle", owner: "previews", target: "previewSettle", args: ["actor", "lessonId", "dto"] },
  { name: "reschedule", owner: "commands", target: "reschedule", args: ["actor", "lessonId", "dto", "metadata"] },
  { name: "cancel", owner: "commands", target: "cancel", args: ["actor", "lessonId", "dto", "metadata"] },
  { name: "settle", owner: "commands", target: "settle", args: ["actor", "lessonId", "dto", "metadata"] },
  { name: "previewBulk", owner: "bulkTransitions", target: "previewBulk", args: ["actor", "dto"] },
  { name: "bulk", owner: "bulkTransitions", target: "bulk", args: ["actor", "dto", "metadata"] },
] as const;

const facadeContractErrors = (source: string): string[] => {
  const errors: string[] = [];
  const facade = classDeclaration(source, "LessonTransitionService");
  const constructors = facade.members.filter(ts.isConstructorDeclaration);
  if (constructors.length !== 1) return ["constructor-count"];
  const constructor = constructors[0]!;
  const expectedParameters = [
    ["previews", "LessonTransitionPreviewService"],
    ["commands", "LessonTransitionCommandService"],
    ["bulkTransitions", "LessonBulkTransitionService"],
  ] as const;
  if (constructor.parameters.length !== expectedParameters.length) {
    errors.push("constructor-parameter-count");
  }
  constructor.parameters.forEach((parameter, index) => {
    const expected = expectedParameters[index];
    if (!expected) return;
    if (identifierName(parameter.name) !== expected[0]) {
      errors.push(`constructor-name-${index}`);
    }
    if (parameter.type?.getText() !== expected[1]) {
      errors.push(`constructor-type-${index}`);
    }
    const modifiers = parameter.modifiers?.map((modifier) => modifier.kind) ?? [];
    if (
      modifiers.length !== 2 ||
      !modifiers.includes(ts.SyntaxKind.PrivateKeyword) ||
      !modifiers.includes(ts.SyntaxKind.ReadonlyKeyword)
    ) errors.push(`constructor-modifiers-${index}`);
  });

  const methods = facade.members.filter(ts.isMethodDeclaration);
  const methodNames = methods.map((method) => identifierName(method.name));
  if (JSON.stringify(methodNames) !== JSON.stringify(
    facadeContracts.map(({ name }) => name),
  )) errors.push("method-names");
  facadeContracts.forEach((contract, index) => {
    const method = methods[index];
    if (!method || identifierName(method.name) !== contract.name) return;
    const parameterNames = method.parameters.map((parameter) =>
      identifierName(parameter.name)
    );
    if (JSON.stringify(parameterNames) !== JSON.stringify(contract.args)) {
      errors.push(`parameters-${contract.name}`);
    }
    if (method.body?.statements.length !== 1) {
      errors.push(`statement-count-${contract.name}`);
      return;
    }
    const statement = method.body.statements[0];
    if (!statement || !ts.isReturnStatement(statement)) {
      errors.push(`return-${contract.name}`);
      return;
    }
    const call = statement.expression;
    if (!call || !ts.isCallExpression(call)) {
      errors.push(`call-${contract.name}`);
      return;
    }
    const target = call.expression;
    if (!ts.isPropertyAccessExpression(target) || target.name.text !== contract.target) {
      errors.push(`target-method-${contract.name}`);
      return;
    }
    const owner = target.expression;
    if (
      !ts.isPropertyAccessExpression(owner) ||
      owner.expression.kind !== ts.SyntaxKind.ThisKeyword ||
      owner.name.text !== contract.owner
    ) errors.push(`target-owner-${contract.name}`);
    const argumentNames = call.arguments.map((argument) => identifierName(argument));
    if (JSON.stringify(argumentNames) !== JSON.stringify(contract.args)) {
      errors.push(`arguments-${contract.name}`);
    }
  });
  return errors;
};

describe("Lesson transition owner boundaries", () => {
  it("keeps internal transition contracts independent from transport DTOs", () => {
    expect([
      transitionTypesSource,
      requiredFieldValidatorSource,
      sources.preparation,
      sources.commit,
      readSource("lesson-transition.rules.ts"),
    ].join("\n"))
      .not.toMatch(/\.\.\/dto\//);
  });

  it("keeps the compatibility facade as eight direct delegations", () => {
    expect(sourceNloc(sources.facade)).toBeLessThanOrEqual(130);
    expect(facadeContractErrors(sources.facade)).toEqual([]);
    expect(sources.facade).not.toMatch(
      /DatabaseService|PlatformIntegrityService|\.transaction\s*\(|executeVersionedMutation|select\s|insert\s|update\s/iu,
    );
  });

  it("rejects wrong facade modifiers, target, method, and argument order", () => {
    const mutations = [
      sources.facade.replace(
        "private readonly previews: LessonTransitionPreviewService",
        "public readonly previews: LessonTransitionPreviewService",
      ),
      sources.facade.replace(
        "this.previews.previewCancel(actor, lessonId, dto)",
        "this.commands.previewCancel(actor, lessonId, dto)",
      ),
      sources.facade.replace(
        "this.previews.previewSettle(actor, lessonId, dto)",
        "this.previews.previewCancel(actor, lessonId, dto)",
      ),
      sources.facade.replace(
        "this.commands.reschedule(actor, lessonId, dto, metadata)",
        "this.commands.reschedule(lessonId, actor, dto, metadata)",
      ),
    ];
    for (const mutation of mutations) {
      expect(mutation).not.toBe(sources.facade);
      expect(facadeContractErrors(mutation)).not.toEqual([]);
    }
  });

  it("keeps persistence and mutation ownership singular", () => {
    expect(callCount(sources.preview, "transaction")).toBe(1);
    expect(callCount(sources.bulk, "transaction")).toBe(1);
    expect(callCount(sources.command, "executeVersionedMutation")).toBe(1);
    expect(callCount(sources.bulk, "executeVersionedMutation")).toBe(1);
    for (const [owner, source] of Object.entries(sources)) {
      expect(sourceNloc(source)).toBeLessThanOrEqual(500);
      const maxCcn = maxCyclomaticComplexity("lesson-transition-owner.ts", source);
      if (maxCcn > 10) throw new Error(`${owner} max CCN is ${maxCcn}`);
    }
    for (const source of otherNewSources) {
      expect(sourceNloc(source)).toBeLessThanOrEqual(500);
      expect(maxCyclomaticComplexity("lesson-transition-boundary.ts", source))
        .toBeLessThanOrEqual(10);
    }
    const publicationOwners = [sources.command, sources.bulk];
    expect(publicationOwners.every((source) =>
      source.includes("publishLessonSettlementPostCommit")
    )).toBe(true);
    expect(
      [sources.facade, sources.preparation, sources.financial, sources.commit,
        sources.preview].join("\n"),
    ).not.toMatch(/publishLessonSettlementPostCommit/);
  });

  it("wires six workflow owners privately", () => {
    const owners = [
      "LessonTransitionPreparationService",
      "LessonTransitionFinancialService",
      "LessonTransitionCommitService",
      "LessonTransitionPreviewService",
      "LessonTransitionCommandService",
      "LessonBulkTransitionService",
    ];
    const providers = moduleMetadataIdentifiers("providers");
    const exports = moduleMetadataIdentifiers("exports");
    for (const owner of owners) {
      expect(providers.filter((provider) => provider === owner)).toHaveLength(1);
      expect(exports).not.toContain(owner);
    }
  });

  it("normalizes bulk lesson ids, rejects duplicates, and caps at 500", () => {
    const item = (lessonId: string) => ({
      lessonId,
      operation: "cancel" as const,
      expectedVersion: 1,
      financialDecision: {
        settlementTypeKey: "free_lesson",
        teacherCompensationRuleKey: "none",
      },
    });
    const first = "00000000-0000-4000-8000-000000000001";
    const second = "00000000-0000-4000-8000-000000000002";
    expect(normalizeBulkTransitionItems({
      reasonText: "reason",
      items: [item(second), item(first)],
    }).map(({ lessonId }) => lessonId)).toEqual([first, second]);
    expect(() => normalizeBulkTransitionItems({
      reasonText: "reason",
      items: [item(first), item(first)],
    })).toThrow();
    expect(() => normalizeBulkTransitionItems({
      reasonText: "reason",
      items: Array.from({ length: 501 }, (_, index) =>
        item(`00000000-0000-4000-8000-${String(index).padStart(12, "0")}`)
      ),
    })).toThrow();
  });

  it("builds deterministic bulk fingerprints", () => {
    const dto = { reasonText: " reason ", items: [] };
    const items = [{
      lessonId: "00000000-0000-4000-8000-000000000001",
      operation: "cancel" as const,
      preview: { transitionFingerprint: "fingerprint" },
    }];
    expect(bulkTransitionFingerprint(dto, items)).toBe(
      bulkTransitionFingerprint(dto, items),
    );
  });
});
