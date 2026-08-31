import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import * as ts from 'typescript';
import { presentAuditFieldChange } from './audit-field-presentation.policy';
import { AuditPresentationInput } from './audit-presentation.types';
import { AuditPresentationService } from './audit-presentation.service';

interface AuditContractInventory {
  actions: Set<string>;
  entityTypes: Set<string>;
  presentedFields: Set<string>;
  hintedFields: Set<string>;
  unresolvedActions: string[];
}

interface AuditProducerFixture {
  source: 'sql' | 'import' | 'dynamic';
  actions: string[];
  entityTypes: string[];
  presentedFields: string[];
}

const NON_AST_AUDIT_PRODUCER_FIXTURES: AuditProducerFixture[] = [
  {
    source: 'sql',
    actions: ['workflow.shared_task_legacy_status'],
    entityTypes: ['shared_task'],
    presentedFields: ['field', 'value', 'assigned_to'],
  },
  {
    source: 'import',
    actions: ['workflow.shared_task_legacy_status'],
    entityTypes: ['shared_task'],
    presentedFields: ['field', 'value'],
  },
  {
    source: 'dynamic',
    actions: ['task.created'],
    entityTypes: ['task'],
    presentedFields: [],
  },
  {
    source: 'dynamic',
    actions: ['workflow.shared_task_closed', 'crm.lesson_rescheduled'],
    entityTypes: ['shared_task', 'lesson'],
    presentedFields: [
      'taskId', 'taskVersion', 'closeId', 'closedAt', 'closedBy', 'closeRequestId',
      'lessonId', 'state', 'successorId', 'transitionId', 'clientFinancialFactIds',
      'teacherFinancialFactId', 'financialDecision', 'transitionFingerprint',
    ],
  },
];

const EXPLICIT_FIELD_CLASSIFICATIONS: Record<
  string,
  'technical' | 'changed_only'
> = {
  accountEnabled: 'changed_only',
  amountMinor: 'technical',
  archiveEffectiveDate: 'technical',
  archivedAt: 'technical',
  branchAssignments: 'changed_only',
  capacity: 'changed_only',
  closedAt: 'technical',
  currencyCode: 'technical',
  entityType: 'technical',
  field: 'technical',
  financialDecision: 'changed_only',
  items: 'changed_only',
  kind: 'technical',
  lifecycle: 'changed_only',
  lifecycleState: 'changed_only',
  personType: 'changed_only',
  state: 'changed_only',
  value: 'changed_only',
  walletBalanceMinor: 'technical',
};

type LiteralBindings = Map<ts.Symbol, string[]>;
type CallSites = Map<ts.SignatureDeclaration | ts.JSDocSignature, ts.CallExpression[]>;

interface ResolvedAuditObject {
  node: ts.ObjectLiteralExpression;
  bindings: LiteralBindings;
}

function enclosingSignature(node: ts.Node): ts.SignatureDeclaration | ts.JSDocSignature | null {
  let current: ts.Node | undefined = node.parent;
  while (current) {
    if (ts.isFunctionLike(current)) return current;
    current = current.parent;
  }
  return null;
}

function callSiteBindings(
  node: ts.Node,
  checker: ts.TypeChecker,
  callSites: CallSites,
): LiteralBindings[] {
  const declaration = enclosingSignature(node);
  if (!declaration) return [new Map()];
  const callers = callSites.get(declaration) ?? [];
  if (callers.length === 0) return [new Map()];

  return callers.map((caller) => {
    const bindings: LiteralBindings = new Map();
    declaration.parameters.forEach((parameter, index) => {
      if (!ts.isIdentifier(parameter.name)) return;
      const argument = caller.arguments[index];
      const symbol = checker.getSymbolAtLocation(parameter.name);
      const values = argument ? expandStringExpression(argument, checker) : null;
      if (symbol && values) bindings.set(symbol, values);
    });
    return bindings;
  });
}

function productionTypescriptFiles(directory: string): string[] {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) {
      return entry.name === 'migration' ? [] : productionTypescriptFiles(path);
    }
    return entry.name.endsWith('.ts')
      && !entry.name.endsWith('.spec.ts')
      && !entry.name.endsWith('.test.ts')
      ? [path]
      : [];
  });
}

function propertyName(node: ts.PropertyName, source: ts.SourceFile): string {
  return ts.isIdentifier(node) || ts.isStringLiteralLike(node)
    ? node.text
    : node.getText(source);
}

function registryKeys(sourcePath: string, registryName: string): Set<string> {
  const source = ts.createSourceFile(
    sourcePath,
    readFileSync(sourcePath, 'utf8'),
    ts.ScriptTarget.Latest,
    true,
  );
  const keys = new Set<string>();
  const visit = (node: ts.Node) => {
    if (
      ts.isVariableDeclaration(node)
      && ts.isIdentifier(node.name)
      && node.name.text === registryName
      && node.initializer
      && ts.isObjectLiteralExpression(node.initializer)
    ) {
      for (const property of node.initializer.properties) {
        if (ts.isPropertyAssignment(property)) {
          keys.add(propertyName(property.name, source));
        }
      }
    }
    ts.forEachChild(node, visit);
  };
  visit(source);
  return keys;
}

function symbolName(checker: ts.TypeChecker, node: ts.Expression): string | null {
  const type = checker.getTypeAtLocation(node);
  return type.getSymbol()?.getName() ?? type.aliasSymbol?.getName() ?? null;
}

function objectPropertyExpression(
  object: ts.ObjectLiteralExpression,
  name: string,
  checker: ts.TypeChecker,
): ts.Expression | null {
  for (const property of object.properties) {
    if (ts.isPropertyAssignment(property) && propertyName(property.name, object.getSourceFile()) === name) {
      return property.initializer;
    }
    if (ts.isShorthandPropertyAssignment(property) && property.name.text === name) {
      const symbol = checker.getShorthandAssignmentValueSymbol(property);
      const declaration = symbol?.valueDeclaration;
      if (declaration && ts.isVariableDeclaration(declaration) && declaration.initializer) {
        return declaration.initializer;
      }
    }
  }
  return null;
}

function returnedExpressions(
  declaration: ts.SignatureDeclaration | ts.JSDocSignature,
): ts.Expression[] {
  const body = (declaration as ts.FunctionLikeDeclaration).body;
  if (!body || !ts.isBlock(body)) {
    return [];
  }
  const expressions: ts.Expression[] = [];
  const visit = (node: ts.Node) => {
    if (ts.isReturnStatement(node) && node.expression) expressions.push(node.expression);
    ts.forEachChild(node, visit);
  };
  visit(body);
  return expressions;
}

function resolveAuditObjects(
  expression: ts.Expression,
  checker: ts.TypeChecker,
  callSites: CallSites,
  seen = new Set<ts.Node>(),
  bindings: LiteralBindings = new Map(),
): ResolvedAuditObject[] {
  if (seen.has(expression)) return [];
  seen.add(expression);
  if (ts.isParenthesizedExpression(expression)) {
    return resolveAuditObjects(expression.expression, checker, callSites, seen, bindings);
  }
  if (ts.isAsExpression(expression) || ts.isTypeAssertionExpression(expression)) {
    return resolveAuditObjects(expression.expression, checker, callSites, seen, bindings);
  }
  if (ts.isNonNullExpression(expression)) {
    return resolveAuditObjects(expression.expression, checker, callSites, seen, bindings);
  }
  if (ts.isConditionalExpression(expression)) {
    return [expression.whenTrue, expression.whenFalse].flatMap((branch) =>
      resolveAuditObjects(branch, checker, callSites, new Set(seen), bindings),
    );
  }
  if (ts.isObjectLiteralExpression(expression)) return [{ node: expression, bindings }];
  if (ts.isIdentifier(expression)) {
    const symbol = checker.getSymbolAtLocation(expression);
    return (symbol?.declarations ?? []).flatMap((declaration) =>
      ts.isVariableDeclaration(declaration) && declaration.initializer
        ? resolveAuditObjects(declaration.initializer, checker, callSites, seen, bindings)
        : ts.isParameter(declaration)
          ? (callSites.get(declaration.parent) ?? []).flatMap((call) => {
            const parameterIndex = declaration.parent.parameters.indexOf(declaration);
            const argument = call.arguments[parameterIndex];
            return argument
              ? resolveAuditObjects(argument, checker, callSites, new Set(seen), bindings)
              : [];
          })
          : [],
    );
  }
  if (ts.isCallExpression(expression)) {
    const declaration = checker.getResolvedSignature(expression)?.declaration;
    if (!declaration) return [];
    const callBindings = new Map(bindings);
    declaration.parameters.forEach((parameter, index) => {
      const argument = expression.arguments[index];
      if (!argument || !ts.isIdentifier(parameter.name)) return;
      const symbol = checker.getSymbolAtLocation(parameter.name);
      const values = expandStringExpression(argument, checker, bindings);
      if (symbol && values) callBindings.set(symbol, values);
    });
    return returnedExpressions(declaration).flatMap((returned) =>
      resolveAuditObjects(returned, checker, callSites, seen, callBindings),
    );
  }
  return [];
}

function stringLiteralUnion(
  checker: ts.TypeChecker,
  expression: ts.Expression,
  bindings: LiteralBindings,
): string[] | null {
  const symbol = checker.getSymbolAtLocation(expression);
  const bound = symbol ? bindings.get(symbol) : null;
  if (bound) return bound;
  const type = checker.getTypeAtLocation(expression);
  const members = type.isUnion() ? type.types : [type];
  const values = members.flatMap((member) =>
    member.flags & ts.TypeFlags.StringLiteral
      ? [(member as ts.StringLiteralType).value]
      : [],
  );
  return values.length === members.length && values.length > 0 ? values : null;
}

function expandStringExpression(
  expression: ts.Expression,
  checker: ts.TypeChecker,
  bindings: LiteralBindings = new Map(),
): string[] | null {
  if (ts.isStringLiteralLike(expression)) return [expression.text];
  if (ts.isParenthesizedExpression(expression)) {
    return expandStringExpression(expression.expression, checker, bindings);
  }
  if (ts.isConditionalExpression(expression)) {
    const whenTrue = expandStringExpression(expression.whenTrue, checker, bindings);
    const whenFalse = expandStringExpression(expression.whenFalse, checker, bindings);
    return whenTrue && whenFalse ? [...whenTrue, ...whenFalse] : null;
  }
  if (ts.isTemplateExpression(expression)) {
    let expanded = [expression.head.text];
    for (const span of expression.templateSpans) {
      const values = stringLiteralUnion(checker, span.expression, bindings);
      if (!values) return null;
      expanded = expanded.flatMap((prefix) =>
        values.map((value) => `${prefix}${value}${span.literal.text}`),
      );
    }
    return expanded;
  }
  return stringLiteralUnion(checker, expression, bindings);
}

function auditObjectsForCall(
  call: ts.CallExpression,
  checker: ts.TypeChecker,
  callSites: CallSites,
): ResolvedAuditObject[] {
  if (!ts.isPropertyAccessExpression(call.expression)) return [];
  const receiver = call.expression.expression;
  const method = call.expression.name.text;
  const receiverSymbol = symbolName(checker, receiver);
  if (receiverSymbol === 'AuditService' && method === 'record' && call.arguments[0]) {
    return callSiteBindings(call, checker, callSites).flatMap((bindings) =>
      resolveAuditObjects(call.arguments[0], checker, callSites, new Set(), bindings),
    );
  }
  if (
    receiverSymbol === 'PlatformIntegrityService'
    && method === 'executeVersionedMutation'
    && call.arguments[0]
  ) {
    return resolveAuditObjects(call.arguments[0], checker, callSites).flatMap((mutation) => {
      const audit = objectPropertyExpression(mutation.node, 'audit', checker);
      return audit
        ? resolveAuditObjects(audit, checker, callSites, new Set(), mutation.bindings)
        : [];
    });
  }
  if (
    receiverSymbol === 'PlatformIntegrityRepository'
    && method === 'appendAudit'
    && call.arguments[1]
  ) {
    return callSiteBindings(call, checker, callSites).flatMap((bindings) =>
      resolveAuditObjects(call.arguments[1], checker, callSites, new Set(), bindings),
    );
  }
  return [];
}

function auditRefFields(
  audit: ResolvedAuditObject,
  property: 'beforeRef' | 'afterRef',
  checker: ts.TypeChecker,
  callSites: CallSites,
): string[] {
  const expression = objectPropertyExpression(audit.node, property, checker);
  if (!expression) return [];
  return resolveAuditObjects(
    expression,
    checker,
    callSites,
    new Set(),
    audit.bindings,
  ).flatMap(({ node }) => node.properties.flatMap((candidate) =>
    ts.isPropertyAssignment(candidate) || ts.isShorthandPropertyAssignment(candidate)
      ? [propertyName(candidate.name, node.getSourceFile())]
      : [],
  ));
}

function auditMetadataFields(
  audit: ResolvedAuditObject,
  checker: ts.TypeChecker,
  callSites: CallSites,
): { fields: string[]; hintedFields: string[] } {
  const metadataExpression = objectPropertyExpression(audit.node, 'metadata', checker);
  if (!metadataExpression) return { fields: [], hintedFields: [] };
  const fields: string[] = [];
  const hintedFields: string[] = [];
  for (const metadata of resolveAuditObjects(
    metadataExpression,
    checker,
    callSites,
    new Set(),
    audit.bindings,
  )) {
    const changes = objectPropertyExpression(metadata.node, 'changes', checker);
    if (!changes || !ts.isArrayLiteralExpression(changes)) continue;
    for (const element of changes.elements) {
      if (!ts.isExpression(element)) continue;
      for (const change of resolveAuditObjects(
        element,
        checker,
        callSites,
        new Set(),
        metadata.bindings,
      )) {
        const fieldExpression = objectPropertyExpression(change.node, 'field', checker)
          ?? objectPropertyExpression(change.node, 'key', checker);
        const expanded = fieldExpression
          ? expandStringExpression(fieldExpression, checker, change.bindings) ?? []
          : [];
        fields.push(...expanded);
        if (
          objectPropertyExpression(change.node, 'label', checker)
          && objectPropertyExpression(change.node, 'valueType', checker)
          && objectPropertyExpression(change.node, 'displayMode', checker)
        ) {
          hintedFields.push(...expanded);
        }
      }
    }
  }
  return { fields, hintedFields };
}

function productionAuditContract(sourceRoot: string): AuditContractInventory {
  const files = productionTypescriptFiles(sourceRoot);
  const productionPaths = new Set(
    files.map((path) => resolve(path).replaceAll('\\', '/').toLowerCase()),
  );
  const program = ts.createProgram(files, {
    target: ts.ScriptTarget.ES2023,
    module: ts.ModuleKind.CommonJS,
    moduleResolution: ts.ModuleResolutionKind.Node10,
    experimentalDecorators: true,
    skipLibCheck: true,
    strict: true,
  });
  const checker = program.getTypeChecker();
  const callSites: CallSites = new Map();
  for (const source of program.getSourceFiles()) {
    const sourcePath = resolve(source.fileName).replaceAll('\\', '/').toLowerCase();
    if (!productionPaths.has(sourcePath)) continue;
    const visit = (node: ts.Node) => {
      if (ts.isCallExpression(node)) {
        const declaration = checker.getResolvedSignature(node)?.declaration;
        if (declaration) {
          const calls = callSites.get(declaration) ?? [];
          calls.push(node);
          callSites.set(declaration, calls);
        }
      }
      ts.forEachChild(node, visit);
    };
    visit(source);
  }
  const actions = new Set<string>();
  const entityTypes = new Set<string>();
  const presentedFields = new Set<string>();
  const hintedFields = new Set<string>();
  const unresolvedActions: string[] = [];

  for (const source of program.getSourceFiles()) {
    const sourcePath = resolve(source.fileName).replaceAll('\\', '/').toLowerCase();
    if (!productionPaths.has(sourcePath)) continue;
    const visit = (node: ts.Node) => {
      if (ts.isCallExpression(node)) {
        for (const audit of auditObjectsForCall(node, checker, callSites)) {
          const actionExpression = objectPropertyExpression(audit.node, 'action', checker);
          const entityExpression = objectPropertyExpression(audit.node, 'entityType', checker);
          const expandedActions = actionExpression
            ? expandStringExpression(actionExpression, checker, audit.bindings)
            : null;
          const actionSource = actionExpression
            ?.getText(actionExpression.getSourceFile())
            .replace(/\s+/g, '');
          if (actionExpression && !expandedActions && actionSource) {
            unresolvedActions.push(actionSource);
          }
          for (const action of expandedActions ?? []) {
            actions.add(action);
          }
          for (const entityType of entityExpression
            ? expandStringExpression(entityExpression, checker, audit.bindings) ?? []
            : []) {
            entityTypes.add(entityType);
          }
          for (const field of [
            ...auditRefFields(audit, 'beforeRef', checker, callSites),
            ...auditRefFields(audit, 'afterRef', checker, callSites),
          ]) {
            presentedFields.add(field);
          }
          const metadata = auditMetadataFields(audit, checker, callSites);
          for (const field of metadata.fields) presentedFields.add(field);
          for (const field of metadata.hintedFields) hintedFields.add(field);
        }
      }
      ts.forEachChild(node, visit);
    };
    visit(source);
  }
  for (const fixture of NON_AST_AUDIT_PRODUCER_FIXTURES) {
    fixture.actions.forEach((action) => actions.add(action));
    fixture.entityTypes.forEach((entityType) => entityTypes.add(entityType));
    fixture.presentedFields.forEach((field) => presentedFields.add(field));
  }
  return { actions, entityTypes, presentedFields, hintedFields, unresolvedActions };
}

describe('Audit presentation production coverage', () => {
  const service = new AuditPresentationService();
  const input: AuditPresentationInput = {
    id: 'event-coverage',
    actionKey: 'crm.student_created',
    actor: { id: 'actor-1', name: 'Администратор', role: 'admin' },
    target: { type: 'student', id: 'student-1', displayName: 'Мария' },
    metadata: null,
    beforeRef: null,
    afterRef: null,
    reason: null,
    reasonText: null,
    occurredAt: new Date('2026-08-31T00:00:00.000Z'),
  };
  const sourceRoot = join(__dirname, '..');
  const presenterSource = join(__dirname, 'audit-presentation.service.ts');

  it('requires every real business audit producer action to have an explicit shared title', () => {
    const inventory = productionAuditContract(sourceRoot);
    const actionTitles = registryKeys(presenterSource, 'ACTION_TITLES');
    const businessActions = [...inventory.actions].filter((action) =>
      service.isBusinessAction(action),
    );

    expect(inventory.actions).toContain('crm.student_updated');
    expect(inventory.actions).toContain('crm.lesson_deleted');
    expect(inventory.actions).toContain('crm.schedule_series_stopped');
    expect(inventory.actions).toContain('crm.reference_discipline_archived');
    expect(inventory.actions).toContain('crm.reference_loss_reason_archived');
    expect(inventory.actions).toContain('crm.reference_branch_discipline_unassigned');
    expect(inventory.actions).toContain('crm.client_internal_note_changed');
    expect(inventory.actions).toContain('crm.installment_payment_due');
    expect(inventory.actions).toContain('task.created');
    expect(inventory.actions).toContain('workflow.shared_task_legacy_status');
    expect(inventory.unresolvedActions).toEqual([]);
    expect(businessActions.filter((action) => !actionTitles.has(action))).toEqual([]);
    for (const actionKey of businessActions) {
      expect(service.present({ ...input, actionKey }).title).not.toBe('Действие выполнено');
      expect(service.present({ ...input, actionKey }).title).not.toMatch(/^Изменение: [A-Za-z0-9_.:-]+$/);
    }
  });

  it('requires every statically known journal target to have a central Russian label', () => {
    const inventory = productionAuditContract(sourceRoot);
    const entityLabels = registryKeys(presenterSource, 'ENTITY_LABELS');

    expect(inventory.entityTypes).toContain('access:role-package');
    expect([...inventory.entityTypes].filter((type) => !entityLabels.has(type))).toEqual([]);
  });

  it('classifies every statically known presented field through policy or immutable hints', () => {
    const inventory = productionAuditContract(sourceRoot);
    const compatibilityLabels = registryKeys(presenterSource, 'ACTION_FIELD_LABELS');
    const unclassified = [...inventory.presentedFields].filter((field) => {
      if (
        inventory.hintedFields.has(field)
        || compatibilityLabels.has(field)
        || EXPLICIT_FIELD_CLASSIFICATIONS[field]
      ) return false;
      const presented = presentAuditFieldChange({ field, from: 'До', to: 'После' });
      return presented !== null
        && presented.label === 'Дополнительное поле'
        && (presented.before !== null || presented.after !== null);
    });

    const expectedFixtureFields = [
      'closedBy',
      'transitionFingerprint',
      'capacity',
      'assigned_to',
      'value',
    ];
    expect(expectedFixtureFields.filter((field) => !inventory.presentedFields.has(field)))
      .toEqual([]);
    expect(unclassified.sort()).toEqual([]);
  });
});
