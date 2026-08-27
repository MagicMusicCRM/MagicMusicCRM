import 'package:analyzer/dart/ast/ast.dart';

import 'dart_provider_flow_state.dart';

typedef ProviderExpressionEvaluator =
    ProviderFlowValue Function(Expression? expression);

Expression? transparentProviderFlowOperand(Expression expression) {
  if (expression is AsExpression) return expression.expression;
  if (expression is AwaitExpression) return expression.expression;
  return null;
}

ProviderFlowValue evaluateConditionalProviderFlow({
  required ConditionalExpression expression,
  required ProviderFlowState state,
  required ProviderExpressionEvaluator evaluate,
}) {
  evaluate(expression.condition);
  final before = state.snapshot();
  final paths = [
    _evaluatePath(expression.thenExpression, before, state, evaluate),
    _evaluatePath(expression.elseExpression, before, state, evaluate),
  ];
  return _joinExpressionPaths(paths, state);
}

ProviderFlowValue evaluateSwitchProviderFlow({
  required SwitchExpression expression,
  required ProviderFlowState state,
  required ProviderExpressionEvaluator evaluate,
}) {
  evaluate(expression.expression);
  final before = state.snapshot();
  final paths = <_ExpressionPath>[];
  for (final switchCase in expression.cases) {
    state.restore(before);
    evaluate(switchCase.guardedPattern.whenClause?.expression);
    paths.add(
      _evaluatePath(switchCase.expression, state.snapshot(), state, evaluate),
    );
  }
  return _joinExpressionPaths(paths, state);
}

_ExpressionPath _evaluatePath(
  Expression expression,
  ProviderFlowSnapshot start,
  ProviderFlowState state,
  ProviderExpressionEvaluator evaluate,
) {
  state.restore(start);
  final value = evaluate(expression);
  return _ExpressionPath(value, state.snapshot());
}

ProviderFlowValue _joinExpressionPaths(
  List<_ExpressionPath> paths,
  ProviderFlowState state,
) {
  state.restore(state.join(paths.map((path) => path.state)));
  var value = ProviderFlowValue.empty;
  for (final path in paths) {
    value = value.mergedWith(path.value);
  }
  return value;
}

class _ExpressionPath {
  const _ExpressionPath(this.value, this.state);

  final ProviderFlowValue value;
  final ProviderFlowSnapshot state;
}
