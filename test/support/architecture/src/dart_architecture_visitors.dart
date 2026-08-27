import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

ArchitectureAstData collectArchitectureAst(
  CompilationUnit unit,
  LineInfo lineInfo,
) {
  final executableVisitor = _ExecutableVisitor(lineInfo);
  final typeVisitor = _TypeVisitor(lineInfo);
  final ownershipVisitor = _OwnershipVisitor();
  unit.accept(executableVisitor);
  unit.accept(typeVisitor);
  unit.accept(ownershipVisitor);
  return ArchitectureAstData(
    executables: executableVisitor.metrics,
    types: typeVisitor.metrics,
    declaredTypes: typeVisitor.declaredTypes,
    methodNames: typeVisitor.methodNames,
    invocations: ownershipVisitor.invocations,
    aliases: AstAliasOwnership(
      aliasSources: ownershipVisitor.aliasSources,
      declaredTypes: ownershipVisitor.declaredTypes,
    ),
  );
}

int tokenNloc(AstNode node, LineInfo lineInfo) {
  final lines = <int>{};
  var token = node.beginToken;
  while (true) {
    lines.add(lineInfo.getLocation(token.offset).lineNumber);
    if (identical(token, node.endToken)) break;
    final next = token.next;
    if (next == null) break;
    token = next;
  }
  return lines.length;
}

class ArchitectureAstData {
  const ArchitectureAstData({
    required this.executables,
    required this.types,
    required this.declaredTypes,
    required this.methodNames,
    required this.invocations,
    required this.aliases,
  });

  final List<ExecutableMetric> executables;
  final List<TypeMetric> types;
  final Set<String> declaredTypes;
  final Set<String> methodNames;
  final List<AstInvocation> invocations;
  final AstAliasOwnership aliases;
}

class ExecutableMetric {
  const ExecutableMetric({
    required this.name,
    required this.ccn,
    required this.nloc,
    required this.switchCount,
  });

  final String name;
  final int ccn;
  final int nloc;
  final int switchCount;
}

class TypeMetric {
  const TypeMetric({
    required this.name,
    required this.nloc,
    required this.memberCount,
    required this.callableCount,
  });

  final String name;
  final int nloc;
  final int memberCount;
  final int callableCount;
}

class AstInvocation {
  const AstInvocation({
    required this.name,
    required this.targetIdentifier,
    required this.argumentIdentifiers,
    required this.providerTargetIdentifier,
    required this.providerReceiverIdentifier,
  });

  final String name;
  final String? targetIdentifier;
  final Set<String> argumentIdentifiers;
  final String? providerTargetIdentifier;
  final String? providerReceiverIdentifier;
}

class AstAliasOwnership {
  const AstAliasOwnership({
    required Map<String, String> aliasSources,
    required Map<String, String> declaredTypes,
  }) : _aliasSources = aliasSources,
       _declaredTypes = declaredTypes;

  final Map<String, String> _aliasSources;
  final Map<String, String> _declaredTypes;

  Set<String> identifiers({
    Set<String> names = const {},
    Set<String> typeNames = const {},
  }) {
    final owned = <String>{...names};
    for (final entry in _declaredTypes.entries) {
      if (typeNames.contains(entry.value)) owned.add(entry.key);
    }
    var changed = true;
    while (changed) {
      changed = false;
      for (final entry in _aliasSources.entries) {
        if (owned.contains(entry.value) && owned.add(entry.key)) changed = true;
      }
    }
    return owned;
  }
}

class _ExecutableVisitor extends RecursiveAstVisitor<void> {
  _ExecutableVisitor(this.lineInfo);

  final LineInfo lineInfo;
  final metrics = <ExecutableMetric>[];

  void _record(String name, FunctionBody body) {
    final complexity = _CyclomaticComplexityVisitor();
    body.accept(complexity);
    metrics.add(
      ExecutableMetric(
        name: name,
        ccn: complexity.value,
        nloc: tokenNloc(body, lineInfo),
        switchCount: complexity.switchCount,
      ),
    );
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _record(node.name.lexeme, node.functionExpression.body);
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _record(node.name.lexeme, node.body);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final suffix = node.name?.lexeme;
    _record(
      suffix == null ? '<constructor>' : '<constructor>.$suffix',
      node.body,
    );
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    if (node.parent is! FunctionDeclaration) {
      _record('<closure>@${node.offset}', node.body);
    }
    super.visitFunctionExpression(node);
  }
}

class _CyclomaticComplexityVisitor extends RecursiveAstVisitor<void> {
  var value = 1;
  var switchCount = 0;

  void _decision(AstNode node) {
    value++;
    node.visitChildren(this);
  }

  @override
  void visitIfStatement(IfStatement node) => _decision(node);
  @override
  void visitForStatement(ForStatement node) => _decision(node);
  @override
  void visitWhileStatement(WhileStatement node) => _decision(node);
  @override
  void visitDoStatement(DoStatement node) => _decision(node);
  @override
  void visitConditionalExpression(ConditionalExpression node) =>
      _decision(node);
  @override
  void visitCatchClause(CatchClause node) => _decision(node);
  @override
  void visitIfElement(IfElement node) => _decision(node);
  @override
  void visitForElement(ForElement node) => _decision(node);
  @override
  void visitSwitchStatement(SwitchStatement node) {
    switchCount++;
    super.visitSwitchStatement(node);
  }

  @override
  void visitSwitchExpression(SwitchExpression node) {
    switchCount++;
    super.visitSwitchExpression(node);
  }

  @override
  void visitSwitchCase(SwitchCase node) => _decision(node);
  @override
  void visitSwitchPatternCase(SwitchPatternCase node) => _decision(node);
  @override
  void visitSwitchExpressionCase(SwitchExpressionCase node) => _decision(node);

  @override
  void visitBinaryExpression(BinaryExpression node) {
    if (node.operator.lexeme == '&&' || node.operator.lexeme == '||') value++;
    super.visitBinaryExpression(node);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {}

  @override
  void visitFunctionDeclarationStatement(FunctionDeclarationStatement node) {}
}

class _TypeVisitor extends RecursiveAstVisitor<void> {
  _TypeVisitor(this.lineInfo);

  final LineInfo lineInfo;
  final metrics = <TypeMetric>[];
  final declaredTypes = <String>{};
  final methodNames = <String>{};

  void _record(String name, AstNode node, List<ClassMember> members) {
    declaredTypes.add(name);
    metrics.add(
      TypeMetric(
        name: name,
        nloc: tokenNloc(node, lineInfo),
        memberCount: members.length,
        callableCount: members
            .where(
              (member) =>
                  member is MethodDeclaration ||
                  member is ConstructorDeclaration,
            )
            .length,
      ),
    );
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final body = node.body;
    _record(
      node.namePart.typeName.lexeme,
      node,
      body is BlockClassBody ? body.members : const <ClassMember>[],
    );
    super.visitClassDeclaration(node);
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    _record(node.name.lexeme, node, node.body.members);
    super.visitMixinDeclaration(node);
  }

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    _record(
      node.name?.lexeme ?? '<unnamed extension>',
      node,
      node.body.members,
    );
    super.visitExtensionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    methodNames.add(node.name.lexeme);
    super.visitMethodDeclaration(node);
  }
}

class _OwnershipVisitor extends RecursiveAstVisitor<void> {
  final aliasSources = <String, String>{};
  final declaredTypes = <String, String>{};
  final invocations = <AstInvocation>[];

  @override
  void visitVariableDeclarationList(VariableDeclarationList node) {
    final type = _typeName(node.type);
    if (type != null) {
      for (final variable in node.variables) {
        declaredTypes[variable.name.lexeme] = type;
      }
    }
    super.visitVariableDeclarationList(node);
  }

  @override
  void visitSimpleFormalParameter(SimpleFormalParameter node) {
    final name = node.name?.lexeme;
    final type = _typeName(node.type);
    if (name != null && type != null) declaredTypes[name] = type;
    super.visitSimpleFormalParameter(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    _recordAlias(node.name.lexeme, node.initializer);
    super.visitVariableDeclaration(node);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    final target = _expressionIdentifier(node.leftHandSide);
    if (target != null) _recordAlias(target, node.rightHandSide);
    super.visitAssignmentExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target;
    final providerTarget =
        target is MethodInvocation &&
            (target.methodName.name == 'read' ||
                target.methodName.name == 'watch')
        ? target
        : null;
    invocations.add(
      AstInvocation(
        name: node.methodName.name,
        targetIdentifier: _expressionIdentifier(target),
        argumentIdentifiers: node.argumentList.arguments
            .map(_expressionIdentifier)
            .whereType<String>()
            .toSet(),
        providerTargetIdentifier: providerTarget?.argumentList.arguments
            .map(_expressionIdentifier)
            .whereType<String>()
            .firstOrNull,
        providerReceiverIdentifier: _expressionIdentifier(
          providerTarget?.target,
        ),
      ),
    );
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    final name = _expressionIdentifier(node.function);
    if (name != null) {
      invocations.add(
        AstInvocation(
          name: name,
          targetIdentifier: null,
          argumentIdentifiers: node.argumentList.arguments
              .map(_expressionIdentifier)
              .whereType<String>()
              .toSet(),
          providerTargetIdentifier: null,
          providerReceiverIdentifier: null,
        ),
      );
    }
    super.visitFunctionExpressionInvocation(node);
  }

  void _recordAlias(String target, Expression? expression) {
    final source = _expressionIdentifier(expression);
    if (source != null) aliasSources[target] = source;
  }
}

String? _typeName(TypeAnnotation? type) => type?.toSource().replaceAll('?', '');

String? _expressionIdentifier(Expression? expression) {
  if (expression is SimpleIdentifier) return expression.name;
  if (expression is PrefixedIdentifier) return expression.identifier.name;
  if (expression is PropertyAccess) return expression.propertyName.name;
  if (expression is ParenthesizedExpression) {
    return _expressionIdentifier(expression.expression);
  }
  return null;
}
