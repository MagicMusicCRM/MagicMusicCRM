import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import * as ts from "typescript";

const crmDirectory = __dirname;
const financeDirectory = resolve(crmDirectory, "finance");
const paths = {
  facade: resolve(crmDirectory, "finance.service.ts"),
  payments: resolve(financeDirectory, "finance-payment.service.ts"),
  queries: resolve(financeDirectory, "student-finance-query.service.ts"),
  transfers: resolve(financeDirectory, "student-account-transfer.service.ts"),
  expenses: resolve(financeDirectory, "expense.service.ts"),
  types: resolve(financeDirectory, "finance.types.ts"),
} as const;

const readSource = (path: string) =>
  existsSync(path) ? readFileSync(path, "utf8") : "";

const sources = Object.fromEntries(
  Object.entries(paths).map(([name, path]) => [name, readSource(path)]),
) as Record<keyof typeof paths, string>;

const parse = (name: string, source: string) =>
  ts.createSourceFile(name, source, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);

const sourceNloc = (source: string) => {
  const withoutBlockComments = source.replace(/\/\*[\s\S]*?\*\//g, "");
  return withoutBlockComments.split(/\r?\n/).filter((line) => {
    const trimmed = line.trim();
    return trimmed.length > 0 && !trimmed.startsWith("//");
  }).length;
};

const identifierName = (node: ts.Node | undefined) =>
  node && ts.isIdentifier(node) ? node.text : null;

const classDeclaration = (name: string, source: string) =>
  parse(`${name}.ts`, source).statements.find(
    (statement): statement is ts.ClassDeclaration =>
      ts.isClassDeclaration(statement) && statement.name?.text === name,
  );

const isPrivateReadonly = (parameter: ts.ParameterDeclaration) => {
  const modifiers = ts
    .getModifiers(parameter)
    ?.map((modifier) => modifier.kind);
  return (
    JSON.stringify(modifiers) ===
    JSON.stringify([
      ts.SyntaxKind.PrivateKeyword,
      ts.SyntaxKind.ReadonlyKeyword,
    ])
  );
};

const callCount = (source: string, methodName: string) => {
  const sourceFile = parse("calls.ts", source);
  let count = 0;
  const visit = (node: ts.Node) => {
    if (
      ts.isCallExpression(node) &&
      ts.isPropertyAccessExpression(node.expression) &&
      node.expression.name.text === methodName
    ) {
      count += 1;
    }
    ts.forEachChild(node, visit);
  };
  visit(sourceFile);
  return count;
};

const templateText = (source: string) => {
  const sourceFile = parse("templates.ts", source);
  const parts: string[] = [];
  const visit = (node: ts.Node) => {
    if (ts.isNoSubstitutionTemplateLiteral(node)) parts.push(node.text);
    if (ts.isTemplateExpression(node)) {
      parts.push(node.head.text, ...node.templateSpans.map((span) => span.literal.text));
    }
    ts.forEachChild(node, visit);
  };
  visit(sourceFile);
  return parts.join("\n");
};

const facadeContracts = [
  ["listRecentPaymentsForStudents", "payments", ["studentIds"]],
  ["listPayments", "payments", ["actor", "query"]],
  ["listExpectedPayments", "queries", ["actor", "query"]],
  ["listStudentBalances", "queries", ["actor", "query"]],
  ["listStudentLedger", "queries", ["actor", "studentId", "query"]],
  [
    "createAccountTransfer",
    "transfers",
    ["actor", "fromStudentId", "dto", "metadata"],
  ],
  ["createPayment", "payments", ["actor", "dto", "metadata"]],
  ["listExpenses", "expenses", ["actor", "query"]],
  ["createExpense", "expenses", ["actor", "dto", "metadata"]],
  ["updateExpense", "expenses", ["actor", "expenseId", "dto", "metadata"]],
  [
    "deleteExpense",
    "expenses",
    ["actor", "expenseId", "expectedVersion", "metadata"],
  ],
] as const;

describe("FinanceService semantic boundary", () => {
  it("provides all four capability owners and the shared row types", () => {
    const missing = Object.entries(paths)
      .filter(([name, path]) => name !== "facade" && !existsSync(path))
      .map(([name]) => name);

    expect(missing).toEqual([]);
  });

  it("keeps an exact four-owner, eleven-delegation compatibility facade", () => {
    const service = classDeclaration("FinanceService", sources.facade);
    expect(service).toBeDefined();
    const constructor = service!.members.find(ts.isConstructorDeclaration);
    expect(constructor).toBeDefined();
    expect(constructor!.parameters.map((parameter) => identifierName(parameter.name)))
      .toEqual(["payments", "queries", "transfers", "expenses"]);
    expect(constructor!.parameters.map((parameter) => parameter.type?.getText()))
      .toEqual([
        "FinancePaymentService",
        "StudentFinanceQueryService",
        "StudentAccountTransferService",
        "ExpenseService",
      ]);
    expect(constructor!.parameters.every(isPrivateReadonly)).toBe(true);

    const methods = service!.members.filter(ts.isMethodDeclaration);
    expect(methods.map((method) => identifierName(method.name))).toEqual(
      facadeContracts.map(([name]) => name),
    );
    methods.forEach((method, index) => {
      const [name, owner, argumentsList] = facadeContracts[index]!;
      expect(method.body?.statements).toHaveLength(1);
      const statement = method.body!.statements[0];
      expect(ts.isReturnStatement(statement)).toBe(true);
      const call = (statement as ts.ReturnStatement).expression;
      expect(call && ts.isCallExpression(call)).toBe(true);
      const access = (call as ts.CallExpression).expression;
      expect(ts.isPropertyAccessExpression(access)).toBe(true);
      expect((access as ts.PropertyAccessExpression).name.text).toBe(name);
      const ownerAccess = (access as ts.PropertyAccessExpression).expression;
      expect(ts.isPropertyAccessExpression(ownerAccess)).toBe(true);
      expect((ownerAccess as ts.PropertyAccessExpression).name.text).toBe(owner);
      expect(
        (call as ts.CallExpression).arguments.map((argument) => identifierName(argument)),
      ).toEqual(argumentsList);
    });

    expect(sourceNloc(sources.facade)).toBeLessThanOrEqual(150);
    expect(sources.facade).not.toMatch(
      /DatabaseService|AuditService|RealtimeBus|\.transaction\s*\(/,
    );
    expect(templateText(sources.facade)).not.toMatch(
      /\bselect\b|\binsert\b|\bupdate\b|\bdelete\b/i,
    );
  });

  it("keeps every capability owner injectable and within its NLOC ceiling", () => {
    const owners = [
      ["FinancePaymentService", sources.payments],
      ["StudentFinanceQueryService", sources.queries],
      ["StudentAccountTransferService", sources.transfers],
      ["ExpenseService", sources.expenses],
    ] as const;

    for (const [name, source] of owners) {
      const declaration = classDeclaration(name, source);
      expect(declaration).toBeDefined();
      const decorators = declaration && ts.getDecorators(declaration);
      expect(
        decorators?.some(
          (decorator) =>
            ts.isCallExpression(decorator.expression) &&
            ts.isIdentifier(decorator.expression.expression) &&
            decorator.expression.expression.text === "Injectable",
        ),
      ).toBe(true);
      expect(sourceNloc(source)).toBeLessThanOrEqual(350);
    }
  });

  it("retains command transaction envelopes and soft expense deletion", () => {
    expect(callCount(sources.payments, "transaction")).toBe(0);
    expect(sources.payments).not.toMatch(/insert into app\.payments/);
    expect(callCount(sources.transfers, "executeVersionedMutation")).toBe(1);
    expect(callCount(sources.queries, "transaction")).toBe(0);
    expect(callCount(sources.expenses, "executeVersionedMutation")).toBe(1);
    expect(sources.expenses).toMatch(/set\s+deleted_at\s*=\s*now\(\)/i);
    expect(sources.expenses).not.toMatch(/delete\s+from\s+app\.expenses/i);
  });
});
