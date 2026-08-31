import {
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import * as ts from 'typescript';
import {
  AUDIT_FIELD_PRESENTATION_POLICIES,
  presentAuditFieldChange,
} from './audit-field-presentation.policy';
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

type LiteralBindings = Map<ts.Symbol, string[]>;
type CallSites = Map<ts.SignatureDeclaration | ts.JSDocSignature, ts.CallExpression[]>;

const HINT_VALUE_TYPES = new Set([
  'text', 'date', 'datetime', 'boolean', 'list', 'contact_list', 'reference', 'technical',
]);
const HINT_DISPLAY_MODES = new Set(['values', 'changed_only', 'count', 'hidden']);

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
  callSites: CallSites,
  bindings: LiteralBindings = new Map(),
  seen = new Set<ts.Node>(),
): ts.Expression | null {
  if (seen.has(object)) return null;
  seen.add(object);
  for (const property of [...object.properties].reverse()) {
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
    if (ts.isSpreadAssignment(property)) {
      for (const spread of resolveAuditObjects(
        property.expression,
        checker,
        callSites,
        new Set(seen),
        bindings,
      )) {
        const expression = objectPropertyExpression(
          spread.node,
          name,
          checker,
          callSites,
          spread.bindings,
          new Set(seen),
        );
        if (expression) return expression;
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
    const condition = staticBooleanValue(expression.condition, checker, bindings);
    const branches = condition === true
      ? [expression.whenTrue]
      : condition === false
        ? [expression.whenFalse]
        : [expression.whenTrue, expression.whenFalse];
    return branches.flatMap((branch) =>
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

function staticStringValues(
  checker: ts.TypeChecker,
  expression: ts.Expression,
  bindings: LiteralBindings,
  seen = new Set<ts.Symbol>(),
): string[] | null {
  const symbol = checker.getSymbolAtLocation(expression);
  const bound = symbol ? bindings.get(symbol) : null;
  if (bound) return bound;
  if (!symbol || !ts.isIdentifier(expression) || seen.has(symbol)) return null;
  seen.add(symbol);
  const declarations = symbol.declarations ?? [];
  if (declarations.length === 0) return null;
  const expanded = declarations.map((declaration) => {
    if (
      !ts.isVariableDeclaration(declaration)
      || !ts.isIdentifier(declaration.name)
      || !declaration.initializer
      || !ts.isVariableDeclarationList(declaration.parent)
      || !(declaration.parent.flags & ts.NodeFlags.Const)
    ) return null;
    return expandStringExpression(
      declaration.initializer,
      checker,
      bindings,
      new Set(seen),
    );
  });
  return expanded.every((values): values is string[] => values !== null)
    ? expanded.flat()
    : null;
}

function staticBooleanValue(
  expression: ts.Expression,
  checker: ts.TypeChecker,
  bindings: LiteralBindings,
): boolean | null {
  if (ts.isParenthesizedExpression(expression)) {
    return staticBooleanValue(expression.expression, checker, bindings);
  }
  if (ts.isPrefixUnaryExpression(expression) && expression.operator === ts.SyntaxKind.ExclamationToken) {
    const value = staticBooleanValue(expression.operand, checker, bindings);
    return value === null ? null : !value;
  }
  if (!ts.isBinaryExpression(expression)) return null;
  const equality = [
    ts.SyntaxKind.EqualsEqualsToken,
    ts.SyntaxKind.EqualsEqualsEqualsToken,
    ts.SyntaxKind.ExclamationEqualsToken,
    ts.SyntaxKind.ExclamationEqualsEqualsToken,
  ].includes(expression.operatorToken.kind);
  if (!equality) return null;
  const left = expandStringExpression(expression.left, checker, bindings);
  const right = expandStringExpression(expression.right, checker, bindings);
  if (!left || !right) return null;
  const negated = expression.operatorToken.kind === ts.SyntaxKind.ExclamationEqualsToken
    || expression.operatorToken.kind === ts.SyntaxKind.ExclamationEqualsEqualsToken;
  const results = left.flatMap((leftValue) =>
    right.map((rightValue) => negated ? leftValue !== rightValue : leftValue === rightValue),
  );
  if (results.every(Boolean)) return true;
  if (results.every((result) => !result)) return false;
  return null;
}

function expandStringExpression(
  expression: ts.Expression,
  checker: ts.TypeChecker,
  bindings: LiteralBindings = new Map(),
  seen = new Set<ts.Symbol>(),
): string[] | null {
  if (ts.isStringLiteralLike(expression)) return [expression.text];
  if (ts.isParenthesizedExpression(expression)) {
    return expandStringExpression(expression.expression, checker, bindings, seen);
  }
  if (
    ts.isAsExpression(expression)
    || ts.isTypeAssertionExpression(expression)
    || ts.isNonNullExpression(expression)
  ) {
    return expandStringExpression(expression.expression, checker, bindings, seen);
  }
  if (ts.isConditionalExpression(expression)) {
    const condition = staticBooleanValue(expression.condition, checker, bindings);
    if (condition !== null) {
      return expandStringExpression(
        condition ? expression.whenTrue : expression.whenFalse,
        checker,
        bindings,
        new Set(seen),
      );
    }
    const branches = [expression.whenTrue, expression.whenFalse].map((branch) =>
      expandStringExpression(branch, checker, bindings, new Set(seen)),
    );
    return branches.every((values): values is string[] => values !== null)
      ? branches.flat()
      : null;
  }
  if (ts.isTemplateExpression(expression)) {
    let expanded = [expression.head.text];
    for (const span of expression.templateSpans) {
      const values = expandStringExpression(
        span.expression,
        checker,
        bindings,
        new Set(seen),
      );
      if (!values) return null;
      expanded = expanded.flatMap((prefix) =>
        values.map((value) => `${prefix}${value}${span.literal.text}`),
      );
    }
    return expanded;
  }
  return staticStringValues(checker, expression, bindings, seen);
}

function resolveArrayElements(
  expression: ts.Expression,
  checker: ts.TypeChecker,
  callSites: CallSites,
  seen = new Set<ts.Node>(),
  bindings: LiteralBindings = new Map(),
): ts.Expression[] {
  if (seen.has(expression)) return [];
  seen.add(expression);
  if (ts.isParenthesizedExpression(expression)) {
    return resolveArrayElements(expression.expression, checker, callSites, seen, bindings);
  }
  if (
    ts.isAsExpression(expression)
    || ts.isTypeAssertionExpression(expression)
    || ts.isNonNullExpression(expression)
  ) {
    return resolveArrayElements(expression.expression, checker, callSites, seen, bindings);
  }
  if (ts.isConditionalExpression(expression)) {
    return [expression.whenTrue, expression.whenFalse].flatMap((branch) =>
      resolveArrayElements(branch, checker, callSites, new Set(seen), bindings),
    );
  }
  if (ts.isArrayLiteralExpression(expression)) {
    return expression.elements.flatMap((element) => {
      if (ts.isSpreadElement(element)) {
        return resolveArrayElements(
          element.expression,
          checker,
          callSites,
          new Set(seen),
          bindings,
        );
      }
      return ts.isExpression(element) ? [element] : [];
    });
  }
  if (ts.isIdentifier(expression)) {
    const symbol = checker.getSymbolAtLocation(expression);
    return (symbol?.declarations ?? []).flatMap((declaration) =>
      ts.isVariableDeclaration(declaration) && declaration.initializer
        ? resolveArrayElements(declaration.initializer, checker, callSites, seen, bindings)
        : ts.isParameter(declaration)
          ? (callSites.get(declaration.parent) ?? []).flatMap((call) => {
            const parameterIndex = declaration.parent.parameters.indexOf(declaration);
            const argument = call.arguments[parameterIndex];
            return argument
              ? resolveArrayElements(argument, checker, callSites, new Set(seen), bindings)
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
      resolveArrayElements(returned, checker, callSites, seen, callBindings),
    );
  }
  return [];
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
    return callSiteBindings(call, checker, callSites).flatMap((bindings) =>
      resolveAuditObjects(
        call.arguments[0],
        checker,
        callSites,
        new Set(),
        bindings,
      ).flatMap((mutation) => {
        const audit = objectPropertyExpression(
          mutation.node,
          'audit',
          checker,
          callSites,
          mutation.bindings,
        );
        return audit
          ? resolveAuditObjects(audit, checker, callSites, new Set(), mutation.bindings)
          : [];
      }),
    );
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
  const expression = objectPropertyExpression(
    audit.node,
    property,
    checker,
    callSites,
    audit.bindings,
  );
  if (!expression) return [];
  return resolveAuditObjects(
    expression,
    checker,
    callSites,
    new Set(),
    audit.bindings,
  ).flatMap((resolved) => auditObjectFieldNames(resolved, checker, callSites));
}

function auditObjectFieldNames(
  object: ResolvedAuditObject,
  checker: ts.TypeChecker,
  callSites: CallSites,
  seen = new Set<ts.Node>(),
): string[] {
  if (seen.has(object.node)) return [];
  seen.add(object.node);
  return object.node.properties.flatMap((candidate) => {
    if (ts.isPropertyAssignment(candidate) || ts.isShorthandPropertyAssignment(candidate)) {
      return [propertyName(candidate.name, object.node.getSourceFile())];
    }
    if (!ts.isSpreadAssignment(candidate)) return [];
    return resolveAuditObjects(
      candidate.expression,
      checker,
      callSites,
      new Set(seen),
      object.bindings,
    ).flatMap((spread) => auditObjectFieldNames(spread, checker, callSites, new Set(seen)));
  });
}

function auditMetadataFields(
  audit: ResolvedAuditObject,
  checker: ts.TypeChecker,
  callSites: CallSites,
): { fields: string[]; hintedFields: string[] } {
  const metadataExpression = objectPropertyExpression(
    audit.node,
    'metadata',
    checker,
    callSites,
    audit.bindings,
  );
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
    const changes = objectPropertyExpression(
      metadata.node,
      'changes',
      checker,
      callSites,
      metadata.bindings,
    );
    if (!changes) continue;
    for (const element of resolveArrayElements(
      changes,
      checker,
      callSites,
      new Set(),
      metadata.bindings,
    )) {
      for (const change of resolveAuditObjects(
        element,
        checker,
        callSites,
        new Set(),
        metadata.bindings,
      )) {
        const fieldExpression = objectPropertyExpression(
          change.node,
          'field',
          checker,
          callSites,
          change.bindings,
        ) ?? objectPropertyExpression(
          change.node,
          'key',
          checker,
          callSites,
          change.bindings,
        );
        const expanded = fieldExpression
          ? expandStringExpression(fieldExpression, checker, change.bindings) ?? []
          : [];
        fields.push(...expanded);
        const labelExpression = objectPropertyExpression(
          change.node,
          'label',
          checker,
          callSites,
          change.bindings,
        );
        const valueTypeExpression = objectPropertyExpression(
          change.node,
          'valueType',
          checker,
          callSites,
          change.bindings,
        );
        const displayModeExpression = objectPropertyExpression(
          change.node,
          'displayMode',
          checker,
          callSites,
          change.bindings,
        );
        const labels = labelExpression
          ? expandStringExpression(labelExpression, checker, change.bindings)
          : null;
        const valueTypes = valueTypeExpression
          ? expandStringExpression(valueTypeExpression, checker, change.bindings)
          : null;
        const displayModes = displayModeExpression
          ? expandStringExpression(displayModeExpression, checker, change.bindings)
          : null;
        if (
          labels?.every((label) => label.trim().length > 0)
          && valueTypes?.every((valueType) => HINT_VALUE_TYPES.has(valueType))
          && displayModes?.every((displayMode) => HINT_DISPLAY_MODES.has(displayMode))
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
          const actionExpression = objectPropertyExpression(
            audit.node,
            'action',
            checker,
            callSites,
            audit.bindings,
          );
          const entityExpression = objectPropertyExpression(
            audit.node,
            'entityType',
            checker,
            callSites,
            audit.bindings,
          );
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

function fixtureAuditContract(source: string): AuditContractInventory {
  const root = mkdtempSync(join(tmpdir(), 'audit-contract-'));
  try {
    writeFileSync(join(root, 'fixture.ts'), source, 'utf8');
    return productionAuditContract(root);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
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

  it('resolves audit and reference fields inherited through object spreads', () => {
    const inventory = fixtureAuditContract(`
      class AuditService { record(_input: unknown): void {} }
      const auditService = new AuditService();
      const ref = { spreadReferenceField: 'До' };
      const baseAudit = {
        action: 'crm.fixture_object_spread',
        entityType: 'fixture_object_spread',
        beforeRef: { ...ref },
      };
      auditService.record({ ...baseAudit });
    `);

    expect(inventory.actions).toContain('crm.fixture_object_spread');
    expect(inventory.entityTypes).toContain('fixture_object_spread');
    expect(inventory.presentedFields).toContain('spreadReferenceField');
  });

  it('resolves a statically defined array identifier used as metadata changes', () => {
    const inventory = fixtureAuditContract(`
      class AuditService { record(_input: unknown): void {} }
      const auditService = new AuditService();
      const immutableChanges = [{
        field: 'arrayHintField',
        from: 'До',
        to: 'После',
        label: 'Поле из массива',
        valueType: 'text',
        displayMode: 'values',
      }];
      auditService.record({
        action: 'crm.fixture_array_identifier',
        entityType: 'fixture',
        metadata: { changes: immutableChanges },
      });
    `);

    expect(inventory.presentedFields).toContain('arrayHintField');
    expect(inventory.hintedFields).toContain('arrayHintField');
  });

  it('accepts only statically resolved valid literal hint triples', () => {
    const inventory = fixtureAuditContract(`
      class AuditService { record(_input: unknown): void {} }
      const auditService = new AuditService();
      function dynamicLabel(): string { return 'Динамическая подпись'; }
      auditService.record({
        action: 'crm.fixture_hint_validation',
        entityType: 'fixture',
        metadata: {
          changes: [
            {
              field: 'validHintField',
              from: 'До',
              to: 'После',
              label: 'Надёжная подпись',
              valueType: 'text',
              displayMode: 'values',
            },
            {
              field: 'dynamicLabelField',
              label: dynamicLabel(),
              valueType: 'text',
              displayMode: 'values',
            },
            {
              field: 'emptyLabelField',
              label: '   ',
              valueType: 'text',
              displayMode: 'values',
            },
            {
              field: 'invalidValueTypeField',
              label: 'Тип',
              valueType: 'money',
              displayMode: 'values',
            },
            {
              field: 'invalidDisplayModeField',
              label: 'Режим',
              valueType: 'text',
              displayMode: 'raw',
            },
          ],
        },
      });
    `);

    expect([...inventory.hintedFields].sort()).toEqual(['validHintField']);
    expect([
      'dynamicLabelField',
      'emptyLabelField',
      'invalidValueTypeField',
      'invalidDisplayModeField',
    ].filter((field) => !inventory.presentedFields.has(field))).toEqual([]);
  });

  it('rejects dynamic or mutable hints whose TypeScript types look literal-safe', () => {
    const inventory = fixtureAuditContract(`
      type HintValueType = 'text' | 'date';
      type HintDisplayMode = 'values' | 'changed_only';
      declare function runtimeLabel(): string;
      declare function runtimeValueType(): HintValueType;
      declare function runtimeDisplayMode(): HintDisplayMode;
      class AuditService { record(_input: unknown): void {} }
      const auditService = new AuditService();
      const staticLabel = 'Статическая подпись' as const;
      const staticValueType: HintValueType = 'text';
      const staticDisplayMode: HintDisplayMode = 'values';
      let mutableDisplayMode: HintDisplayMode = runtimeDisplayMode();
      const annotatedDisplayMode: HintDisplayMode = runtimeDisplayMode();
      const assertedLabel = runtimeLabel() as 'Убедительная подпись';
      const assertedValueType = runtimeValueType() as 'text';
      auditService.record({
        action: 'crm.fixture_typed_dynamic_hints',
        entityType: 'fixture',
        metadata: {
          changes: [
            {
              field: 'staticControlField',
              label: staticLabel,
              valueType: staticValueType,
              displayMode: staticDisplayMode,
            },
            {
              field: 'dynamicUnionModeField',
              label: 'Динамический режим',
              valueType: 'text',
              displayMode: runtimeDisplayMode(),
            },
            {
              field: 'mutableUnionModeField',
              label: 'Изменяемый режим',
              valueType: 'text',
              displayMode: mutableDisplayMode,
            },
            {
              field: 'annotatedUnionModeField',
              label: 'Аннотированный режим',
              valueType: 'text',
              displayMode: annotatedDisplayMode,
            },
            {
              field: 'assertedLiteralLabelField',
              label: assertedLabel,
              valueType: 'text',
              displayMode: 'values',
            },
            {
              field: 'assertedLiteralValueTypeField',
              label: 'Заявленный тип',
              valueType: assertedValueType,
              displayMode: 'values',
            },
          ],
        },
      });
    `);

    expect([...inventory.hintedFields].sort()).toEqual(['staticControlField']);
    expect([
      'dynamicUnionModeField',
      'mutableUnionModeField',
      'annotatedUnionModeField',
      'assertedLiteralLabelField',
      'assertedLiteralValueTypeField',
    ].filter((field) => !inventory.presentedFields.has(field))).toEqual([]);
  });

  it('classifies every statically known presented field through policy or immutable hints', () => {
    const inventory = productionAuditContract(sourceRoot);
    const compatibilityLabels = registryKeys(presenterSource, 'ACTION_FIELD_LABELS');
    const unclassified = [...inventory.presentedFields].filter((field) => {
      if (
        inventory.hintedFields.has(field)
        || compatibilityLabels.has(field)
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

  it('enforces every central field classification through the runtime presenter', () => {
    for (const [field, policy] of Object.entries(AUDIT_FIELD_PRESENTATION_POLICIES)) {
      const presented = presentAuditFieldChange({ field, from: 'До', to: 'После' });
      if (policy.valueType === 'technical') {
        expect(presented).toBeNull();
      } else if (policy.displayMode === 'changed_only') {
        expect(presented).toEqual({
          key: field,
          label: policy.label,
          before: null,
          after: null,
        });
      }
    }
  });
});
