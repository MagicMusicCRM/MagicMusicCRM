import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

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
  final _scopes = <Map<String, _Binding>>[{}];
  final _values = <int, _FlowValue>{};
  final _cascadeTargets = <_FlowValue>[];
  var _nextBindingId = 0;

  @override
  void visitBlock(Block node) {
    _pushScope();
    super.visitBlock(node);
    _popScope();
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _pushScope();
    final body = node.body;
    if (body is! BlockClassBody) {
      _popScope();
      return;
    }
    final members = body.members;
    final fields = _registerFields(members.whereType<FieldDeclaration>());
    final baseState = _capture(fields);
    final states = members
        .whereType<ConstructorDeclaration>()
        .map((constructor) => _constructorState(constructor, fields, baseState))
        .toList();
    _restore(_joinStates(states.isEmpty ? [baseState] : states));
    for (final method in members.whereType<MethodDeclaration>()) {
      _visitExecutable(method.parameters, method.body);
    }
    _popScope();
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
    _declare(node.name.lexeme, _evaluate(node.initializer));
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

  List<_Binding> _registerFields(Iterable<FieldDeclaration> declarations) {
    final fields = <_Binding>[];
    for (final declaration in declarations) {
      for (final variable in declaration.fields.variables) {
        fields.add(
          _declare(variable.name.lexeme, _evaluate(variable.initializer)),
        );
      }
    }
    return fields;
  }

  Map<int, _FlowValue> _constructorState(
    ConstructorDeclaration node,
    List<_Binding> fields,
    Map<int, _FlowValue> baseState,
  ) {
    _restore(baseState);
    final outerState = Map<int, _FlowValue>.from(_values);
    _pushScope();
    _declareParameters(node.parameters);
    _applyFieldFormals(node.parameters);
    for (final initializer in node.initializers) {
      _visitConstructorInitializer(initializer);
    }
    node.body.accept(this);
    final result = _capture(fields);
    _popScope();
    _restore(outerState);
    return result;
  }

  void _visitConstructorInitializer(ConstructorInitializer initializer) {
    if (initializer is ConstructorFieldInitializer) {
      _assign(initializer.fieldName.name, _evaluate(initializer.expression));
      return;
    }
    initializer.visitChildren(this);
  }

  void _applyFieldFormals(FormalParameterList parameters) {
    for (final parameter in parameters.parameters) {
      final unwrapped = _unwrapParameter(parameter);
      if (unwrapped is FieldFormalParameter) {
        final name = unwrapped.name.lexeme;
        _assignOuter(name, _read(name));
      }
    }
  }

  void _visitExecutable(FormalParameterList? parameters, FunctionBody body) {
    final outerState = Map<int, _FlowValue>.from(_values);
    _pushScope();
    if (parameters != null) _declareParameters(parameters);
    body.accept(this);
    _popScope();
    _restore(outerState);
  }

  void _declareParameters(FormalParameterList parameters) {
    for (final parameter in parameters.parameters) {
      final name = _unwrapParameter(parameter).name?.lexeme;
      if (name != null) _declare(name, _FlowValue.symbol(name));
    }
  }

  FormalParameter _unwrapParameter(FormalParameter parameter) =>
      parameter is DefaultFormalParameter ? parameter.parameter : parameter;

  _FlowValue _evaluate(Expression? expression) {
    if (expression == null) return _FlowValue.empty;
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

  _FlowValue _evaluateValue(Expression expression) {
    if (expression is SimpleIdentifier) return _read(expression.name);
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
      return _FlowValue.empty;
    }
    expression.visitChildren(this);
    return _FlowValue.empty;
  }

  _FlowValue _evaluateMember(Expression? target, String memberName) {
    final receiver = _evaluate(target);
    if (memberName == 'read' || memberName == 'watch') {
      return _FlowValue(readReceivers: receiver.symbols);
    }
    return _FlowValue.symbol(memberName);
  }

  _FlowValue _evaluateMethodInvocation(MethodInvocation node) {
    final callable = node.target == null && !node.isCascaded
        ? _read(node.methodName.name)
        : _FlowValue.empty;
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
    return _FlowValue.empty;
  }

  _FlowValue _evaluateFunctionInvocation(FunctionExpressionInvocation node) {
    final callable = _evaluate(node.function);
    final arguments = _evaluateArguments(node.argumentList);
    return _serviceValue(callable.readReceivers, arguments);
  }

  List<_FlowValue> _evaluateArguments(ArgumentList arguments) =>
      arguments.arguments.map(_evaluate).toList();

  _FlowValue _serviceValue(Set<String> receivers, List<_FlowValue> arguments) {
    if (receivers.isEmpty || arguments.isEmpty) return _FlowValue.empty;
    final providers = arguments.first.symbols;
    if (providers.isEmpty) return _FlowValue.empty;
    return _FlowValue(
      services: [
        _ProviderOrigin(providerSymbols: providers, receiverSymbols: receivers),
      ],
    );
  }

  _FlowValue _evaluateAssignment(AssignmentExpression node) {
    final value = _evaluate(node.rightHandSide);
    if (node.operator.lexeme == '=') {
      final name = _assignedName(node.leftHandSide);
      if (name != null) _assign(name, value);
    }
    return value;
  }

  _FlowValue _evaluateCascade(CascadeExpression node) {
    final target = _evaluate(node.target);
    _cascadeTargets.add(target);
    for (final section in node.cascadeSections) {
      _evaluate(section);
    }
    _cascadeTargets.removeLast();
    return target;
  }

  void _recordInvocation(String name, int offset, _FlowValue receiver) {
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

  _Binding _declare(String name, _FlowValue value) {
    final binding = _Binding(_nextBindingId++);
    _scopes.last[name] = binding;
    _values[binding.id] = value;
    return binding;
  }

  _FlowValue _read(String name) {
    final binding = _lookup(name);
    return binding == null ? _FlowValue.symbol(name) : _values[binding.id]!;
  }

  void _assign(String name, _FlowValue value) {
    final binding = _lookup(name);
    if (binding != null) _values[binding.id] = value;
  }

  void _assignOuter(String name, _FlowValue value) {
    final binding = _lookup(name, skipCurrent: true);
    if (binding != null) _values[binding.id] = value;
  }

  _Binding? _lookup(String name, {bool skipCurrent = false}) {
    final start = _scopes.length - (skipCurrent ? 2 : 1);
    for (var index = start; index >= 0; index--) {
      final binding = _scopes[index][name];
      if (binding != null) return binding;
    }
    return null;
  }

  Map<int, _FlowValue> _capture(Iterable<_Binding> bindings) => {
    for (final binding in bindings) binding.id: _values[binding.id]!,
  };

  Map<int, _FlowValue> _joinStates(List<Map<int, _FlowValue>> states) {
    final result = <int, _FlowValue>{};
    for (final state in states) {
      for (final entry in state.entries) {
        result.update(
          entry.key,
          (value) => value.mergedWith(entry.value),
          ifAbsent: () => entry.value,
        );
      }
    }
    return result;
  }

  void _restore(Map<int, _FlowValue> state) {
    for (final entry in state.entries) {
      if (_values.containsKey(entry.key)) _values[entry.key] = entry.value;
    }
  }

  void _pushScope() => _scopes.add({});

  void _popScope() {
    final removed = _scopes.removeLast();
    for (final binding in removed.values) {
      _values.remove(binding.id);
    }
  }
}

class _Binding {
  const _Binding(this.id);

  final int id;
}

class _FlowValue {
  const _FlowValue({
    this.symbols = const {},
    this.readReceivers = const {},
    this.services = const [],
  });

  factory _FlowValue.symbol(String name) => _FlowValue(symbols: {name});

  static const empty = _FlowValue();

  final Set<String> symbols;
  final Set<String> readReceivers;
  final List<_ProviderOrigin> services;

  _FlowValue mergedWith(_FlowValue other) => _FlowValue(
    symbols: {...symbols, ...other.symbols},
    readReceivers: {...readReceivers, ...other.readReceivers},
    services: {...services, ...other.services}.toList(),
  );
}

class _ProviderOrigin {
  const _ProviderOrigin({
    required this.providerSymbols,
    required this.receiverSymbols,
  });

  final Set<String> providerSymbols;
  final Set<String> receiverSymbols;
}
