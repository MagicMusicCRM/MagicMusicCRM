import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import * as ts from "typescript";

const readSource = (name: string) =>
  readFileSync(resolve(__dirname, name), "utf8");

const facade = readSource("profile.service.ts");
const profileModule = readSource("profile.module.ts");
const ownerSources = [
  readSource("profile-record.repository.ts"),
  readSource("my-profile.service.ts"),
  readSource("profile-directory.service.ts"),
  readSource("profile-notes.service.ts"),
];

const sourceNloc = (source: string) => {
  const withoutBlockComments = source.replace(/\/\*[\s\S]*?\*\//g, "");
  return withoutBlockComments
    .split(/\r?\n/)
    .filter((line) => {
      const trimmed = line.trim();
      return trimmed.length > 0 && !trimmed.startsWith("//");
    }).length;
};

const identifierName = (node: ts.Node | undefined) =>
  node && ts.isIdentifier(node) ? node.text : null;

const facadeClass = () => {
  const sourceFile = ts.createSourceFile(
    "profile.service.ts",
    facade,
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );
  const declaration = sourceFile.statements.find(
    (statement): statement is ts.ClassDeclaration =>
      ts.isClassDeclaration(statement) && statement.name?.text === "ProfileService",
  );
  if (!declaration) throw new Error("Missing ProfileService facade");
  return declaration;
};

const moduleIdentifiers = (propertyName: "providers" | "exports") => {
  const sourceFile = ts.createSourceFile(
    "profile.module.ts",
    profileModule,
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );
  const declaration = sourceFile.statements.find(
    (statement): statement is ts.ClassDeclaration =>
      ts.isClassDeclaration(statement) && statement.name?.text === "ProfileModule",
  );
  const decorator = declaration && ts.getDecorators(declaration)?.find((item) => {
    const expression = item.expression;
    return (
      ts.isCallExpression(expression) &&
      ts.isIdentifier(expression.expression) &&
      expression.expression.text === "Module"
    );
  });
  expect(decorator).toBeDefined();
  const metadata = (decorator!.expression as ts.CallExpression).arguments[0];
  expect(metadata && ts.isObjectLiteralExpression(metadata)).toBe(true);
  const property = (metadata as ts.ObjectLiteralExpression).properties.find(
    (item): item is ts.PropertyAssignment =>
      ts.isPropertyAssignment(item) && identifierName(item.name) === propertyName,
  );
  expect(property && ts.isArrayLiteralExpression(property.initializer)).toBe(true);
  return (property!.initializer as ts.ArrayLiteralExpression).elements.map(
    (element) => identifierName(element),
  );
};

const exactConstructorTypes = (sourceClass: ts.ClassDeclaration) => {
  const constructor = sourceClass.members.find(ts.isConstructorDeclaration);
  expect(constructor).toBeDefined();
  expect(
    constructor!.parameters.map((parameter) => ({
      type: parameter.type?.getText(),
      private: parameter.modifiers?.some(
        (modifier) => modifier.kind === ts.SyntaxKind.PrivateKeyword,
      ),
      readonly: parameter.modifiers?.some(
        (modifier) => modifier.kind === ts.SyntaxKind.ReadonlyKeyword,
      ),
    })),
  ).toEqual([
    { type: "MyProfileService", private: true, readonly: true },
    { type: "ProfileDirectoryService", private: true, readonly: true },
    { type: "ProfileNotesService", private: true, readonly: true },
  ]);
  return constructor!.parameters.map((parameter) => parameter.type?.getText());
};

const exactMethodNames = (sourceClass: ts.ClassDeclaration) =>
  sourceClass.members.filter(ts.isMethodDeclaration).map((method) =>
    identifierName(method.name),
  );

const delegations = [
  ["getMe", "self", "getMe", ["actor"]],
  ["updateMe", "self", "updateMe", ["actor", "dto"]],
  ["listProfiles", "directory", "listProfiles", ["actor", "query"]],
  ["getProfile", "directory", "getProfile", ["actor", "profileId"]],
  [
    "listProfileLinks",
    "directory",
    "listProfileLinks",
    ["actor", "profileId"],
  ],
  ["listProfileNotes", "notes", "listProfileNotes", ["actor", "profileId"]],
  [
    "createProfileNote",
    "notes",
    "createProfileNote",
    ["actor", "profileId", "body"],
  ],
] as const;

describe("profile owner boundaries", () => {
  it("keeps the facade small, typed, and persistence-free", () => {
    const declaration = facadeClass();
    expect(sourceNloc(facade)).toBeLessThanOrEqual(90);
    expect(exactConstructorTypes(declaration)).toEqual([
      "MyProfileService",
      "ProfileDirectoryService",
      "ProfileNotesService",
    ]);
    expect(exactMethodNames(declaration)).toEqual([
      "getMe",
      "updateMe",
      "listProfiles",
      "getProfile",
      "listProfileLinks",
      "listProfileNotes",
      "createProfileNote",
    ]);
    expect(facade).not.toMatch(
      /DatabaseService|\.transaction\(|select\s|insert\s|update\s|delete\s|AuditService|ProfilePolicy/iu,
    );
  });

  it("keeps every facade method as one exact direct delegation", () => {
    const methods = facadeClass().members.filter(ts.isMethodDeclaration);

    methods.forEach((method, index) => {
      const [methodName, owner, ownerMethod, argumentsList] = delegations[index]!;
      expect(identifierName(method.name)).toBe(methodName);
      expect(method.body?.statements).toHaveLength(1);
      const statement = method.body?.statements[0];
      expect(statement && ts.isReturnStatement(statement)).toBe(true);
      const call = (statement as ts.ReturnStatement).expression;
      expect(call && ts.isCallExpression(call)).toBe(true);
      expect((call as ts.CallExpression).arguments.map(identifierName)).toEqual(
        argumentsList,
      );
      const methodAccess = (call as ts.CallExpression).expression;
      expect(ts.isPropertyAccessExpression(methodAccess)).toBe(true);
      expect((methodAccess as ts.PropertyAccessExpression).name.text).toBe(
        ownerMethod,
      );
      const ownerAccess = (methodAccess as ts.PropertyAccessExpression).expression;
      expect(ts.isPropertyAccessExpression(ownerAccess)).toBe(true);
      expect((ownerAccess as ts.PropertyAccessExpression).name.text).toBe(owner);
      expect((ownerAccess as ts.PropertyAccessExpression).expression.kind).toBe(
        ts.SyntaxKind.ThisKeyword,
      );
    });
  });

  it("registers owners privately and exports only ProfileService", () => {
    expect(moduleIdentifiers("providers")).toEqual(
      expect.arrayContaining([
        "ProfileRecordRepository",
        "MyProfileService",
        "ProfileDirectoryService",
        "ProfileNotesService",
      ]),
    );
    expect(moduleIdentifiers("exports")).toEqual(["ProfileService"]);
  });

  it("keeps every new production owner at or below 500 NLOC", () => {
    for (const source of ownerSources) {
      expect(sourceNloc(source)).toBeLessThanOrEqual(500);
    }
  });
});
