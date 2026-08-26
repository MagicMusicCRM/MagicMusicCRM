import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import * as ts from "typescript";

const readSource = (name: string) =>
  readFileSync(resolve(__dirname, name), "utf8");

const facade = readSource("auth.service.ts");
const moduleSource = readSource("auth.module.ts");
const ownerFiles = [
  "auth-rate-limit.service.ts",
  "auth-email-challenge.service.ts",
  "auth-registration.service.ts",
  "auth-login.service.ts",
  "auth-verification.service.ts",
  "auth-password-recovery.service.ts",
  "auth-account.service.ts",
] as const;
const ownerSources = ownerFiles.map((name) => [name, readSource(name)] as const);

const sourceNloc = (source: string) => {
  const withoutBlockComments = source.replace(/\/\*[\s\S]*?\*\//g, "");
  return withoutBlockComments
    .split(/\r?\n/)
    .filter((line) => {
      const trimmed = line.trim();
      return trimmed.length > 0 && !trimmed.startsWith("//");
    }).length;
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
    const visit = (node: ts.Node) => {
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
  const visitDeclarations = (node: ts.Node) => {
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
  ts.forEachChild(sourceFile, visitDeclarations);
  return maximum;
};

const identifierName = (node: ts.Node | undefined) =>
  node && ts.isIdentifier(node) ? node.text : null;

const moduleMetadataIdentifiers = (propertyName: "providers" | "exports") => {
  const sourceFile = ts.createSourceFile(
    "auth.module.ts",
    moduleSource,
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );
  const moduleClass = sourceFile.statements.find(
    (statement): statement is ts.ClassDeclaration =>
      ts.isClassDeclaration(statement) && statement.name?.text === "AuthModule",
  );
  const decorator = moduleClass && ts.getDecorators(moduleClass)?.find((item) => {
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

const facadeContracts = [
  ["signup", "registration", ["dto", "clientIp"]],
  ["login", "loginFlow", ["dto"]],
  ["refresh", "loginFlow", ["refreshToken"]],
  ["logoutAll", "loginFlow", ["actor"]],
  ["requestOtp", "verification", ["emailInput"]],
  ["verifyOtp", "verification", ["emailInput", "code"]],
  ["requestPasswordReset", "recovery", ["emailInput"]],
  ["resetPassword", "recovery", ["token", "password", "clientIp"]],
  ["setPassword", "account", ["actor", "password"]],
  ["changeEmail", "account", ["actor", "emailInput", "currentPassword"]],
  ["listIdentities", "account", ["actor"]],
  ["verifyEmail", "verification", ["token"]],
] as const;

const findFacadeClass = () => {
  const sourceFile = ts.createSourceFile(
    "auth.service.ts",
    facade,
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );
  const declaration = sourceFile.statements.find(
    (statement): statement is ts.ClassDeclaration =>
      ts.isClassDeclaration(statement) && statement.name?.text === "AuthService",
  );
  if (!declaration) throw new Error("Missing AuthService facade");
  return { sourceFile, declaration };
};

describe("AuthService security workflow boundaries", () => {
  it("wires all workflow owners privately and preserves historical exports", () => {
    const owners = [
      "AuthRateLimitService",
      "AuthEmailChallengeService",
      "AuthRegistrationService",
      "AuthLoginService",
      "AuthVerificationService",
      "AuthPasswordRecoveryService",
      "AuthAccountService",
    ];
    const providers = moduleMetadataIdentifiers("providers");
    const exports = moduleMetadataIdentifiers("exports");

    for (const owner of owners) {
      expect(providers.filter((provider) => provider === owner)).toHaveLength(1);
      expect(exports).not.toContain(owner);
    }
    expect(exports).toEqual(["AuthService", "PasswordService", "SessionService"]);
  });

  it("keeps a small persistence-free compatibility facade", () => {
    expect(sourceNloc(facade)).toBeLessThanOrEqual(140);
    expect(facade).not.toMatch(
      /DatabaseService|AuditService|NotificationsService|PasswordService|SessionService|createHash|randomBytes|randomInt|process\.env|select\s|insert\s|update\s/iu,
    );
  });

  it("keeps exact constructor ownership and twelve direct delegations", () => {
    const { sourceFile, declaration } = findFacadeClass();
    const constructors = declaration.members.filter(ts.isConstructorDeclaration);
    expect(constructors).toHaveLength(1);
    const constructor = constructors[0]!;
    expect(constructor.parameters.map((parameter) => identifierName(parameter.name))).toEqual([
      "registration",
      "loginFlow",
      "verification",
      "recovery",
      "account",
    ]);
    expect(
      constructor.parameters.map((parameter) => parameter.type?.getText(sourceFile)),
    ).toEqual([
      "AuthRegistrationService",
      "AuthLoginService",
      "AuthVerificationService",
      "AuthPasswordRecoveryService",
      "AuthAccountService",
    ]);
    for (const parameter of constructor.parameters) {
      expect(ts.getModifiers(parameter)?.map((modifier) => modifier.kind)).toEqual([
        ts.SyntaxKind.PrivateKeyword,
        ts.SyntaxKind.ReadonlyKeyword,
      ]);
    }

    const methods = declaration.members.filter(ts.isMethodDeclaration);
    expect(methods.map((method) => identifierName(method.name))).toEqual(
      facadeContracts.map(([method]) => method),
    );
    methods.forEach((method, index) => {
      expect(method.type).toBeDefined();
      expect(method.body?.statements).toHaveLength(1);
      const statement = method.body!.statements[0];
      expect(ts.isReturnStatement(statement)).toBe(true);
      const call = (statement as ts.ReturnStatement).expression;
      expect(call && ts.isCallExpression(call)).toBe(true);
      const access = (call as ts.CallExpression).expression;
      expect(ts.isPropertyAccessExpression(access)).toBe(true);
      expect((access as ts.PropertyAccessExpression).name.text).toBe(
        facadeContracts[index]![0],
      );
      const owner = (access as ts.PropertyAccessExpression).expression;
      expect(ts.isPropertyAccessExpression(owner)).toBe(true);
      expect((owner as ts.PropertyAccessExpression).name.text).toBe(
        facadeContracts[index]![1],
      );
      expect((owner as ts.PropertyAccessExpression).expression.kind).toBe(
        ts.SyntaxKind.ThisKeyword,
      );
      expect((call as ts.CallExpression).arguments.map(identifierName)).toEqual(
        facadeContracts[index]![2],
      );
    });
  });

  it("keeps every production owner within the permanent size ceiling", () => {
    for (const [name, source] of ownerSources) {
      expect(source).toMatch(/@Injectable\(\)/);
      expect(sourceNloc(source)).toBeLessThanOrEqual(500);
    }
    const login = ownerSources.find(([name]) => name === "auth-login.service.ts")!;
    expect(maxCyclomaticComplexity(login[0], login[1])).toBeLessThanOrEqual(10);
  });
});
