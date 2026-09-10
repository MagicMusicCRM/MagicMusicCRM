import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

/// Checks the call's own argument; dynamic labels still need runtime semantics.
List<String> findMissingIconTooltips(
  String source, {
  String path = 'input.dart',
}) {
  final parsed = parseString(
    content: source,
    path: path,
    throwIfDiagnostics: false,
  );
  if (parsed.errors.isNotEmpty) {
    throw FormatException(
      'Cannot inspect invalid Dart: $path: ${parsed.errors.first}',
    );
  }
  final visitor = _IconTooltipVisitor(path, parsed.lineInfo);
  parsed.unit.accept(visitor);
  return visitor.missing;
}

class _IconTooltipVisitor extends RecursiveAstVisitor<void> {
  _IconTooltipVisitor(this.path, this.lines);

  final String path;
  final LineInfo lines;
  final missing = <String>[];

  void check(
    String type,
    String? constructor,
    ArgumentList arguments,
    int offset,
  ) {
    if (type != 'IconButton' && type != 'FloatingActionButton') return;
    final constructors = type == 'IconButton'
        ? const {null, 'filled', 'filledTonal', 'outlined'}
        : const {null, 'small', 'large'};
    if (!constructors.contains(constructor)) return;
    final tooltip = arguments.arguments
        .whereType<NamedExpression>()
        .where((argument) => argument.name.label.name == 'tooltip')
        .map((argument) => argument.expression)
        .firstOrNull;
    if (tooltip == null ||
        tooltip is NullLiteral ||
        (tooltip is StringLiteral &&
            tooltip.stringValue?.trim().isEmpty == true)) {
      missing.add('$path:${lines.getLocation(offset).lineNumber}');
    }
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    // The parser can read `Type.named` as a prefixed type before resolution.
    final names = node.constructorName.toSource().split('.');
    final index = names.indexWhere(
      (name) => name == 'IconButton' || name == 'FloatingActionButton',
    );
    if (index >= 0) {
      check(
        names[index],
        names.length > index + 1 ? names[index + 1] : null,
        node.argumentList,
        node.offset,
      );
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // Without resolution, implicit constructor calls can be method invocations.
    final method = node.methodName.name;
    final target = node.target?.toSource().split('.').last;
    if (method == 'IconButton' || method == 'FloatingActionButton') {
      check(method, null, node.argumentList, node.offset);
    } else if (target != null) {
      check(target, method, node.argumentList, node.offset);
    }
    super.visitMethodInvocation(node);
  }
}
