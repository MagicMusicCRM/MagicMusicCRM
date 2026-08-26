import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import * as ts from "typescript";

const payrollDirectory = __dirname;
const crmDirectory = resolve(payrollDirectory, "..");
const readSource = (path: string) => readFileSync(path, "utf8");

const paths = {
  facade: resolve(crmDirectory, "payroll.service.ts"),
  types: resolve(payrollDirectory, "payroll.types.ts"),
  calculator: resolve(payrollDirectory, "payroll-accrual-calculator.ts"),
  repository: resolve(payrollDirectory, "payroll-read.repository.ts"),
  query: resolve(payrollDirectory, "teacher-payroll-query.service.ts"),
  command: resolve(payrollDirectory, "teacher-payroll-command.service.ts"),
  report: resolve(payrollDirectory, "teacher-stats-report.service.ts"),
  csv: resolve(payrollDirectory, "teacher-stats-csv.service.ts"),
} as const;

const sources = Object.fromEntries(
  Object.entries(paths).map(([name, path]) => [name, readSource(path)]),
) as Record<keyof typeof paths, string>;
const facade = sources.facade;
const commandSource = sources.command;
const moduleSource = readSource(resolve(crmDirectory, "crm.module.ts"));
const productionPayrollSource = Object.values(sources).join("\n");
const otherProductionSources = Object.entries(sources)
  .filter(([name]) => name !== "command")
  .map(([, source]) => source)
  .join("\n");

const sourceNloc = (source: string) => {
  const withoutBlockComments = source.replace(/\/\*[\s\S]*?\*\//g, "");
  return withoutBlockComments
    .split(/\r?\n/)
    .filter((line) => {
      const trimmed = line.trim();
      return trimmed.length > 0 && !trimmed.startsWith("//");
    }).length;
};

const versionedMutationCount = (source: string) =>
  source.match(/executeVersionedMutation\s*\(/g)?.length ?? 0;

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

const facadeContracts = [
  ["getTeacherPayroll", "query", ["actor", "teacherId"]],
  ["createTeacherPayout", "commands", ["actor", "teacherId", "dto", "metadata"]],
  ["setTeacherRate", "commands", ["actor", "teacherId", "dto", "metadata"]],
  ["updateTeacherRate", "commands", ["actor", "teacherId", "entryId", "dto", "metadata"]],
  ["deleteTeacherRate", "commands", ["actor", "teacherId", "entryId", "dto", "metadata"]],
  ["updateTeacherPayout", "commands", ["actor", "teacherId", "entryId", "dto", "metadata"]],
  ["deleteTeacherPayout", "commands", ["actor", "teacherId", "entryId", "dto", "metadata"]],
  ["getTeacherStatsReport", "report", ["actor", "query"]],
  ["exportTeacherStatsReport", "csv", ["actor", "query"]],
] as const;

const assertFacadeAst = () => {
  const sourceFile = ts.createSourceFile(
    "payroll.service.ts",
    facade,
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );
  const service = sourceFile.statements.find(
    (statement): statement is ts.ClassDeclaration =>
      ts.isClassDeclaration(statement) && statement.name?.text === "PayrollService",
  );
  expect(service).toBeDefined();
  const constructor = service!.members.find(ts.isConstructorDeclaration)!;
  expect(constructor.parameters).toHaveLength(4);
  expect(
    constructor.parameters.map((parameter) => identifierName(parameter.name)),
  ).toEqual(["query", "commands", "report", "csv"]);
  expect(
    constructor.parameters.map((parameter) => parameter.type?.getText(sourceFile)),
  ).toEqual([
    "TeacherPayrollQueryService",
    "TeacherPayrollCommandService",
    "TeacherStatsReportService",
    "TeacherStatsCsvService",
  ]);
  for (const parameter of constructor.parameters) {
    expect(
      ts.getModifiers(parameter)?.map((modifier) => modifier.kind),
    ).toEqual([ts.SyntaxKind.PrivateKeyword, ts.SyntaxKind.ReadonlyKeyword]);
  }

  const publicMethods = service!.members.filter(ts.isMethodDeclaration);
  expect(publicMethods).toHaveLength(9);
  expect(publicMethods.map((method) => identifierName(method.name))).toEqual(
    facadeContracts.map(([name]) => name),
  );
  publicMethods.forEach((method, index) => {
    const [name, owner, argumentsList] = facadeContracts[index]!;
    expect(method.body?.statements).toHaveLength(1);
    const statement = method.body!.statements[0];
    expect(ts.isReturnStatement(statement)).toBe(true);
    const call = (statement as ts.ReturnStatement).expression;
    expect(call && ts.isCallExpression(call)).toBe(true);
    const expression = (call as ts.CallExpression).expression;
    expect(ts.isPropertyAccessExpression(expression)).toBe(true);
    const methodAccess = expression as ts.PropertyAccessExpression;
    expect(methodAccess.name.text).toBe(name);
    expect(ts.isPropertyAccessExpression(methodAccess.expression)).toBe(true);
    const ownerAccess = methodAccess.expression as ts.PropertyAccessExpression;
    expect(ownerAccess.expression.kind).toBe(ts.SyntaxKind.ThisKeyword);
    expect(ownerAccess.name.text).toBe(owner);
    expect(
      (call as ts.CallExpression).arguments.map((argument) =>
        identifierName(argument),
      ),
    ).toEqual(argumentsList);
  });
};

describe("PayrollService semantic boundary", () => {
  it("wires every payroll owner privately and retains the facade", () => {
    const owners = [
      "PayrollAccrualCalculator",
      "PayrollReadRepository",
      "TeacherPayrollQueryService",
      "TeacherPayrollCommandService",
      "TeacherStatsReportService",
      "TeacherStatsCsvService",
    ];
    const providers = moduleMetadataIdentifiers("providers");
    const exports = moduleMetadataIdentifiers("exports");
    const facadeIndex = providers.indexOf("PayrollService");

    expect(providers.slice(facadeIndex - owners.length, facadeIndex)).toEqual(owners);
    expect(facadeIndex).toBeGreaterThanOrEqual(owners.length);
    for (const owner of owners) {
      expect(providers.filter((provider) => provider === owner)).toHaveLength(1);
      expect(exports).not.toContain(owner);
    }
    expect(providers.filter((provider) => provider === "PayrollService")).toHaveLength(1);
    expect(exports).not.toContain("PayrollService");
  });

  it("keeps the exact four-owner, nine-delegation public facade", () => {
    expect(sourceNloc(facade)).toBeLessThanOrEqual(120);
    assertFacadeAst();
  });

  it("keeps each semantic owner within its permanent NLOC ceiling", () => {
    expect(sourceNloc(sources.types)).toBeLessThanOrEqual(180);
    expect(sourceNloc(sources.calculator)).toBeLessThanOrEqual(260);
    expect(sourceNloc(sources.repository)).toBeLessThanOrEqual(360);
    expect(sourceNloc(sources.query)).toBeLessThanOrEqual(180);
    expect(sourceNloc(sources.command)).toBeLessThanOrEqual(520);
    expect(sourceNloc(sources.report)).toBeLessThanOrEqual(420);
    expect(sourceNloc(sources.csv)).toBeLessThanOrEqual(170);
  });

  it("keeps every integrity mutation in the command owner", () => {
    expect(versionedMutationCount(commandSource)).toBe(5);
    expect(otherProductionSources).not.toMatch(
      /executeVersionedMutation|\.transaction\s*\(/,
    );
  });

  it("rate and payout deletion soft-void history without physical DELETE", () => {
    expect(productionPayrollSource).not.toMatch(
      /delete\s+from\s+app\.(teacher_rates|teacher_payouts)/i,
    );
    expect(commandSource).toMatch(
      /set\s+deleted_at\s*=\s*clock_timestamp\(\)/i,
    );
    expect(commandSource).toMatch(/deleted_by\s*=\s*\$3/i);
  });
});
