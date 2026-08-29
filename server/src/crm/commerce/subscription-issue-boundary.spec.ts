import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import * as ts from "typescript";

const readSource = (name: string) =>
  readFileSync(resolve(__dirname, name), "utf8");

const facade = readSource("subscription-issue.service.ts");
const termsSource = readSource("subscription-commercial-terms.service.ts");
const purchaseTermsSource = readSource("subscription-purchase-terms.service.ts");
const previewSource = readSource("subscription-purchase-preview.service.ts");
const purchaseSource = readSource("subscription-purchase-command.service.ts");
const purchasePaymentSource = readSource(
  "subscription-purchase-payment.service.ts",
);
const purchasePersistenceSource = readSource(
  "subscription-purchase-persistence.service.ts",
);
const grantSource = readSource("subscription-grant-command.service.ts");
const resultSource = readSource("subscription-issue-result.service.ts");
const contractsSource = readSource("subscription-issue.contracts.ts");
const repositorySource = readSource("subscription-issue.repository.ts");
const moduleSource = readFileSync(resolve(__dirname, "..", "crm.module.ts"), "utf8");
const subscriptionsSource = readFileSync(
  resolve(__dirname, "..", "subscriptions.service.ts"),
  "utf8",
);

const sourceNloc = (source: string) => {
  const withoutBlockComments = source.replace(/\/\*[\s\S]*?\*\//g, "");
  return withoutBlockComments
    .split(/\r?\n/)
    .filter((line) => {
      const trimmed = line.trim();
      return trimmed.length > 0 && !trimmed.startsWith("//");
    }).length;
};

const versionedMutationCount = (source: string) => {
  const sourceFile = ts.createSourceFile(
    "mutation-guard-input.ts",
    source,
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );
  let count = 0;
  const visit = (node: ts.Node): void => {
    if (
      ts.isCallExpression(node) &&
      calleeIdentity(node.expression) === "executeVersionedMutation"
    ) {
      count += 1;
    }
    ts.forEachChild(node, visit);
  };
  visit(sourceFile);
  return count;
};

const calleeIdentity = (expression: ts.LeftHandSideExpression) => {
  if (ts.isIdentifier(expression)) return expression.text;
  if (ts.isPropertyAccessExpression(expression)) return expression.name.text;
  return null;
};

const identifierName = (node: ts.Node | undefined) =>
  node && ts.isIdentifier(node) ? node.text : null;

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

const assertInOrder = (source: string, markers: readonly string[]) => {
  let previous = -1;
  for (const marker of markers) {
    const current = source.indexOf(marker, previous + 1);
    expect(current).toBeGreaterThan(previous);
    previous = current;
  }
};

const executionEvents = (sourceFile: ts.SourceFile, body: ts.Node) => {
  const events: Array<{ position: number; value: string }> = [];
  const visit = (node: ts.Node): void => {
    if (ts.isCallExpression(node)) {
      const identity = calleeIdentity(node.expression);
      if (identity) {
        events.push({ position: node.getStart(sourceFile), value: `call:${identity}` });
      }
    }
    if (
      ts.isBinaryExpression(node) &&
      node.operatorToken.kind === ts.SyntaxKind.EqualsToken &&
      node.left.getText(sourceFile) === "audit.afterRef"
    ) {
      events.push({ position: node.getStart(sourceFile), value: "assign:audit.afterRef" });
    }
    ts.forEachChild(node, visit);
  };
  visit(body);
  return events
    .sort((left, right) => left.position - right.position)
    .map(({ value }) => value);
};

const mutationEvents = (source: string) => {
  const sourceFile = ts.createSourceFile(
    "mutation-owner.ts",
    source,
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );
  const callbacks: ts.ConciseBody[] = [];
  const visit = (node: ts.Node): void => {
    if (
      ts.isCallExpression(node) &&
      calleeIdentity(node.expression) === "executeVersionedMutation"
    ) {
      const config = node.arguments[0];
      if (config && ts.isObjectLiteralExpression(config)) {
        const mutate = config.properties.find(
          (property): property is ts.PropertyAssignment =>
            ts.isPropertyAssignment(property) &&
            identifierName(property.name) === "mutate",
        );
        if (
          mutate &&
          (ts.isArrowFunction(mutate.initializer) ||
            ts.isFunctionExpression(mutate.initializer))
        ) {
          callbacks.push(mutate.initializer.body);
        }
      }
    }
    ts.forEachChild(node, visit);
  };
  visit(sourceFile);
  expect(callbacks).toHaveLength(1);
  return executionEvents(sourceFile, callbacks[0]!);
};

const methodContract = (source: string, className: string, methodName: string) => {
  const sourceFile = ts.createSourceFile(
    `${className}.ts`,
    source,
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );
  const owner = sourceFile.statements.find(
    (statement): statement is ts.ClassDeclaration =>
      ts.isClassDeclaration(statement) && statement.name?.text === className,
  );
  const method = owner?.members.find(
    (member): member is ts.MethodDeclaration =>
      ts.isMethodDeclaration(member) && identifierName(member.name) === methodName,
  );
  expect(method?.body).toBeDefined();
  return {
    events: executionEvents(sourceFile, method!.body!),
    parameterTypes: method!.parameters.map((parameter) =>
      parameter.type?.getText(sourceFile),
    ),
  };
};

const expectSubsequence = (actual: readonly string[], expected: readonly string[]) => {
  let cursor = 0;
  for (const event of actual) {
    if (event === expected[cursor]) cursor += 1;
  }
  expect(actual).toEqual(expect.arrayContaining(expected));
  expect(cursor).toBe(expected.length);
};

const facadeContracts = [
  { method: "previewPurchase", owner: "preview" },
  { method: "purchase", owner: "purchaseCommand" },
  { method: "issue", owner: "grantCommand" },
] as const;

describe("subscription issue owner boundaries", () => {
  it("keeps shared contracts independent from persistence", () => {
    expect(contractsSource).not.toMatch(
      /from ["']\.\/subscription-issue\.repository["']/,
    );
    expect(repositorySource).toMatch(
      /from ["']\.\/subscription-issue\.contracts["']/,
    );
  });

  it("wires every subscription issue owner privately and retains the facade pair", () => {
    const owners = [
      "SubscriptionPurchaseTermsService",
      "SubscriptionCommercialTermsService",
      "SubscriptionPurchasePreviewService",
      "SubscriptionPurchasePaymentService",
      "SubscriptionPurchasePersistenceService",
      "SubscriptionPurchaseCommandService",
      "SubscriptionGrantCommandService",
      "SubscriptionIssueResultService",
    ];
    const providers = moduleMetadataIdentifiers("providers");
    const exports = moduleMetadataIdentifiers("exports");
    const repositoryIndex = providers.indexOf("SubscriptionIssueRepository");

    expect(providers.slice(repositoryIndex - owners.length, repositoryIndex)).toEqual(owners);
    expect(repositoryIndex).toBeGreaterThanOrEqual(owners.length);
    for (const owner of owners) {
      expect(providers.filter((provider) => provider === owner)).toHaveLength(1);
      expect(exports).not.toContain(owner);
    }
    expect(providers.filter((provider) => provider === "SubscriptionIssueRepository")).toHaveLength(1);
    expect(providers.filter((provider) => provider === "SubscriptionIssueService")).toHaveLength(1);
    expect(exports).not.toContain("SubscriptionIssueRepository");
    expect(exports).not.toContain("SubscriptionIssueService");
  });

  it("counts typed and untyped mutation calls but ignores source text", () => {
    expect(
      versionedMutationCount("integrity.executeVersionedMutation({});"),
    ).toBe(1);
    expect(
      versionedMutationCount(
        "integrity.executeVersionedMutation<Result>({});",
      ),
    ).toBe(1);
    expect(
      versionedMutationCount("integrity?.executeVersionedMutation?.({});"),
    ).toBe(1);
    expect(
      versionedMutationCount(`
        // integrity.executeVersionedMutation<Comment>({});
        const text = "integrity.executeVersionedMutation<String>({});";
      `),
    ).toBe(0);
  });

  it("keeps exact direct facade delegations", () => {
    const sourceFile = ts.createSourceFile(
      "subscription-issue.service.ts",
      facade,
      ts.ScriptTarget.Latest,
      true,
      ts.ScriptKind.TS,
    );
    const facadeClass = sourceFile.statements.find(
      (statement): statement is ts.ClassDeclaration =>
        ts.isClassDeclaration(statement) &&
        statement.name?.text === "SubscriptionIssueService",
    );
    expect(facadeClass).toBeDefined();
    const constructor = facadeClass!.members.find(ts.isConstructorDeclaration)!;
    const publicMethods = facadeClass!.members.filter(ts.isMethodDeclaration);

    expect(sourceNloc(facade)).toBeLessThanOrEqual(70);
    expect(constructor.parameters).toHaveLength(3);
    expect(
      constructor.parameters.map((parameter) => ({
        modifiers: parameter.modifiers?.map((modifier) => modifier.kind),
        name: identifierName(parameter.name),
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
        name: "preview",
        type: "SubscriptionPurchasePreviewService",
      },
      {
        modifiers: [
          ts.SyntaxKind.PrivateKeyword,
          ts.SyntaxKind.ReadonlyKeyword,
        ],
        name: "purchaseCommand",
        type: "SubscriptionPurchaseCommandService",
      },
      {
        modifiers: [
          ts.SyntaxKind.PrivateKeyword,
          ts.SyntaxKind.ReadonlyKeyword,
        ],
        name: "grantCommand",
        type: "SubscriptionGrantCommandService",
      },
    ]);
    expect(publicMethods).toHaveLength(3);
    expect(publicMethods.map((method) => identifierName(method.name))).toEqual(
      facadeContracts.map(({ method }) => method),
    );

    publicMethods.forEach((method, index) => {
      expect(method.body?.statements).toHaveLength(1);
      const statement = method.body!.statements[0];
      expect(ts.isReturnStatement(statement)).toBe(true);
      const call = (statement as ts.ReturnStatement).expression;
      expect(call && ts.isCallExpression(call)).toBe(true);
      const methodAccess = (call as ts.CallExpression).expression;
      expect(ts.isPropertyAccessExpression(methodAccess)).toBe(true);
      expect((methodAccess as ts.PropertyAccessExpression).name.text).toBe(
        facadeContracts[index]!.method,
      );
      const ownerAccess = (methodAccess as ts.PropertyAccessExpression).expression;
      expect(ts.isPropertyAccessExpression(ownerAccess)).toBe(true);
      expect((ownerAccess as ts.PropertyAccessExpression).name.text).toBe(
        facadeContracts[index]!.owner,
      );
      expect((call as ts.CallExpression).arguments.map(identifierName)).toEqual(
        method.parameters.map((parameter) => identifierName(parameter.name)),
      );
    });
  });

  it("keeps owner size and transaction boundaries", () => {
    expect(sourceNloc(termsSource)).toBeLessThanOrEqual(400);
    expect(sourceNloc(purchaseTermsSource)).toBeLessThanOrEqual(180);
    expect(sourceNloc(previewSource)).toBeLessThanOrEqual(260);
    expect(sourceNloc(purchasePaymentSource)).toBeLessThanOrEqual(160);
    expect(sourceNloc(purchasePersistenceSource)).toBeLessThanOrEqual(180);
    expect(sourceNloc(purchaseSource)).toBeLessThanOrEqual(300);
    expect(sourceNloc(grantSource)).toBeLessThanOrEqual(240);
    expect(sourceNloc(resultSource)).toBeLessThanOrEqual(180);
    expect(versionedMutationCount(purchaseSource)).toBe(1);
    expect(versionedMutationCount(grantSource)).toBe(1);
    expect(versionedMutationCount(subscriptionsSource)).toBe(1);
    const otherIssueSources = [
      facade,
      termsSource,
      purchaseTermsSource,
      previewSource,
      purchasePaymentSource,
      purchasePersistenceSource,
      resultSource,
      contractsSource,
    ].join("\n");
    const allIssueSources = [otherIssueSources, purchaseSource, grantSource].join("\n");
    expect(otherIssueSources).not.toMatch(/executeVersionedMutation/);
    expect(allIssueSources).not.toMatch(/delete\s+from\s+app\./i);
  });

  it("keeps purchase and grant persistence order", () => {
    expectSubsequence(mutationEvents(purchaseSource), [
      "call:decodeBoundToken",
      "call:lockPurchaseStudents",
      "call:findActivePackageForShare",
      "call:readAccountBalance",
      "call:assertPurchaseContext",
      "call:normalizePurchase",
      "call:assertStillCurrent",
      "call:persist",
      "assign:audit.afterRef",
    ]);
    expectSubsequence(mutationEvents(grantSource), [
      "call:lockPurchaseStudents",
      "call:findActivePackageForShare",
      "call:normalizeIssue",
      "call:createIssuedSubscription",
      "call:createInstallments",
      "call:createObligations",
      "call:createIssueLifecycle",
      "assign:audit.afterRef",
    ]);

    const purchasePersistence = methodContract(
      purchasePersistenceSource,
      "SubscriptionPurchasePersistenceService",
      "persist",
    );
    expect(purchasePersistence.parameterTypes[0]).toBe("PoolClient");
    expectSubsequence(purchasePersistence.events, [
      "call:createIssuedSubscription",
      "call:persist",
      "call:createInstallments",
      "call:createObligations",
      "call:createIssueLifecycle",
    ]);

    const paymentPersistence = methodContract(
      purchasePaymentSource,
      "SubscriptionPurchasePaymentService",
      "persist",
    );
    expect(paymentPersistence.parameterTypes[0]).toBe("PoolClient");
    expectSubsequence(paymentPersistence.events, [
      "call:createActualPayment",
      "call:createRecord",
      "call:linkActualPayment",
      "call:appendStatusEvent",
      "call:initializeRecordAggregate",
    ]);

    expect(subscriptionsSource).not.toMatch(
      /\.(?:createIssuedSubscription|createActualPayment|createInstallments|createObligations|createIssueLifecycle|createRecord)\(/,
    );
    expect(subscriptionsSource).toContain("this.purchasePersistence.persist(");
  });

  it("publishes reservations only after non-replayed commits", () => {
    for (const source of [purchaseSource, grantSource]) {
      assertInOrder(source, [
        "executeVersionedMutation<",
        "await this.results.load(",
        "if (!result.replayed)",
        "await this.reservations.publishPostCommit(",
      ]);
    }
  });
});
