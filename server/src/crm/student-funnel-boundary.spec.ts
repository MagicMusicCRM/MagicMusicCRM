import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import * as ts from "typescript";

const crmDirectory = __dirname;
const funnelDirectory = resolve(crmDirectory, "student-funnel");

const paths = {
  facade: resolve(crmDirectory, "student-funnel.service.ts"),
  types: resolve(funnelDirectory, "student-funnel.types.ts"),
  definition: resolve(funnelDirectory, "student-funnel.definition.ts"),
  repository: resolve(funnelDirectory, "student-funnel.repository.ts"),
  resolver: resolve(
    funnelDirectory,
    "student-funnel-resolver.service.ts",
  ),
  query: resolve(funnelDirectory, "student-funnel-query.service.ts"),
  policy: resolve(funnelDirectory, "student-funnel-transition.policy.ts"),
  revisions: resolve(funnelDirectory, "student-funnel-revision.service.ts"),
} as const;

const source = (path: string) =>
  existsSync(path) ? readFileSync(path, "utf8") : "";

const sourceNloc = (value: string) => {
  const withoutBlockComments = value.replace(/\/\*[\s\S]*?\*\//g, "");
  return withoutBlockComments
    .split(/\r?\n/)
    .filter((line) => {
      const trimmed = line.trim();
      return trimmed.length > 0 && !trimmed.startsWith("//");
    }).length;
};

const identifierName = (node: ts.Node | undefined) =>
  node && ts.isIdentifier(node) ? node.text : null;

const modifierKinds = (node: ts.HasModifiers) =>
  ts.canHaveModifiers(node)
    ? (ts.getModifiers(node)?.map((modifier) => modifier.kind) ?? [])
    : [];

const typeName = (node: ts.TypeNode | undefined, file: ts.SourceFile) =>
  node?.getText(file) ?? null;

const facadeContracts = [
  {
    method: "getEffective",
    owner: "queries",
    parameters: ["actor", "branchId", "clientType"],
  },
  {
    method: "listRevisions",
    owner: "queries",
    parameters: ["actor", "branchId", "clientType"],
  },
  { method: "preview", owner: "revisions", parameters: ["actor", "dto"] },
  { method: "publish", owner: "revisions", parameters: ["actor", "dto"] },
  { method: "rollback", owner: "revisions", parameters: ["actor", "dto"] },
  {
    method: "assertCreateStatus",
    owner: "transitions",
    parameters: ["client", "branchId", "status"],
  },
  {
    method: "assertTransition",
    owner: "transitions",
    parameters: ["client", "branchId", "currentStatus", "nextStatus"],
  },
  {
    method: "assertLeadTransition",
    owner: "transitions",
    parameters: [
      "client",
      "branchId",
      "currentStatusId",
      "nextStatusId",
      "hasReason",
    ],
  },
] as const;

const assertFacadeBoundary = (facade: string) => {
  const file = ts.createSourceFile(
    "student-funnel.service.ts",
    facade,
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );
  const service = file.statements.find(
    (statement): statement is ts.ClassDeclaration =>
      ts.isClassDeclaration(statement) &&
      statement.name?.text === "StudentFunnelService",
  );
  expect(service).toBeDefined();

  const constructor = service!.members.find(ts.isConstructorDeclaration);
  expect(constructor).toBeDefined();
  expect(constructor!.body?.statements).toHaveLength(0);
  expect(
    constructor!.parameters.map((parameter) => ({
      modifiers: modifierKinds(parameter),
      name: identifierName(parameter.name),
      type: typeName(parameter.type, file),
    })),
  ).toEqual([
    {
      modifiers: [ts.SyntaxKind.PrivateKeyword, ts.SyntaxKind.ReadonlyKeyword],
      name: "queries",
      type: "StudentFunnelQueryService",
    },
    {
      modifiers: [ts.SyntaxKind.PrivateKeyword, ts.SyntaxKind.ReadonlyKeyword],
      name: "revisions",
      type: "StudentFunnelRevisionService",
    },
    {
      modifiers: [ts.SyntaxKind.PrivateKeyword, ts.SyntaxKind.ReadonlyKeyword],
      name: "transitions",
      type: "StudentFunnelTransitionPolicy",
    },
  ]);

  const methods = service!.members.filter(ts.isMethodDeclaration);
  expect(methods.map((method) => identifierName(method.name))).toEqual(
    facadeContracts.map(({ method }) => method),
  );
  expect(service!.members).toHaveLength(facadeContracts.length + 1);

  methods.forEach((method, index) => {
    const contract = facadeContracts[index]!;
    expect(method.parameters.map((parameter) => identifierName(parameter.name))).toEqual(
      contract.parameters,
    );
    expect(method.body?.statements).toHaveLength(1);
    const statement = method.body!.statements[0];
    expect(ts.isReturnStatement(statement)).toBe(true);
    const call = (statement as ts.ReturnStatement).expression;
    expect(call && ts.isCallExpression(call)).toBe(true);
    const methodAccess = (call as ts.CallExpression).expression;
    expect(ts.isPropertyAccessExpression(methodAccess)).toBe(true);
    expect((methodAccess as ts.PropertyAccessExpression).name.text).toBe(
      contract.method,
    );
    const ownerAccess = (methodAccess as ts.PropertyAccessExpression).expression;
    expect(ts.isPropertyAccessExpression(ownerAccess)).toBe(true);
    expect((ownerAccess as ts.PropertyAccessExpression).name.text).toBe(
      contract.owner,
    );
    expect((call as ts.CallExpression).arguments.map(identifierName)).toEqual(
      contract.parameters,
    );
  });
};

describe("StudentFunnelService semantic boundary", () => {
  it("provides every focused funnel owner", () => {
    for (const path of Object.values(paths).filter(
      (path) => path !== paths.facade,
    )) {
      expect(existsSync(path)).toBe(true);
    }
  });

  it("keeps the exact three-owner, eight-delegation facade", () => {
    const facade = source(paths.facade);
    expect(sourceNloc(facade)).toBeLessThanOrEqual(150);
    expect(facade).not.toMatch(
      /database\.|\.transaction\s*\(|\b(?:select|insert|update|delete)\b/i,
    );
    expect(facade).toMatch(
      /export type \{ FunnelPatch, FunnelSnapshot \} from ["']\.\/student-funnel\/student-funnel\.types["'];/,
    );
    assertFacadeBoundary(facade);
  });

  it("keeps pure definitions separate and every injectable owner bounded", () => {
    const definitions = source(paths.definition);
    expect(definitions).not.toMatch(
      /DatabaseService|AuditService|RealtimeBus|@Injectable/,
    );

    for (const path of [
      paths.repository,
      paths.resolver,
      paths.query,
      paths.policy,
      paths.revisions,
    ]) {
      const owner = source(path);
      expect(owner).toMatch(/@Injectable\(\)/);
      expect(sourceNloc(owner)).toBeLessThanOrEqual(350);
    }
  });

  it("keeps mutation dependencies and the full commit envelope in the revision owner", () => {
    const revision = source(paths.revisions);
    const nonRevisionOwners = [
      source(paths.query),
      source(paths.policy),
      source(paths.resolver),
      source(paths.repository),
    ].join("\n");

    expect(nonRevisionOwners).not.toMatch(/AuditService|RealtimeBus/);
    expect(revision.match(/\.transaction\s*\(/g)).toHaveLength(1);
    expect(revision).toMatch(/pg_advisory_xact_lock/);
    expect(revision).toMatch(/syncLeadStatuses/);
    expect(revision).toMatch(/insert into app\.student_funnel_revisions/i);
    expect(revision).toMatch(/crm\.client_pipeline_published/);
    expect(revision).toMatch(/emitCrmChanged/);
  });

  it("never updates or deletes append-only revision history", () => {
    const productionSources = Object.values(paths)
      .map(source)
      .join("\n");
    expect(productionSources).not.toMatch(
      /\bupdate\s+app\.student_funnel_revisions\b|\bdelete\s+from\s+app\.student_funnel_revisions\b/i,
    );
  });
});
