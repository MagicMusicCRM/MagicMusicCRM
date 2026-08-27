import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import * as ts from "typescript";

const readSource = (name: string) =>
  readFileSync(resolve(__dirname, name), "utf8");

const facade = readSource("subscription-issue.service.ts");
const termsSource = readSource("subscription-commercial-terms.service.ts");
const previewSource = readSource("subscription-purchase-preview.service.ts");
const purchaseSource = readSource("subscription-purchase-command.service.ts");
const grantSource = readSource("subscription-grant-command.service.ts");
const resultSource = readSource("subscription-issue-result.service.ts");
const contractsSource = readSource("subscription-issue.contracts.ts");
const repositorySource = readSource("subscription-issue.repository.ts");
const moduleSource = readFileSync(resolve(__dirname, "..", "crm.module.ts"), "utf8");

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
      "SubscriptionCommercialTermsService",
      "SubscriptionPurchasePreviewService",
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
    expect(sourceNloc(previewSource)).toBeLessThanOrEqual(260);
    expect(sourceNloc(purchaseSource)).toBeLessThanOrEqual(300);
    expect(sourceNloc(grantSource)).toBeLessThanOrEqual(240);
    expect(sourceNloc(resultSource)).toBeLessThanOrEqual(180);
    expect(versionedMutationCount(purchaseSource)).toBe(1);
    expect(versionedMutationCount(grantSource)).toBe(1);
    const otherIssueSources = [
      facade,
      termsSource,
      previewSource,
      resultSource,
      contractsSource,
    ].join("\n");
    const allIssueSources = [otherIssueSources, purchaseSource, grantSource].join("\n");
    expect(otherIssueSources).not.toMatch(/executeVersionedMutation/);
    expect(allIssueSources).not.toMatch(/delete\s+from\s+app\./i);
  });

  it("keeps purchase and grant persistence order", () => {
    assertInOrder(purchaseSource, [
      ".decodeBoundToken(",
      ".lockPurchaseStudents(",
      ".findActivePackageForShare(",
      ".readAccountBalance(",
      ".assertPurchaseContext(",
      ".normalizePurchase(",
      ".assertStillCurrent(",
      ".assertSufficientBalance(",
      ".createIssuedSubscription(",
      ".createInstallments(",
      ".createObligations(",
      ".createIssueLifecycle(",
      "audit.afterRef =",
    ]);
    assertInOrder(grantSource, [
      ".assertStudentsInScope(",
      "executeVersionedMutation<",
      ".lockPurchaseStudents(",
      ".findActivePackageForShare(",
      ".normalizeIssue(",
      ".createIssuedSubscription(",
      ".createInstallments(",
      ".createObligations(",
      ".createIssueLifecycle(",
      "audit.afterRef =",
    ]);
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
