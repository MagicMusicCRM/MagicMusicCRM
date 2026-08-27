import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import * as ts from "typescript";

const readSource = (name: string) =>
  readFileSync(resolve(__dirname, name), "utf8");

const facade = readSource("messenger.service.ts");
const systemChats = readSource("messenger-system-chat.service.ts");
const access = readSource("messenger-chat-access.service.ts");
const queries = readSource("messenger-chat-query.service.ts");
const commands = readSource("messenger-chat-command.service.ts");
const delivery = readSource("messenger-message-delivery.service.ts");
const moduleSource = readSource("messenger.module.ts");

const moduleMetadataIdentifiers = (propertyName: "providers" | "exports") => {
  const sourceFile = ts.createSourceFile(
    "messenger.module.ts",
    moduleSource,
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );
  const moduleClass = sourceFile.statements.find(
    (statement): statement is ts.ClassDeclaration =>
      ts.isClassDeclaration(statement) && statement.name?.text === "MessengerModule",
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
  const call = decorator!.expression as ts.CallExpression;
  const metadata = call.arguments[0];
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

const sourceNloc = (source: string) => {
  const withoutBlockComments = source.replace(/\/\*[\s\S]*?\*\//g, "");
  return withoutBlockComments
    .split(/\r?\n/)
    .filter((line) => {
      const trimmed = line.trim();
      return trimmed.length > 0 && !trimmed.startsWith("//");
    }).length;
};

const transactionBoundaryCount = (source: string) =>
  source.match(/\.transaction\s*\(/g)?.length ?? 0;

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

const ownerMappings = [
  ["onModuleInit", "systemChats", "bootstrapAnnouncements", []],
  ["ensureAnnouncementsChat", "systemChats", "ensureAnnouncementsChat", []],
  ["listChats", "queries", "listChats", ["actor", "query"]],
  ["getMessages", "queries", "getMessages", ["actor", "chatId", "query"]],
  ["listChatMembers", "queries", "listChatMembers", ["actor", "chatId"]],
  ["sendMessage", "delivery", "sendMessage", ["actor", "chatId", "dto"]],
  ["createDirectChat", "commands", "createDirectChat", ["actor", "dto"]],
  ["createGroup", "commands", "createGroup", ["actor", "dto"]],
  [
    "updateGroupMembers",
    "commands",
    "updateGroupMembers",
    ["actor", "chatId", "dto"],
  ],
  ["leaveGroup", "commands", "leaveGroup", ["actor", "chatId"]],
  ["getChat", "queries", "getChat", ["actor", "chatId"]],
  ["setChatMute", "commands", "setChatMute", ["actor", "chatId", "dto"]],
] as const;

const findFacadeClass = () => {
  const sourceFile = ts.createSourceFile(
    "messenger.service.ts",
    facade,
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );
  const declaration = sourceFile.statements.find(
    (statement): statement is ts.ClassDeclaration =>
      ts.isClassDeclaration(statement) &&
      statement.name?.text === "MessengerService",
  );
  if (!declaration) throw new Error("Missing MessengerService facade");
  return { sourceFile, declaration };
};

const expectSourceOrder = (source: string, markers: readonly string[]) => {
  let previous = -1;
  for (const marker of markers) {
    const current = source.indexOf(marker, previous + 1);
    expect(current).toBeGreaterThan(previous);
    previous = current;
  }
};

describe("Messenger service boundaries", () => {
  it("wires every semantic owner privately before the compatibility facade", () => {
    const owners = [
      "MessengerChatAccessService",
      "MessengerSystemChatService",
      "MessengerChatQueryService",
      "MessengerChatCommandService",
      "MessengerMessageDeliveryService",
    ];
    const providers = moduleMetadataIdentifiers("providers");
    const exports = moduleMetadataIdentifiers("exports");

    expect(providers.slice(0, owners.length + 1)).toEqual([
      ...owners,
      "MessengerService",
    ]);
    for (const owner of owners) {
      expect(providers.filter((provider) => provider === owner)).toHaveLength(1);
      expect(exports).not.toContain(owner);
    }
    expect(exports).toEqual([
      "MessengerService",
      "MessengerPolicyModule",
      "RealtimeGateway",
    ]);
  });

  it("keeps the compatibility facade small and persistence-free", () => {
    expect(sourceNloc(facade)).toBeLessThanOrEqual(100);
    expect(facade).not.toMatch(
      /DatabaseService|MessengerPolicy|AuditService|RealtimeBus|\.transaction\s*\(|select\s|insert\s|update\s|delete\s/i,
    );
  });

  it("keeps the exact four-owner, twelve-method direct-delegation facade", () => {
    const { sourceFile, declaration } = findFacadeClass();
    const constructors = declaration.members.filter(ts.isConstructorDeclaration);
    expect(constructors).toHaveLength(1);
    const constructor = constructors[0]!;
    expect(constructor.parameters).toHaveLength(4);
    expect(
      constructor.parameters.map((parameter) => identifierName(parameter.name)),
    ).toEqual(["systemChats", "queries", "delivery", "commands"]);
    expect(
      constructor.parameters.map((parameter) => ({
        modifiers: parameter.modifiers?.map((modifier) => modifier.kind),
        type:
          parameter.type && ts.isTypeReferenceNode(parameter.type)
            ? identifierName(parameter.type.typeName)
            : null,
      })),
    ).toEqual([
      {
        modifiers: [
          ts.SyntaxKind.PrivateKeyword,
          ts.SyntaxKind.ReadonlyKeyword,
        ],
        type: "MessengerSystemChatService",
      },
      {
        modifiers: [
          ts.SyntaxKind.PrivateKeyword,
          ts.SyntaxKind.ReadonlyKeyword,
        ],
        type: "MessengerChatQueryService",
      },
      {
        modifiers: [
          ts.SyntaxKind.PrivateKeyword,
          ts.SyntaxKind.ReadonlyKeyword,
        ],
        type: "MessengerMessageDeliveryService",
      },
      {
        modifiers: [
          ts.SyntaxKind.PrivateKeyword,
          ts.SyntaxKind.ReadonlyKeyword,
        ],
        type: "MessengerChatCommandService",
      },
    ]);

    const publicMethods = declaration.members.filter(ts.isMethodDeclaration);
    expect(publicMethods).toHaveLength(12);
    expect(publicMethods.map((method) => identifierName(method.name))).toEqual(
      ownerMappings.map(([name]) => name),
    );

    publicMethods.forEach((method, index) => {
      const [methodName, owner, ownerMethod, argumentNames] =
        ownerMappings[index]!;
      expect(identifierName(method.name)).toBe(methodName);
      expect(method.body?.statements).toHaveLength(1);
      const statement = method.body?.statements[0];
      expect(statement && ts.isReturnStatement(statement)).toBe(true);
      if (!statement || !ts.isReturnStatement(statement)) return;
      const call = statement.expression;
      expect(call && ts.isCallExpression(call)).toBe(true);
      if (!call || !ts.isCallExpression(call)) return;
      expect(call.arguments.map((argument) => identifierName(argument))).toEqual(
        argumentNames,
      );
      expect(ts.isPropertyAccessExpression(call.expression)).toBe(true);
      if (!ts.isPropertyAccessExpression(call.expression)) return;
      expect(call.expression.name.text).toBe(ownerMethod);
      const ownerAccess = call.expression.expression;
      expect(ts.isPropertyAccessExpression(ownerAccess)).toBe(true);
      if (!ts.isPropertyAccessExpression(ownerAccess)) return;
      expect(ownerAccess.name.text).toBe(owner);
      expect(ownerAccess.expression.kind).toBe(ts.SyntaxKind.ThisKeyword);
      expect(method.getSourceFile()).toBe(sourceFile);
    });
  });

  it("keeps owner NLOC and transaction ceilings", () => {
    expect(sourceNloc(systemChats)).toBeLessThanOrEqual(100);
    expect(sourceNloc(access)).toBeLessThanOrEqual(80);
    expect(sourceNloc(queries)).toBeLessThanOrEqual(600);
    expect(sourceNloc(commands)).toBeLessThanOrEqual(400);
    expect(sourceNloc(delivery)).toBeLessThanOrEqual(300);

    expect(transactionBoundaryCount(systemChats)).toBe(1);
    expect(transactionBoundaryCount(delivery)).toBe(1);
    expect(transactionBoundaryCount(commands)).toBe(4);
    expect(transactionBoundaryCount(queries)).toBe(0);
    expect(transactionBoundaryCount(access)).toBe(0);
    expect(
      maxCyclomaticComplexity("messenger-chat-command.service.ts", commands),
    ).toBeLessThanOrEqual(10);
    expect(
      maxCyclomaticComplexity(
        "messenger-message-delivery.service.ts",
        delivery,
      ),
    ).toBeLessThanOrEqual(10);
  });

  it("keeps delivery and group side effects after their transaction commits", () => {
    expectSourceOrder(delivery, [
      "this.access.requireChat",
      "this.policy.assertCanWriteChat",
      "this.policy.assertNotBlacklisted",
      "this.prepareMessagePayload",
      "this.persistMessage",
      "this.leadIntake.autoCreateLeadFromChat",
      "this.realtime.publishAdminInboxEvent",
      "this.fanout.publishMessageEventForAudience",
      "this.fanout.fanoutChatListUpdate",
    ]);

    const groupUpdate = commands.slice(
      commands.indexOf("async updateGroupMembers"),
      commands.indexOf("async leaveGroup"),
    );
    expectSourceOrder(groupUpdate, [
      "this.persistGroupMemberChanges",
      "this.audit.record",
      "this.realtime.publishChatEvent",
      "this.queries.getChat",
      "this.realtime.publishUserEvent",
    ]);
  });
});
