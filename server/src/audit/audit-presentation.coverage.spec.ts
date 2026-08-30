import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import * as ts from 'typescript';
import { AuditPresentationInput } from './audit-presentation.types';
import { AuditPresentationService } from './audit-presentation.service';

interface AuditContractInventory {
  actions: Set<string>;
  entityTypes: Set<string>;
  unresolvedActions: string[];
}

type LiteralBindings = Map<ts.Symbol, string[]>;

interface ResolvedAuditObject {
  node: ts.ObjectLiteralExpression;
  bindings: LiteralBindings;
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
  seen = new Set<ts.Node>(),
  bindings: LiteralBindings = new Map(),
): ResolvedAuditObject[] {
  if (seen.has(expression)) return [];
  seen.add(expression);
  if (ts.isParenthesizedExpression(expression)) {
    return resolveAuditObjects(expression.expression, checker, seen, bindings);
  }
  if (ts.isObjectLiteralExpression(expression)) return [{ node: expression, bindings }];
  if (ts.isIdentifier(expression)) {
    const symbol = checker.getSymbolAtLocation(expression);
    return (symbol?.declarations ?? []).flatMap((declaration) =>
      ts.isVariableDeclaration(declaration) && declaration.initializer
        ? resolveAuditObjects(declaration.initializer, checker, seen, bindings)
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
      resolveAuditObjects(returned, checker, seen, callBindings),
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
): ResolvedAuditObject[] {
  if (!ts.isPropertyAccessExpression(call.expression)) return [];
  const receiver = call.expression.expression;
  const method = call.expression.name.text;
  const receiverSymbol = symbolName(checker, receiver);
  if (receiverSymbol === 'AuditService' && method === 'record' && call.arguments[0]) {
    return resolveAuditObjects(call.arguments[0], checker);
  }
  if (
    receiverSymbol === 'PlatformIntegrityService'
    && method === 'executeVersionedMutation'
    && call.arguments[0]
  ) {
    return resolveAuditObjects(call.arguments[0], checker).flatMap((mutation) => {
      const audit = objectPropertyExpression(mutation.node, 'audit', checker);
      return audit ? resolveAuditObjects(audit, checker, new Set(), mutation.bindings) : [];
    });
  }
  return [];
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
  const actions = new Set<string>();
  const entityTypes = new Set<string>();
  const unresolvedActions: string[] = [];

  for (const source of program.getSourceFiles()) {
    const sourcePath = resolve(source.fileName).replaceAll('\\', '/').toLowerCase();
    if (!productionPaths.has(sourcePath)) continue;
    const visit = (node: ts.Node) => {
      if (ts.isCallExpression(node)) {
        for (const audit of auditObjectsForCall(node, checker)) {
          const actionExpression = objectPropertyExpression(audit.node, 'action', checker);
          const entityExpression = objectPropertyExpression(audit.node, 'entityType', checker);
          const expandedActions = actionExpression
            ? expandStringExpression(actionExpression, checker, audit.bindings)
            : null;
          const actionSource = actionExpression
            ?.getText(actionExpression.getSourceFile())
            .replace(/\s+/g, '');
          if (
            actionExpression
            && !expandedActions
            && actionSource
            && /^(?:`|['"])?(?:crm|workflow)\./.test(actionSource)
          ) {
            unresolvedActions.push(actionSource);
          }
          for (const action of expandedActions ?? []) {
            if (/^(crm|workflow)\./.test(action)) actions.add(action);
          }
          for (const entityType of entityExpression
            ? expandStringExpression(entityExpression, checker, audit.bindings) ?? []
            : []) {
            entityTypes.add(entityType);
          }
        }
      }
      ts.forEachChild(node, visit);
    };
    visit(source);
  }
  return { actions, entityTypes, unresolvedActions };
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

  it('requires every real CRM/workflow audit producer action to have an explicit shared title', () => {
    const inventory = productionAuditContract(sourceRoot);
    const actionTitles = registryKeys(presenterSource, 'ACTION_TITLES');

    expect(inventory.actions).toContain('crm.student_updated');
    expect(inventory.unresolvedActions).toEqual([]);
    expect([...inventory.actions].filter((action) => !actionTitles.has(action))).toEqual([]);
    for (const actionKey of inventory.actions) {
      expect(service.present({ ...input, actionKey }).title).not.toBe('Действие выполнено');
    }
  });

  it('requires every statically known journal target to have a central Russian label', () => {
    const inventory = productionAuditContract(sourceRoot);
    const entityLabels = registryKeys(presenterSource, 'ENTITY_LABELS');

    expect(inventory.entityTypes).toContain('access:role-package');
    expect([...inventory.entityTypes].filter((type) => !entityLabels.has(type))).toEqual([]);
  });
});
