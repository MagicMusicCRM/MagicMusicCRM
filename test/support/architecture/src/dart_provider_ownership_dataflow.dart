import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import 'dart_provider_expression_flow.dart';
import 'dart_provider_flow_state.dart';

ProviderOwnershipDataflow collectProviderOwnershipDataflow(
  CompilationUnit unit,
) {
  final visitor = _ProviderOwnershipVisitor();
  unit.accept(visitor);
  return ProviderOwnershipDataflow(visitor.invocations);
}

class ProviderOwnershipDataflow {
  const ProviderOwnershipDataflow(this.invocations);

  final List<ProviderOwnedInvocation> invocations;

  Set<String> invocationNames({
    required Set<String> providerNames,
    required Set<String> receiverNames,
  }) => invocations
      .where(
        (invocation) =>
            invocation.providerSymbols.any(providerNames.contains) &&
            invocation.receiverSymbols.any(receiverNames.contains),
      )
      .map((invocation) => invocation.name)
      .toSet();
}

class ProviderOwnedInvocation {
  const ProviderOwnedInvocation({
    required this.name,
    required this.offset,
    required this.providerSymbols,
    required this.receiverSymbols,
  });

  final String name;
  final int offset;
  final Set<String> providerSymbols;
  final Set<String> receiverSymbols;
}

class _ProviderOwnershipVisitor extends RecursiveAstVisitor<void> {
  final invocations = <ProviderOwnedInvocation>[];
  final _state = ProviderFlowState();
  final _cascadeTargets = <ProviderFlowValue>[];

  @override
  void visitBlock(Block node) {
    _state.pushScope();
    super.visitBlock(node);
    _state.popScope();
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _state.pushScope();
    final body = node.body;
    if (body is! BlockClassBody) {
      _state.popScope();
      return;
    }
    final members = body.members;
    final fields = _registerFields(members.whereType<FieldDeclaration>());
    final baseState = _state.capture(fields);
    final states = members
        .whereType<ConstructorDeclaration>()
        .map((constructor) => _constructorState(constructor, fields, baseState))
        .toList();
    final classBase = _state.join(states.isEmpty ? [baseState] : states);
    final methods = members.whereType<MethodDeclaration>().toList();
    final methodStates = methods.map(
      (method) => _methodState(method, fields, classBase),
    );
    _state.restore(_state.join([classBase, ...methodStates]));
    for (final method in methods) {
      _visitExecutable(method.parameters, method.body);
    }
    _state.popScope();
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final expression = node.functionExpression;
    _visitExecutable(expression.parameters, expression.body);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _visitExecutable(node.parameters, node.body);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    _visitExecutable(node.parameters, node.body);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    _visitExecutable(node.parameters, node.body);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    _state.declare(node.name.lexeme, _evaluate(node.initializer));
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    _evaluateAssignment(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _evaluateMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    _evaluateFunctionInvocation(node);
  }

  @override
  void visitCascadeExpression(CascadeExpression node) {
    _evaluateCascade(node);
  }

  @override
  void visitIfStatement(IfStatement node) {
    _evaluate(node.expression);
    final before = _state.snapshot();
    final thenState = _statementState(node.thenStatement, before);
    final elseStatement = node.elseStatement;
    final elseState = elseStatement == null
        ? before
        : _statementState(elseStatement, before);
    _state.restore(_state.join([thenState, elseState]));
  }

  @override
  void visitSwitchStatement(SwitchStatement node) {
    _evaluate(node.expression);
    final before = _state.snapshot();
    final states = node.members
        .map((member) => _switchMemberState(member, before))
        .toList();
    if (!node.members.any((member) => member is SwitchDefault)) {
      states.add(before);
    }
    _state.restore(_state.join(states));
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    _evaluate(node.condition);
    final before = _state.snapshot();
    final bodyState = _statementState(node.body, before);
    _state.restore(_state.join([before, bodyState]));
  }

  @override
  void visitDoStatement(DoStatement node) {
    final firstState = _statementState(node.body, _state.snapshot());
    _state.restore(firstState);
    _evaluate(node.condition);
    final afterCondition = _state.snapshot();
    final repeatedState = _statementState(node.body, afterCondition);
    _state.restore(_state.join([afterCondition, repeatedState]));
  }

  @override
  void visitForStatement(ForStatement node) {
    _state.pushScope();
    final parts = node.forLoopParts;
    _prepareForLoop(parts);
    final before = _state.snapshot();
    final bodyState = _statementState(node.body, before);
    _state.restore(bodyState);
    if (parts is ForParts) {
      for (final updater in parts.updaters) {
        _evaluate(updater);
      }
    }
    _state.restore(_state.join([before, _state.snapshot()]));
    _state.popScope();
  }

  @override
  void visitTryStatement(TryStatement node) {
    final before = _state.snapshot();
    final tryState = _statementState(node.body, before);
    final catchStart = _state.join([before, tryState]);
    final alternatives = <ProviderFlowSnapshot>[tryState];
    for (final clause in node.catchClauses) {
      alternatives.add(_catchState(clause, catchStart));
    }
    final joined = _state.join(alternatives);
    final finallyBlock = node.finallyBlock;
    _state.restore(
      finallyBlock == null ? joined : _statementState(finallyBlock, joined),
    );
  }

  List<ProviderBinding> _registerFields(
    Iterable<FieldDeclaration> declarations,
  ) {
    final fields = <ProviderBinding>[];
    for (final declaration in declarations) {
      for (final variable in declaration.fields.variables) {
        fields.add(
          _state.declare(variable.name.lexeme, _evaluate(variable.initializer)),
        );
      }
    }
    return fields;
  }

  ProviderFlowSnapshot _constructorState(
    ConstructorDeclaration node,
    List<ProviderBinding> fields,
    ProviderFlowSnapshot baseState,
  ) {
    _state.restore(baseState);
    final outerState = _state.snapshot();
    _state.pushScope();
    _declareParameters(node.parameters);
    _applyFieldFormals(node.parameters);
    for (final initializer in node.initializers) {
      _visitConstructorInitializer(initializer);
    }
    node.body.accept(this);
    final result = _state.capture(fields);
    _state.popScope();
    _state.restore(outerState);
    return result;
  }

  ProviderFlowSnapshot _methodState(
    MethodDeclaration node,
    List<ProviderBinding> fields,
    ProviderFlowSnapshot baseState,
  ) {
    _state.restore(baseState);
    final outerState = _state.snapshot();
    _state.pushScope();
    final parameters = node.parameters;
    if (parameters != null) _declareParameters(parameters);
    node.body.accept(this);
    final result = _state.capture(fields);
    _state.popScope();
    _state.restore(outerState);
    return result;
  }

  ProviderFlowSnapshot _statementState(
    Statement statement,
    ProviderFlowSnapshot start,
  ) {
    _state.restore(start);
    statement.accept(this);
    return _state.snapshot();
  }

  ProviderFlowSnapshot _switchMemberState(
    SwitchMember member,
    ProviderFlowSnapshot start,
  ) {
    _state.restore(start);
    for (final statement in member.statements) {
      statement.accept(this);
    }
    return _state.snapshot();
  }

  ProviderFlowSnapshot _catchState(
    CatchClause clause,
    ProviderFlowSnapshot start,
  ) {
    _state.restore(start);
    _state.pushScope();
    _declareCatchParameter(clause.exceptionParameter);
    _declareCatchParameter(clause.stackTraceParameter);
    clause.body.accept(this);
    _state.popScope();
    return _state.snapshot();
  }

  void _declareCatchParameter(CatchClauseParameter? parameter) {
    if (parameter != null) {
      _state.declare(parameter.name.lexeme, ProviderFlowValue.empty);
    }
  }

  void _prepareForLoop(ForLoopParts parts) {
    if (parts is ForPartsWithDeclarations) {
      parts.variables.accept(this);
    } else if (parts is ForPartsWithExpression) {
      _evaluate(parts.initialization);
    } else if (parts is ForEachPartsWithDeclaration) {
      _evaluate(parts.iterable);
      _state.declare(parts.loopVariable.name.lexeme, ProviderFlowValue.empty);
    } else if (parts is ForEachParts) {
      _evaluate(parts.iterable);
    }
    if (parts is ForParts) _evaluate(parts.condition);
  }

  void _visitConstructorInitializer(ConstructorInitializer initializer) {
    if (initializer is ConstructorFieldInitializer) {
      _state.assign(
        initializer.fieldName.name,
        _evaluate(initializer.expression),
      );
      return;
    }
    initializer.visitChildren(this);
  }

  void _applyFieldFormals(FormalParameterList parameters) {
    for (final parameter in parameters.parameters) {
      final unwrapped = _unwrapParameter(parameter);
      if (unwrapped is FieldFormalParameter) {
        final name = unwrapped.name.lexeme;
        _state.assignOuter(name, _state.read(name));
      }
    }
  }

  void _visitExecutable(FormalParameterList? parameters, FunctionBody body) {
    final outerState = _state.snapshot();
    _state.pushScope();
    if (parameters != null) _declareParameters(parameters);
    body.accept(this);
    _state.popScope();
    _state.restore(outerState);
  }

  void _declareParameters(FormalParameterList parameters) {
    for (final parameter in parameters.parameters) {
      final name = _unwrapParameter(parameter).name?.lexeme;
      if (name != null) {
        _state.declare(name, ProviderFlowValue.symbol(name));
      }
    }
  }

  FormalParameter _unwrapParameter(FormalParameter parameter) =>
      parameter is DefaultFormalParameter ? parameter.parameter : parameter;

  ProviderFlowValue _evaluate(Expression? expression) {
    if (expression == null) return ProviderFlowValue.empty;
    if (expression is MethodInvocation) {
      return _evaluateMethodInvocation(expression);
    }
    if (expression is FunctionExpressionInvocation) {
      return _evaluateFunctionInvocation(expression);
    }
    if (expression is AssignmentExpression) {
      return _evaluateAssignment(expression);
    }
    if (expression is CascadeExpression) return _evaluateCascade(expression);
    return _evaluateValue(expression);
  }

  ProviderFlowValue _evaluateValue(Expression expression) {
    if (expression is SimpleIdentifier) return _state.read(expression.name);
    final transparentOperand = transparentProviderFlowOperand(expression);
    if (transparentOperand != null) return _evaluate(transparentOperand);
    if (expression is ConditionalExpression) {
      return evaluateConditionalProviderFlow(
        expression: expression,
        state: _state,
        evaluate: _evaluate,
      );
    }
    if (expression is SwitchExpression) {
      return evaluateSwitchProviderFlow(
        expression: expression,
        state: _state,
        evaluate: _evaluate,
      );
    }
    if (expression is ParenthesizedExpression) {
      return _evaluate(expression.expression);
    }
    if (expression is PrefixedIdentifier) {
      return _evaluateMember(expression.prefix, expression.identifier.name);
    }
    if (expression is PropertyAccess) {
      return _evaluateMember(expression.target, expression.propertyName.name);
    }
    if (expression is FunctionExpression) {
      _visitExecutable(expression.parameters, expression.body);
      return ProviderFlowValue.empty;
    }
    expression.visitChildren(this);
    return ProviderFlowValue.empty;
  }

  ProviderFlowValue _evaluateMember(Expression? target, String memberName) {
    final receiver = _evaluate(target);
    if (memberName == 'read' || memberName == 'watch') {
      return ProviderFlowValue(readReceivers: receiver.symbols);
    }
    return ProviderFlowValue.symbol(memberName);
  }

  ProviderFlowValue _evaluateMethodInvocation(MethodInvocation node) {
    final callable = node.target == null && !node.isCascaded
        ? _state.read(node.methodName.name)
        : ProviderFlowValue.empty;
    final receiver = node.isCascaded && _cascadeTargets.isNotEmpty
        ? _cascadeTargets.last
        : _evaluate(node.target);
    final arguments = _evaluateArguments(node.argumentList);
    _recordInvocation(node.methodName.name, node.offset, receiver);
    if (callable.readReceivers.isNotEmpty) {
      return _serviceValue(callable.readReceivers, arguments);
    }
    if (node.methodName.name == 'read' || node.methodName.name == 'watch') {
      return _serviceValue(receiver.symbols, arguments);
    }
    return ProviderFlowValue.empty;
  }

  ProviderFlowValue _evaluateFunctionInvocation(
    FunctionExpressionInvocation node,
  ) {
    final callable = _evaluate(node.function);
    final arguments = _evaluateArguments(node.argumentList);
    return _serviceValue(callable.readReceivers, arguments);
  }

  List<ProviderFlowValue> _evaluateArguments(ArgumentList arguments) =>
      arguments.arguments.map(_evaluate).toList();

  ProviderFlowValue _serviceValue(
    Set<String> receivers,
    List<ProviderFlowValue> arguments,
  ) {
    if (receivers.isEmpty || arguments.isEmpty) {
      return ProviderFlowValue.empty;
    }
    final providers = arguments.first.symbols;
    if (providers.isEmpty) return ProviderFlowValue.empty;
    return ProviderFlowValue(
      services: [
        ProviderOrigin(providerSymbols: providers, receiverSymbols: receivers),
      ],
    );
  }

  ProviderFlowValue _evaluateAssignment(AssignmentExpression node) {
    final value = _evaluate(node.rightHandSide);
    if (node.operator.lexeme == '=') {
      final name = _assignedName(node.leftHandSide);
      if (name != null) _state.assign(name, value);
    }
    return value;
  }

  ProviderFlowValue _evaluateCascade(CascadeExpression node) {
    final target = _evaluate(node.target);
    _cascadeTargets.add(target);
    for (final section in node.cascadeSections) {
      _evaluate(section);
    }
    _cascadeTargets.removeLast();
    return target;
  }

  void _recordInvocation(String name, int offset, ProviderFlowValue receiver) {
    for (final origin in receiver.services) {
      invocations.add(
        ProviderOwnedInvocation(
          name: name,
          offset: offset,
          providerSymbols: origin.providerSymbols,
          receiverSymbols: origin.receiverSymbols,
        ),
      );
    }
  }

  String? _assignedName(Expression expression) {
    if (expression is SimpleIdentifier) return expression.name;
    if (expression is PrefixedIdentifier) return expression.identifier.name;
    if (expression is PropertyAccess) return expression.propertyName.name;
    return null;
  }
}
