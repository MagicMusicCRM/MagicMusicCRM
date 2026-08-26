import { readFileSync, readdirSync } from "node:fs";
import { basename, resolve } from "node:path";
import * as ts from "typescript";

const studentsDirectory = __dirname;
const crmDirectory = resolve(studentsDirectory, "..");

const readSource = (path: string) => readFileSync(path, "utf8");

const facade = readSource(resolve(crmDirectory, "crm.service.ts"));
const crmModule = readSource(resolve(crmDirectory, "crm.module.ts"));
const executor = readSource(
  resolve(studentsDirectory, "student-mutation.executor.ts"),
);
const command = readSource(
  resolve(studentsDirectory, "student-command.service.ts"),
);

const productionBoundaryFiles = [
  resolve(crmDirectory, "crm.service.ts"),
  ...readdirSync(studentsDirectory)
    .filter((name) => name.endsWith(".ts") && !name.endsWith(".spec.ts"))
    .map((name) => resolve(studentsDirectory, name)),
];

const facadeConstructorContract = [
  { name: "directory", type: "StudentDirectoryService" },
  { name: "summary", type: "StudentSelfSummaryService" },
  { name: "cardTimeline", type: "StudentCardTimelineService" },
  { name: "commands", type: "StudentCommandService" },
] as const;

const facadeMethodContracts = [
  {
    name: "getMySummary",
    owner: "summary",
    parameters: [
      { name: "actor", type: "ActorContext", optional: false },
    ],
  },
  {
    name: "listStudents",
    owner: "directory",
    parameters: [
      { name: "actor", type: "ActorContext", optional: false },
      { name: "query", type: "CrmListQuery", optional: false },
    ],
  },
  {
    name: "searchStudents",
    owner: "directory",
    parameters: [
      { name: "actor", type: "ActorContext", optional: false },
      { name: "query", type: "StudentSearchQuery", optional: false },
    ],
  },
  {
    name: "createStudent",
    owner: "commands",
    parameters: [
      { name: "actor", type: "ActorContext", optional: false },
      { name: "dto", type: "CreateStudentDto", optional: false },
      { name: "validated", type: "ValidatedStudentCreate", optional: true },
    ],
  },
  {
    name: "getStudent",
    owner: "directory",
    parameters: [
      { name: "actor", type: "ActorContext", optional: false },
      { name: "studentId", type: "string", optional: false },
    ],
  },
  {
    name: "getStudentCard",
    owner: "cardTimeline",
    parameters: [
      { name: "actor", type: "ActorContext", optional: false },
      { name: "studentId", type: "string", optional: false },
    ],
  },
  {
    name: "listStudentGroups",
    owner: "directory",
    parameters: [
      { name: "actor", type: "ActorContext", optional: false },
      { name: "studentId", type: "string", optional: false },
      { name: "query", type: "CrmListQuery", optional: false },
    ],
  },
  {
    name: "updateStudent",
    owner: "commands",
    parameters: [
      { name: "actor", type: "ActorContext", optional: false },
      { name: "studentId", type: "string", optional: false },
      { name: "dto", type: "UpdateStudentDto", optional: false },
      { name: "customFields", type: "ValidatedCustomFields", optional: true },
    ],
  },
  {
    name: "inviteStudent",
    owner: "commands",
    parameters: [
      { name: "actor", type: "ActorContext", optional: false },
      { name: "studentId", type: "string", optional: false },
    ],
  },
  {
    name: "listGroupStudents",
    owner: "directory",
    parameters: [
      { name: "actor", type: "ActorContext", optional: false },
      { name: "groupId", type: "string", optional: false },
      { name: "query", type: "CrmListQuery", optional: false },
    ],
  },
  {
    name: "deleteStudent",
    owner: "commands",
    parameters: [
      { name: "actor", type: "ActorContext", optional: false },
      { name: "studentId", type: "string", optional: false },
    ],
  },
  {
    name: "returnStudentToLead",
    owner: "commands",
    parameters: [
      { name: "actor", type: "ActorContext", optional: false },
      { name: "studentId", type: "string", optional: false },
    ],
  },
] as const;

const injectableOwners = [
  "StudentDirectoryService",
  "StudentSelfSummaryService",
  "StudentCardTimelineService",
  "StudentMutationExecutor",
  "StudentCommandService",
] as const;

const transactionBoundaryCount = (source: string) =>
  source.match(/\.transaction\s*\(/g)?.length ?? 0;

const sourceNloc = (source: string) => {
  const withoutBlockComments = source.replace(/\/\*[\s\S]*?\*\//g, "");
  return withoutBlockComments
    .split(/\r?\n/)
    .filter((line) => {
      const trimmed = line.trim();
      return trimmed.length > 0 && !trimmed.startsWith("//");
    }).length;
};

const arraySection = (source: string, property: string) => {
  const propertyStart = source.indexOf(`${property}:`);
  if (propertyStart < 0) {
    throw new Error(`Missing ${property} section`);
  }

  const arrayStart = source.indexOf("[", propertyStart);
  let depth = 0;
  for (let index = arrayStart; index < source.length; index += 1) {
    if (source[index] === "[") {
      depth += 1;
    } else if (source[index] === "]") {
      depth -= 1;
      if (depth === 0) {
        return source.slice(arrayStart + 1, index);
      }
    }
  }

  throw new Error(`Unclosed ${property} section`);
};

const modifierKinds = (node: ts.HasModifiers) =>
  ts.canHaveModifiers(node)
    ? (ts.getModifiers(node)?.map((modifier) => modifier.kind) ?? [])
    : [];

const decoratorCount = (node: ts.HasDecorators) =>
  ts.canHaveDecorators(node) ? (ts.getDecorators(node)?.length ?? 0) : 0;

const identifierName = (node: ts.Node | undefined) =>
  node && ts.isIdentifier(node) ? node.text : null;

const typeReferenceName = (node: ts.TypeNode | undefined) =>
  node && ts.isTypeReferenceNode(node) && ts.isIdentifier(node.typeName)
    ? node.typeName.text
    : null;

const assertExactFacadeBoundary = (source: string) => {
  const sourceFile = ts.createSourceFile(
    "crm.service.ts",
    source,
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );

  const facadeClasses = sourceFile.statements.filter(
    (statement): statement is ts.ClassDeclaration =>
      ts.isClassDeclaration(statement) && statement.name?.text === "CrmService",
  );
  expect(facadeClasses).toHaveLength(1);
  const facadeClass = facadeClasses[0]!;

  const constructors = facadeClass.members.filter(ts.isConstructorDeclaration);
  expect(constructors).toHaveLength(1);
  const constructor = constructors[0]!;
  expect(constructor.body?.statements).toHaveLength(0);
  expect(constructor.parameters).toHaveLength(facadeConstructorContract.length);

  constructor.parameters.forEach((parameter, index) => {
    const expected = facadeConstructorContract[index]!;
    expect(identifierName(parameter.name)).toBe(expected.name);
    expect(typeReferenceName(parameter.type)).toBe(expected.type);
    expect(modifierKinds(parameter)).toEqual([
      ts.SyntaxKind.PrivateKeyword,
      ts.SyntaxKind.ReadonlyKeyword,
    ]);
    expect(parameter.dotDotDotToken).toBeUndefined();
    expect(parameter.questionToken).toBeUndefined();
    expect(parameter.initializer).toBeUndefined();
    expect(decoratorCount(parameter)).toBe(0);
  });

  const methods = facadeClass.members.filter(ts.isMethodDeclaration);
  expect(facadeClass.members).toHaveLength(facadeMethodContracts.length + 1);
  expect(methods.map((method) => identifierName(method.name))).toEqual(
    facadeMethodContracts.map((contract) => contract.name),
  );

  methods.forEach((method, index) => {
    const expected = facadeMethodContracts[index]!;
    expect(modifierKinds(method)).toEqual([]);
    expect(decoratorCount(method)).toBe(0);
    expect(method.asteriskToken).toBeUndefined();
    expect(method.questionToken).toBeUndefined();
    expect(method.typeParameters).toBeUndefined();
    expect(method.parameters).toHaveLength(expected.parameters.length);

    method.parameters.forEach((parameter, parameterIndex) => {
      const expectedParameter = expected.parameters[parameterIndex]!;
      expect(identifierName(parameter.name)).toBe(expectedParameter.name);
      expect(parameter.type?.getText(sourceFile)).toBe(expectedParameter.type);
      expect(parameter.questionToken !== undefined).toBe(
        expectedParameter.optional,
      );
      expect(modifierKinds(parameter)).toEqual([]);
      expect(decoratorCount(parameter)).toBe(0);
      expect(parameter.dotDotDotToken).toBeUndefined();
      expect(parameter.initializer).toBeUndefined();
    });

    expect(method.body?.statements).toHaveLength(1);
    const returnStatement = method.body?.statements[0];
    expect(returnStatement && ts.isReturnStatement(returnStatement)).toBe(true);
    if (!returnStatement || !ts.isReturnStatement(returnStatement)) {
      return;
    }

    const call = returnStatement.expression;
    expect(call && ts.isCallExpression(call)).toBe(true);
    if (!call || !ts.isCallExpression(call)) {
      return;
    }

    expect(call.questionDotToken).toBeUndefined();
    expect(call.typeArguments).toBeUndefined();
    expect(call.arguments.map((argument) => identifierName(argument))).toEqual(
      expected.parameters.map((parameter) => parameter.name),
    );
    expect(ts.isPropertyAccessExpression(call.expression)).toBe(true);
    if (!ts.isPropertyAccessExpression(call.expression)) {
      return;
    }

    expect(call.expression.questionDotToken).toBeUndefined();
    expect(call.expression.name.text).toBe(expected.name);
    const ownerAccess = call.expression.expression;
    expect(ts.isPropertyAccessExpression(ownerAccess)).toBe(true);
    if (!ts.isPropertyAccessExpression(ownerAccess)) {
      return;
    }

    expect(ownerAccess.questionDotToken).toBeUndefined();
    expect(ownerAccess.name.text).toBe(expected.owner);
    expect(ownerAccess.expression.kind).toBe(ts.SyntaxKind.ThisKeyword);
  });
};

describe("CRM student service boundaries", () => {
  it("keeps the compatibility facade small and free of persistence", () => {
    const facadeNloc = sourceNloc(facade);

    expect(facadeNloc).toBeLessThanOrEqual(120);
    expect(facade).not.toMatch(
      /database\.|\.transaction\(|select\s|insert\s|update\s|delete\s/i,
    );
  });

  it("keeps the exact four-owner, twelve-delegation facade AST", () => {
    assertExactFacadeBoundary(facade);
  });

  it("keeps both transaction callbacks in the mutation executor only", () => {
    expect(transactionBoundaryCount(executor)).toBe(2);
    expect(command).not.toMatch(/\.transaction\(/);

    const transactionOwners = productionBoundaryFiles
      .filter((path) => transactionBoundaryCount(readSource(path)) > 0)
      .map((path) => basename(path));

    expect(transactionOwners).toEqual(["student-mutation.executor.ts"]);
  });

  it("registers every extracted owner privately in CrmModule", () => {
    const providers = arraySection(crmModule, "providers");
    const exports = arraySection(crmModule, "exports");

    for (const owner of injectableOwners) {
      expect(providers).toMatch(new RegExp(`\\b${owner}\\b`));
      expect(exports).not.toMatch(new RegExp(`\\b${owner}\\b`));
    }
  });
});
