// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:flutter_test/flutter_test.dart';

const _widgetDirectory = 'lib/features/manager/presentation/widgets';
const _shellFilename = 'teacher_stats_widget.dart';
const _controllerFilename = 'teacher_stats_controller.dart';
const _ownerNlocLimit = 500;
const _shellNlocLimit = 240;
const _shellImportLimit = 12;
const _executableNlocLimit = 130;
const _typeNlocLimit = 420;
const _typeMemberLimit = 30;
const _cyclomaticComplexityLimit = 10;

const _requiredShellMethods = <String>{
  'initState',
  'didUpdateWidget',
  'dispose',
  'build',
};

const _requiredShellProviders = <String>{
  'magicCrmServiceProvider',
  'magicSettingsServiceProvider',
  'reportFileOpenerProvider',
};

const _controllerLifecycleMethods = <String>{
  'addListener',
  'removeListener',
  'initialize',
  'updateSharedFilter',
  'updateCorrectionPolicy',
};

const _serviceEffectMethods = <String>{
  'getTeacherStatsReport',
  'exportTeacherStatsReport',
  'setLessonsTeacherRate',
  'updateGroup',
};

Map<String, String> _discoverProductionSources() {
  final files = Directory(_widgetDirectory).listSync().whereType<File>().where((
    file,
  ) {
    final name = _basename(file.path);
    return name.startsWith('teacher_stats_') && name.endsWith('.dart');
  }).toList()..sort((left, right) => left.path.compareTo(right.path));

  return <String, String>{
    for (final file in files) _basename(file.path): file.readAsStringSync(),
  };
}

String _basename(String path) => path.replaceAll('\\', '/').split('/').last;

List<String> _auditSources(Map<String, String> sources) {
  final violations = <String>[];

  for (final entry in sources.entries) {
    final filename = entry.key;
    final result = parseString(
      content: entry.value,
      path: filename,
      throwIfDiagnostics: false,
    );

    if (result.errors.isNotEmpty) {
      violations.add(
        '$filename: parse errors: ${result.errors.map((error) => error.toString()).join('; ')}',
      );
      continue;
    }

    final unit = result.unit;
    final ownerNloc = _tokenNloc(unit, result.lineInfo);
    if (ownerNloc > _ownerNlocLimit) {
      violations.add(
        '$filename: owner NLOC $ownerNloc exceeds $_ownerNlocLimit',
      );
    }

    if (filename == _shellFilename) {
      if (ownerNloc > _shellNlocLimit) {
        violations.add(
          '$filename: shell NLOC $ownerNloc exceeds $_shellNlocLimit',
        );
      }
      final imports = unit.directives.whereType<ImportDirective>().length;
      if (imports > _shellImportLimit) {
        violations.add(
          '$filename: shell imports $imports exceeds $_shellImportLimit',
        );
      }
    }

    unit.accept(
      _StructureAuditVisitor(
        filename: filename,
        lineInfo: result.lineInfo,
        violations: violations,
      ),
    );
    unit.accept(
      _ExecutableAuditVisitor(
        filename: filename,
        lineInfo: result.lineInfo,
        violations: violations,
      ),
    );

    final symbols = _OwnershipSymbols();
    unit.accept(_OwnershipSeedVisitor(symbols));
    var changed = true;
    while (changed) {
      final aliasVisitor = _OwnershipAliasVisitor(symbols);
      unit.accept(aliasVisitor);
      changed = aliasVisitor.changed;
    }

    final ownership = _OwnershipAuditVisitor(
      filename: filename,
      symbols: symbols,
      violations: violations,
    );
    unit.accept(ownership);

    if (filename == _shellFilename) {
      _auditShellContract(filename, ownership, violations);
    }
  }

  return violations.toSet().toList()..sort();
}

void _auditShellContract(
  String filename,
  _OwnershipAuditVisitor ownership,
  List<String> violations,
) {
  if (!ownership.classNames.contains('TeacherStatsWidget')) {
    violations.add('$filename: TeacherStatsWidget shell class missing');
  }
  for (final method in _requiredShellMethods.difference(
    ownership.methodNames,
  )) {
    violations.add('$filename: shell lifecycle method $method missing');
  }
  for (final provider in _requiredShellProviders.difference(
    ownership.readProviders,
  )) {
    violations.add('$filename: shell provider read $provider missing');
  }
}

int _tokenNloc(AstNode node, LineInfo lineInfo) {
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

class _StructureAuditVisitor extends RecursiveAstVisitor<void> {
  _StructureAuditVisitor({
    required this.filename,
    required this.lineInfo,
    required this.violations,
  });

  final String filename;
  final LineInfo lineInfo;
  final List<String> violations;

  void _auditType(String name, AstNode node, int memberCount) {
    final nloc = _tokenNloc(node, lineInfo);
    if (nloc > _typeNlocLimit) {
      violations.add(
        '$filename: type $name NLOC $nloc exceeds $_typeNlocLimit',
      );
    }
    if (memberCount > _typeMemberLimit) {
      violations.add(
        '$filename: type $name members $memberCount exceeds $_typeMemberLimit',
      );
    }
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final body = node.body;
    final memberCount = body is BlockClassBody ? body.members.length : 0;
    _auditType(node.namePart.typeName.lexeme, node, memberCount);
    super.visitClassDeclaration(node);
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    _auditType(node.name.lexeme, node, node.body.members.length);
    super.visitMixinDeclaration(node);
  }

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    _auditType(
      node.name?.lexeme ?? '<unnamed extension>',
      node,
      node.body.members.length,
    );
    super.visitExtensionDeclaration(node);
  }
}

class _ExecutableAuditVisitor extends RecursiveAstVisitor<void> {
  _ExecutableAuditVisitor({
    required this.filename,
    required this.lineInfo,
    required this.violations,
  });

  final String filename;
  final LineInfo lineInfo;
  final List<String> violations;

  void _audit(String name, FunctionBody body) {
    final nloc = _tokenNloc(body, lineInfo);
    if (nloc > _executableNlocLimit) {
      violations.add(
        '$filename: executable $name NLOC $nloc exceeds $_executableNlocLimit',
      );
    }

    final complexity = _CyclomaticComplexityVisitor();
    body.accept(complexity);
    if (complexity.value > _cyclomaticComplexityLimit) {
      violations.add(
        '$filename: executable $name CCN ${complexity.value} exceeds $_cyclomaticComplexityLimit',
      );
    }
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _audit(node.name.lexeme, node.body);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final line = lineInfo.getLocation(node.offset).lineNumber;
    _audit('<constructor@$line>', node.body);
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    final parent = node.parent;
    final line = lineInfo.getLocation(node.offset).lineNumber;
    final name = parent is FunctionDeclaration
        ? parent.name.lexeme
        : '<closure@$line>';
    _audit(name, node.body);
    super.visitFunctionExpression(node);
  }
}

class _CyclomaticComplexityVisitor extends RecursiveAstVisitor<void> {
  var value = 1;

  void _branch(AstNode node) {
    value += 1;
    node.visitChildren(this);
  }

  @override
  void visitIfStatement(IfStatement node) => _branch(node);

  @override
  void visitForStatement(ForStatement node) => _branch(node);

  @override
  void visitWhileStatement(WhileStatement node) => _branch(node);

  @override
  void visitDoStatement(DoStatement node) => _branch(node);

  @override
  void visitConditionalExpression(ConditionalExpression node) => _branch(node);

  @override
  void visitCatchClause(CatchClause node) => _branch(node);

  @override
  void visitIfElement(IfElement node) => _branch(node);

  @override
  void visitForElement(ForElement node) => _branch(node);

  @override
  void visitSwitchCase(SwitchCase node) => _branch(node);

  @override
  void visitSwitchPatternCase(SwitchPatternCase node) => _branch(node);

  @override
  void visitSwitchExpressionCase(SwitchExpressionCase node) => _branch(node);

  @override
  void visitBinaryExpression(BinaryExpression node) {
    if (node.operator.lexeme == '&&' || node.operator.lexeme == '||') {
      value += 1;
    }
    super.visitBinaryExpression(node);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    // Nested closures are audited independently.
  }
}

class _OwnershipSymbols {
  final crm = <String>{};
  final controllers = <String>{};
  final refs = <String>{'ref'};
}

class _OwnershipSeedVisitor extends RecursiveAstVisitor<void> {
  _OwnershipSeedVisitor(this.symbols);

  final _OwnershipSymbols symbols;

  @override
  void visitVariableDeclarationList(VariableDeclarationList node) {
    _addTypedNames(
      node.type,
      node.variables.map((variable) => variable.name.lexeme),
    );
    super.visitVariableDeclarationList(node);
  }

  @override
  void visitSimpleFormalParameter(SimpleFormalParameter node) {
    final name = node.name?.lexeme;
    if (name != null) _addTypedNames(node.type, <String>[name]);
    super.visitSimpleFormalParameter(node);
  }

  void _addTypedNames(TypeAnnotation? type, Iterable<String> names) {
    final typeName = type?.toSource();
    if (typeName == 'MagicCrmService') symbols.crm.addAll(names);
    if (typeName == 'TeacherStatsController') {
      symbols.controllers.addAll(names);
    }
  }
}

class _OwnershipAliasVisitor extends RecursiveAstVisitor<void> {
  _OwnershipAliasVisitor(this.symbols);

  final _OwnershipSymbols symbols;
  var changed = false;

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final source = _expressionIdentifier(node.initializer);
    final target = node.name.lexeme;
    if (source != null) {
      changed = _copyAlias(symbols.crm, source, target) || changed;
      changed = _copyAlias(symbols.controllers, source, target) || changed;
      changed = _copyAlias(symbols.refs, source, target) || changed;
    }
    super.visitVariableDeclaration(node);
  }

  bool _copyAlias(Set<String> names, String source, String target) {
    return names.contains(source) && names.add(target);
  }
}

class _OwnershipAuditVisitor extends RecursiveAstVisitor<void> {
  _OwnershipAuditVisitor({
    required this.filename,
    required this.symbols,
    required this.violations,
  });

  final String filename;
  final _OwnershipSymbols symbols;
  final List<String> violations;
  final classNames = <String>{};
  final methodNames = <String>{};
  final readProviders = <String>{};

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    classNames.add(node.namePart.typeName.lexeme);
    super.visitClassDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    methodNames.add(node.name.lexeme);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final method = node.methodName.name;
    final target = _expressionIdentifier(node.target);
    final provider = _providerRead(node, symbols.refs);

    if (provider != null) {
      readProviders.add(provider);
      if (filename != _shellFilename) {
        violations.add('$filename: provider read outside shell');
      }
    }

    final crmTarget = target != null && symbols.crm.contains(target);
    final providerCrmTarget =
        node.target is MethodInvocation &&
        _providerRead(node.target! as MethodInvocation, symbols.refs) ==
            'magicCrmServiceProvider';
    if (filename != _controllerFilename &&
        (crmTarget ||
            providerCrmTarget ||
            _serviceEffectMethods.contains(method))) {
      violations.add(
        '$filename: MagicCrmService invocation $method outside controller',
      );
    }

    if (filename != _shellFilename &&
        target != null &&
        symbols.controllers.contains(target) &&
        _controllerLifecycleMethods.contains(method)) {
      violations.add(
        '$filename: controller lifecycle invocation $method outside shell',
      );
    }
    super.visitMethodInvocation(node);
  }
}

String? _providerRead(MethodInvocation node, Set<String> refs) {
  final target = _expressionIdentifier(node.target);
  if (target == null || !refs.contains(target)) return null;
  if (node.methodName.name != 'read' && node.methodName.name != 'watch') {
    return null;
  }
  for (final argument in node.argumentList.arguments) {
    if (argument is SimpleIdentifier) return argument.name;
  }
  return null;
}

String? _expressionIdentifier(Expression? expression) {
  if (expression is SimpleIdentifier) return expression.name;
  if (expression is PrefixedIdentifier) return expression.identifier.name;
  if (expression is PropertyAccess) return expression.propertyName.name;
  if (expression is ParenthesizedExpression) {
    return _expressionIdentifier(expression.expression);
  }
  return null;
}

void main() {
  test('all discovered teacher statistics owners pass the AST guard', () {
    final sources = _discoverProductionSources();

    expect(sources, isNotEmpty);
    expect(sources.keys, contains(_shellFilename));
    expect(_auditSources(sources), isEmpty);
  });

  test('AST ownership rejects aliased and renamed boundary effects', () {
    final violations = _auditSources({
      'teacher_stats_hidden.dart': '''
void leak(MagicCrmService crm, dynamic ref) {
  final serviceAlias = crm;
  final refAlias = ref;
  serviceAlias . renamedEffect ();
  refAlias . read (magicCrmServiceProvider);
}
''',
    });

    expect(
      violations,
      containsAll(<String>[
        'teacher_stats_hidden.dart: MagicCrmService invocation renamedEffect outside controller',
        'teacher_stats_hidden.dart: provider read outside shell',
      ]),
    );
  });

  test('AST complexity counts every supported decision shape', () {
    final violations = _auditSources({
      'teacher_stats_tangled.dart': '''
int tangled(List<int> values, int x) {
  if (x > 0) x++;
  for (final value in values) { x += value; }
  while (x < 3) { x++; }
  do { x--; } while (x > 20);
  try { x++; } catch (_) { x--; }
  final choice = x > 0 ? 1 : 0;
  final boolean = x > 0 && x < 10 || x == 20;
  final collection = <int>[
    if (x > 0) choice,
    for (final value in values) value,
  ];
  return switch (x) { 1 => collection.length, _ => boolean ? 1 : 0 };
}
''',
    });

    expect(violations.any((violation) => violation.contains('CCN ')), isTrue);
  });

  test('dynamic discovery audits new owners and rejects malformed Dart', () {
    final methods = List.generate(
      31,
      (index) => 'void m$index() {}',
    ).join('\n');
    final violations = _auditSources({
      'teacher_stats_surprise.dart': 'class Surprise {\n$methods\n}',
      'teacher_stats_broken.dart': 'void broken( {',
    });

    expect(
      violations.any(
        (violation) =>
            violation.contains('type Surprise members 31 exceeds 30'),
      ),
      isTrue,
    );
    expect(
      violations.any((violation) => violation.contains('parse errors:')),
      isTrue,
    );
  });
}
