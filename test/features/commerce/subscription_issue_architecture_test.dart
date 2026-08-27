// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

const _directory =
    'lib/features/crm/presentation/client_card/subscription_issue_';

String _source(String suffix) =>
    File('$_directory$suffix.dart').readAsStringSync();

({String source, ParseStringResult parsed}) _parsed(String suffix) {
  final source = _source(suffix);
  return (
    source: source,
    parsed: parseString(content: source, path: '$_directory$suffix.dart'),
  );
}

int _nloc(String source) => source.split('\n').where((line) {
  final trimmed = line.trim();
  return trimmed.isNotEmpty &&
      !trimmed.startsWith('//') &&
      !trimmed.startsWith('///');
}).length;

String _classBody(String source, String className) {
  final declaration = source.indexOf('class $className');
  expect(declaration, isNonNegative, reason: className);
  final openingBrace = source.indexOf('{', declaration);
  var depth = 0;
  for (var index = openingBrace; index < source.length; index++) {
    if (source[index] == '{') depth++;
    if (source[index] == '}') {
      depth--;
      if (depth == 0) return source.substring(openingBrace, index + 1);
    }
  }
  fail('Unclosed class $className');
}

class _ComplexityVisitor extends RecursiveAstVisitor<void> {
  var branches = 0;

  @override
  void visitIfStatement(IfStatement node) {
    branches++;
    super.visitIfStatement(node);
  }

  @override
  void visitForStatement(ForStatement node) {
    branches++;
    super.visitForStatement(node);
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    branches++;
    super.visitWhileStatement(node);
  }

  @override
  void visitDoStatement(DoStatement node) {
    branches++;
    super.visitDoStatement(node);
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    branches++;
    super.visitConditionalExpression(node);
  }

  @override
  void visitIfElement(IfElement node) {
    branches++;
    super.visitIfElement(node);
  }

  @override
  void visitForElement(ForElement node) {
    branches++;
    super.visitForElement(node);
  }

  @override
  void visitCatchClause(CatchClause node) {
    branches++;
    super.visitCatchClause(node);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    if (node.operator.lexeme == '&&' || node.operator.lexeme == '||') {
      branches++;
    }
    super.visitBinaryExpression(node);
  }
}

class _EffectInvocationVisitor extends RecursiveAstVisitor<void> {
  final names = <String>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    names.add(node.methodName.name);
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    names.add(node.function.toSource());
    super.visitFunctionExpressionInvocation(node);
  }
}

void main() {
  test('subscription issue shell stays a bounded lifecycle adapter', () {
    final shell = _source('sheet');
    final imports = shell
        .split('\n')
        .where((line) => line.trimLeft().startsWith('import '))
        .length;
    final state = _classBody(shell, '_SubscriptionIssueFormState');

    expect(_nloc(shell), lessThanOrEqualTo(220));
    expect(imports, lessThanOrEqualTo(12));
    expect(_nloc(state), lessThanOrEqualTo(160));
    for (final forbidden in [
      '_parseMoneyMinor',
      '_parsePercentBasisPoints',
      '_installments',
      '_buildPurchase',
    ]) {
      expect(shell, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(shell, isNot(contains('switch (')));
  });

  test('every extracted subscription issue owner stays bounded', () {
    for (final suffix in [
      'models',
      'pricing',
      'controller',
      'form_view',
      'components',
    ]) {
      expect(_nloc(_source(suffix)), lessThanOrEqualTo(500), reason: suffix);
    }
    final (:source, :parsed) = _parsed('form_view');
    expect(parsed.errors, isEmpty);
    final view = parsed.unit.declarations
        .whereType<ClassDeclaration>()
        .singleWhere(
          (declaration) =>
              declaration.namePart.toSource() == 'SubscriptionIssueFormView',
        );
    final methods = view.members.whereType<MethodDeclaration>();

    for (final method in methods) {
      final visitor = _ComplexityVisitor();
      method.body.accept(visitor);
      final methodSource = source.substring(method.offset, method.end);
      expect(
        visitor.branches + 1,
        lessThanOrEqualTo(10),
        reason: '${method.name.lexeme} complexity',
      );
      expect(
        _nloc(methodSource),
        lessThanOrEqualTo(120),
        reason: '${method.name.lexeme} NLOC',
      );
    }
  });

  test('preview and commit effects are orchestrated only by controller', () {
    for (final suffix in [
      'sheet',
      'models',
      'pricing',
      'controller',
      'form_view',
      'components',
    ]) {
      final parsed = _parsed(suffix).parsed;
      expect(parsed.errors, isEmpty, reason: suffix);
      final visitor = _EffectInvocationVisitor();
      parsed.unit.accept(visitor);
      final effects = visitor.names.where(
        (name) =>
            name.endsWith('onPreview') ||
            name.endsWith('_onPreview') ||
            name.endsWith('onSubmit') ||
            name.endsWith('_onSubmit'),
      );
      if (suffix == 'controller') {
        expect(effects, containsAll(<String>['_onPreview', '_onSubmit']));
      } else {
        expect(effects, isEmpty, reason: suffix);
      }
    }
  });
}
