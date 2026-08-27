import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import type { Type } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import * as ts from "typescript";
import { DatabaseService } from "../../db/database.service";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { LessonSettlementService } from "../commerce/lesson-settlement.service";
import { SubscriptionPreviewTokenService } from "../commerce/subscription-preview-token.service";
import { SubscriptionReservationService } from "../commerce/subscription-reservation.service";
import { CrmPolicy } from "../crm.policy";
import { LessonLifecycleRepository } from "./lesson-lifecycle.repository";
import { LessonSeriesCommandService } from "./lesson-series-command.service";
import { SchedulePlanConstraintPreviewService } from "./schedule-plan-constraint-preview.service";
import { SchedulePlanDefinitionService } from "./schedule-plan-definition.service";
import { SchedulePlanEndService } from "./schedule-plan-end.service";
import { SchedulePlanMutationService } from "./schedule-plan-mutation.service";
import { SchedulePlanQueryService } from "./schedule-plan-query.service";
import { SchedulePlanRepository } from "./schedule-plan.repository";
import { SchedulePlanService } from "./schedule-plan.service";
import { ScheduleSeriesMaterializerService } from "./schedule-series-materializer.service";

const readSource = (name: string) =>
  readFileSync(resolve(__dirname, name), "utf8");
const sources = {
  facade: readSource("schedule-plan.service.ts"),
  definition: readSource("schedule-plan-definition.service.ts"),
  overlap: readSource("schedule-plan-overlap-analyzer.ts"),
  query: readSource("schedule-plan-query.service.ts"),
  preview: readSource("schedule-plan-constraint-preview.service.ts"),
  mutation: readSource("schedule-plan-mutation.service.ts"),
  end: readSource("schedule-plan-end.service.ts"),
};
const moduleSource = readFileSync(
  resolve(__dirname, "..", "crm.module.ts"),
  "utf8",
);

const sourceNloc = (source: string) =>
  source
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split(/\r?\n/)
    .filter((line) => {
      const value = line.trim();
      return value.length > 0 && !value.startsWith("//");
    }).length;

const parsedClass = (source: string) => {
  const file = ts.createSourceFile(
    "facade.ts",
    source,
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );
  const classes = file.statements.filter(ts.isClassDeclaration);
  expect(classes).toHaveLength(1);
  return { file, declaration: classes[0]! };
};

const identifierName = (node: ts.Node | undefined) =>
  node && ts.isIdentifier(node) ? node.text : null;
const exactConstructorTypes = (source: string) => {
  const { file, declaration } = parsedClass(source);
  const constructors = declaration.members.filter(ts.isConstructorDeclaration);
  expect(constructors).toHaveLength(1);
  expect(constructors[0]!.body?.statements).toHaveLength(0);
  return constructors[0]!.parameters.map((parameter) =>
    parameter.type?.getText(file),
  );
};
const exactMethodNames = (source: string) =>
  parsedClass(source)
    .declaration.members.filter(ts.isMethodDeclaration)
    .map((method) => identifierName(method.name));

const assertDirectDelegations = (
  source: string,
  contracts: ReadonlyArray<{
    method: string;
    owner: string;
    parameters: readonly string[];
  }>,
) => {
  const { declaration } = parsedClass(source);
  const methods = declaration.members.filter(ts.isMethodDeclaration);
  expect(methods).toHaveLength(contracts.length);
  methods.forEach((method, index) => {
    const contract = contracts[index]!;
    expect(identifierName(method.name)).toBe(contract.method);
    expect(
      method.parameters.map((parameter) => identifierName(parameter.name)),
    ).toEqual(contract.parameters);
    expect(method.body?.statements).toHaveLength(1);
    const statement = method.body!.statements[0]!;
    expect(ts.isReturnStatement(statement)).toBe(true);
    const call = (statement as ts.ReturnStatement).expression;
    expect(call && ts.isCallExpression(call)).toBe(true);
    const expression = (call as ts.CallExpression).expression;
    expect(ts.isPropertyAccessExpression(expression)).toBe(true);
    const ownerAccess = (expression as ts.PropertyAccessExpression).expression;
    expect(ts.isPropertyAccessExpression(ownerAccess)).toBe(true);
    expect((ownerAccess as ts.PropertyAccessExpression).name.text).toBe(
      contract.owner,
    );
    expect((call as ts.CallExpression).arguments.map(identifierName)).toEqual(
      contract.parameters,
    );
  });
};

const callCount = (source: string, expectedName: string) => {
  const file = ts.createSourceFile(
    "owner.ts",
    source,
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );
  let count = 0;
  const visit = (node: ts.Node): void => {
    if (ts.isCallExpression(node)) {
      const expression = node.expression;
      const name = ts.isIdentifier(expression)
        ? expression.text
        : ts.isPropertyAccessExpression(expression)
          ? expression.name.text
          : null;
      if (name === expectedName) count += 1;
    }
    ts.forEachChild(node, visit);
  };
  visit(file);
  return count;
};

const maxCyclomaticComplexity = (fileName: string, source: string) => {
  const file = ts.createSourceFile(
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
        ts.isIfStatement(node) ||
        ts.isForStatement(node) ||
        ts.isForInStatement(node) ||
        ts.isForOfStatement(node) ||
        ts.isWhileStatement(node) ||
        ts.isDoStatement(node) ||
        ts.isCaseClause(node) ||
        ts.isCatchClause(node) ||
        ts.isConditionalExpression(node) ||
        (ts.isBinaryExpression(node) &&
          [
            ts.SyntaxKind.AmpersandAmpersandToken,
            ts.SyntaxKind.BarBarToken,
            ts.SyntaxKind.QuestionQuestionToken,
          ].includes(node.operatorToken.kind))
      ) {
        complexity += 1;
      }
      ts.forEachChild(node, visit);
    };
    ts.forEachChild(root, visit);
    maximum = Math.max(maximum, complexity);
  };
  const visitDeclarations = (node: ts.Node): void => {
    if (
      ts.isMethodDeclaration(node) ||
      ts.isFunctionDeclaration(node) ||
      ts.isArrowFunction(node)
    ) {
      measure(node);
      return;
    }
    ts.forEachChild(node, visitDeclarations);
  };
  ts.forEachChild(file, visitDeclarations);
  return maximum;
};

const importPathFor = (source: string, importedName: string) => {
  const file = ts.createSourceFile(
    "metadata-owner.ts",
    source,
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );
  const declaration = file.statements.find(
    (statement): statement is ts.ImportDeclaration =>
      ts.isImportDeclaration(statement) &&
      statement.importClause?.namedBindings !== undefined &&
      ts.isNamedImports(statement.importClause.namedBindings) &&
      statement.importClause.namedBindings.elements.some(
        (element) => element.name.text === importedName,
      ),
  );
  return declaration && ts.isStringLiteral(declaration.moduleSpecifier)
    ? declaration.moduleSpecifier.text
    : null;
};

const moduleIdentifiers = (propertyName: "providers" | "exports") => {
  const file = ts.createSourceFile(
    "crm.module.ts",
    moduleSource,
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );
  const classNode = file.statements.find(
    (node): node is ts.ClassDeclaration =>
      ts.isClassDeclaration(node) && node.name?.text === "CrmModule",
  );
  const decorator =
    classNode &&
    ts
      .getDecorators(classNode)
      ?.find(
        (item) =>
          ts.isCallExpression(item.expression) &&
          ts.isIdentifier(item.expression.expression) &&
          item.expression.expression.text === "Module",
      );
  const metadata = (decorator!.expression as ts.CallExpression)
    .arguments[0] as ts.ObjectLiteralExpression;
  const property = metadata.properties.find(
    (node): node is ts.PropertyAssignment =>
      ts.isPropertyAssignment(node) &&
      identifierName(node.name) === propertyName,
  )!;
  return (property.initializer as ts.ArrayLiteralExpression).elements.map(
    identifierName,
  );
};

describe("Schedule plan owner boundaries", () => {
  it("preserves runtime DI metadata and resolves the facade through Nest", async () => {
    const ownerDependencies = new Map<Type<unknown>, Type<unknown>[]>([
      [SchedulePlanDefinitionService, [SchedulePlanRepository]],
      [SchedulePlanQueryService, [SchedulePlanRepository]],
      [
        SchedulePlanConstraintPreviewService,
        [
          CrmPolicy,
          DatabaseService,
          SchedulePlanDefinitionService,
          LessonSeriesCommandService,
          LessonSettlementService,
        ],
      ],
      [
        SchedulePlanMutationService,
        [
          PlatformIntegrityService,
          CrmPolicy,
          SchedulePlanRepository,
          LessonSeriesCommandService,
          ScheduleSeriesMaterializerService,
          LessonSettlementService,
          SchedulePlanDefinitionService,
        ],
      ],
      [
        SchedulePlanEndService,
        [
          PlatformIntegrityService,
          CrmPolicy,
          SchedulePlanRepository,
          DatabaseService,
          SubscriptionPreviewTokenService,
          LessonLifecycleRepository,
          SubscriptionReservationService,
          SchedulePlanDefinitionService,
        ],
      ],
      [
        SchedulePlanService,
        [
          SchedulePlanQueryService,
          SchedulePlanConstraintPreviewService,
          SchedulePlanMutationService,
          SchedulePlanEndService,
        ],
      ],
    ]);
    const owners = [...ownerDependencies.keys()];
    for (const [owner, dependencies] of ownerDependencies) {
      expect(Reflect.getMetadata("design:paramtypes", owner)).toEqual(
        dependencies,
      );
    }

    const moduleRef = await Test.createTestingModule({
      providers: [
        ...owners,
        SchedulePlanRepository,
        CrmPolicy,
        DatabaseService,
        PlatformIntegrityService,
        LessonSettlementService,
        SubscriptionPreviewTokenService,
        SubscriptionReservationService,
        LessonLifecycleRepository,
        LessonSeriesCommandService,
        ScheduleSeriesMaterializerService,
      ],
    })
      .overrideProvider(SchedulePlanRepository)
      .useValue({})
      .overrideProvider(CrmPolicy)
      .useValue({})
      .overrideProvider(DatabaseService)
      .useValue({})
      .overrideProvider(PlatformIntegrityService)
      .useValue({})
      .overrideProvider(LessonSettlementService)
      .useValue({})
      .overrideProvider(SubscriptionPreviewTokenService)
      .useValue({})
      .overrideProvider(SubscriptionReservationService)
      .useValue({})
      .overrideProvider(LessonLifecycleRepository)
      .useValue({})
      .overrideProvider(LessonSeriesCommandService)
      .useValue({})
      .overrideProvider(ScheduleSeriesMaterializerService)
      .useValue({})
      .compile();
    expect(moduleRef.get(SchedulePlanService)).toBeInstanceOf(
      SchedulePlanService,
    );
    await moduleRef.close();
  });

  it("keeps the facade as eight direct controller-facing delegations", () => {
    expect(sourceNloc(sources.facade)).toBeLessThanOrEqual(150);
    expect(exactConstructorTypes(sources.facade)).toEqual([
      "SchedulePlanQueryService",
      "SchedulePlanConstraintPreviewService",
      "SchedulePlanMutationService",
      "SchedulePlanEndService",
    ]);
    expect(exactMethodNames(sources.facade)).toEqual([
      "list",
      "previewConstraints",
      "previewUpdateConstraints",
      "previewEnd",
      "end",
      "tray",
      "create",
      "update",
    ]);
    assertDirectDelegations(sources.facade, [
      { method: "list", owner: "queries", parameters: ["actor", "query"] },
      {
        method: "previewConstraints",
        owner: "previews",
        parameters: ["actor", "dto"],
      },
      {
        method: "previewUpdateConstraints",
        owner: "previews",
        parameters: ["actor", "planId", "dto"],
      },
      {
        method: "previewEnd",
        owner: "ending",
        parameters: ["actor", "planId", "dto"],
      },
      {
        method: "end",
        owner: "ending",
        parameters: ["actor", "planId", "dto", "metadata"],
      },
      {
        method: "tray",
        owner: "queries",
        parameters: ["actor", "planId", "query"],
      },
      {
        method: "create",
        owner: "mutations",
        parameters: ["actor", "dto", "metadata"],
      },
      {
        method: "update",
        owner: "mutations",
        parameters: ["actor", "planId", "dto", "metadata"],
      },
    ]);
    expect(sources.facade).not.toMatch(
      /DatabaseService|PlatformIntegrityService|SchedulePlanRepository|\.transaction\s*\(|executeVersionedMutation|select\s|insert\s|update\s/iu,
    );
  });

  it("keeps persistence and transaction ownership singular", () => {
    expect(callCount(sources.preview, "transaction")).toBe(2);
    expect(callCount(sources.end, "transaction")).toBe(1);
    expect(callCount(sources.mutation, "executeVersionedMutation")).toBe(2);
    expect(callCount(sources.end, "executeVersionedMutation")).toBe(1);
  });

  it("keeps every extracted production owner bounded", () => {
    for (const [name, source] of Object.entries(sources)) {
      expect(sourceNloc(source)).toBeLessThanOrEqual(500);
      const ccn = maxCyclomaticComplexity(name, source);
      if (ccn > 10) throw new Error(`${name} max CCN is ${ccn}`);
      expect(source).not.toMatch(/LessonMutationMetadata/);
    }
  });

  it("uses only the neutral lesson command metadata contract", () => {
    for (const source of [sources.facade, sources.mutation, sources.end]) {
      expect(importPathFor(source, "LessonCommandMetadata")).toBe(
        "./lesson-command-metadata",
      );
    }
    expect(Object.values(sources).join("\n")).not.toMatch(
      /LessonMutationMetadata/,
    );
  });

  it("registers extracted owners privately without changing CRM exports", () => {
    const providers = moduleIdentifiers("providers");
    const exports = moduleIdentifiers("exports");
    for (const owner of [
      "SchedulePlanDefinitionService",
      "SchedulePlanQueryService",
      "SchedulePlanConstraintPreviewService",
      "SchedulePlanMutationService",
      "SchedulePlanEndService",
    ]) {
      expect(providers.filter((provider) => provider === owner)).toHaveLength(
        1,
      );
      expect(exports).not.toContain(owner);
    }
    expect(exports).toEqual([
      "CrmPolicy",
      "DashboardService",
      "ClientReferenceService",
      "ClientWriteValidator",
      "LEAD_INTAKE_PORT",
      "LESSON_SETTLEMENT_PORT",
      "LessonCompletionWorker",
    ]);
  });
});
