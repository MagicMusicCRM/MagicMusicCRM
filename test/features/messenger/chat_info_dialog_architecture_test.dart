// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

const _telegramPath = 'lib/core/widgets/telegram';
const _controllerFileName = 'chat_info_controller.dart';
const _shellFileName = 'chat_info_dialog.dart';
const _maxOwnerNloc = 500;
const _maxShellNloc = 260;
const _maxShellImports = 12;
const _maxCallableCcn = 10;
const _maxCallableNloc = 100;
const _maxClassNloc = 300;
const _maxCallablesPerClass = 24;
const _serviceEffects = {
  'listMessages',
  'listChannelPosts',
  'listProfileNotes',
  'createProfileNote',
  'updateGroupMembers',
};

void main() {
  test('all chat info owners satisfy the AST architecture budget', () {
    final owners = _discoverOwnerFiles(_telegramPath);
    expect(owners, isNotEmpty);

    for (final owner in owners) {
      final inspection = _inspectFile(owner);
      expect(
        _architectureViolations(inspection),
        isEmpty,
        reason: inspection.fileName,
      );
    }

    for (final legacyName in const [
      'chat_info_dialog_views.dart',
      'chat_info_dialog_dialogs.dart',
    ]) {
      expect(
        File('$_telegramPath/$legacyName').existsSync(),
        isFalse,
        reason: '$legacyName must stay deleted',
      );
    }
  });

  test('AST guard resists lexical and fixed-owner bypasses', () {
    const trickySource = r'''
void renamedOwner(dynamic alias, bool a, bool b) {
  // updateGroupMembers(); and switch (a) are not executable code.
  const example = 'createProfileNote(); switch(a)';
  alias
      .listMessages
      ();
  if (a && b || a) {}
  for (;;) { break; }
  while (a) { break; }
  do {} while (a);
  final value = a ? 1 : 0;
  try {} catch (_) {}
  final items = [if (a) 1, for (final item in [1]) item];
  switch(a) {
    case true: break;
    case false: break;
  }
  final label = switch (a) {true => 'yes', false => 'no'};
}
''';
    final tricky = _inspectSource('chat_info_future.dart', trickySource);

    expect(tricky.parseErrors, isEmpty);
    expect(tricky.serviceEffects, {'listMessages'});
    expect(
      tricky.callables
          .singleWhere((callable) => callable.name == 'renamedOwner')
          .ccn,
      15,
    );

    final partInspection = _inspectSource(
      'chat_info_part.dart',
      "part /* comments and whitespace do not hide this */ 'owner.dart';",
    );
    expect(partInspection.parseErrors, isEmpty);
    expect(partInspection.hasPartDirective, isTrue);

    final classInspection = _inspectSource(
      'chat_info_brain.dart',
      'class FutureOwner {${List.generate(25, (index) => 'void m$index() {}').join()}}',
    );
    expect(classInspection.structures.single.callableCount, 25);
    expect(
      _architectureViolations(classInspection),
      contains(contains('25 callables')),
    );

    final fixtureDirectory = Directory.systemTemp.createTempSync(
      'chat-info-architecture-',
    );
    addTearDown(() => fixtureDirectory.deleteSync(recursive: true));
    File(
      '${fixtureDirectory.path}${Platform.pathSeparator}chat_info_future.dart',
    ).writeAsStringSync('void futureOwner() {}');
    File(
      '${fixtureDirectory.path}${Platform.pathSeparator}unrelated.dart',
    ).writeAsStringSync('void unrelated() {}');

    expect(_discoverOwnerFiles(fixtureDirectory.path).map(_fileName), [
      'chat_info_future.dart',
    ]);
  });
}

List<File> _discoverOwnerFiles(String directoryPath) {
  final owners =
      Directory(directoryPath)
          .listSync(followLinks: false)
          .whereType<File>()
          .where(
            (file) => RegExp(r'^chat_info_.*\.dart$').hasMatch(_fileName(file)),
          )
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));
  return owners;
}

_SourceInspection _inspectFile(File file) =>
    _inspectSource(_fileName(file), file.readAsStringSync());

_SourceInspection _inspectSource(String fileName, String source) {
  final result = parseString(content: source, path: fileName);
  final unit = result.unit;
  final invocationVisitor = _ServiceEffectVisitor();
  final callableVisitor = _CallableVisitor(source);
  final structureVisitor = _StructureVisitor(source);
  final declarationVisitor = _TypeDeclarationVisitor();
  unit.accept(invocationVisitor);
  unit.accept(callableVisitor);
  unit.accept(structureVisitor);
  unit.accept(declarationVisitor);

  return _SourceInspection(
    fileName: fileName,
    source: source,
    parseErrors: result.errors.map((error) => error.toString()).toList(),
    importCount: unit.directives.whereType<ImportDirective>().length,
    hasPartDirective: unit.directives.any(
      (directive) => directive is PartDirective || directive is PartOfDirective,
    ),
    serviceEffects: invocationVisitor.names,
    callables: callableVisitor.metrics,
    structures: structureVisitor.metrics,
    declaredTypes: declarationVisitor.names,
  );
}

List<String> _architectureViolations(_SourceInspection inspection) {
  final violations = <String>[];
  if (inspection.parseErrors.isNotEmpty) {
    violations.add('parse errors: ${inspection.parseErrors.join('; ')}');
  }

  final ownerLimit = inspection.fileName == _shellFileName
      ? _maxShellNloc
      : _maxOwnerNloc;
  final ownerNloc = _nloc(inspection.source);
  if (ownerNloc > ownerLimit) {
    violations.add('$ownerNloc NLOC exceeds $ownerLimit');
  }
  if (inspection.fileName == _shellFileName &&
      inspection.importCount > _maxShellImports) {
    violations.add(
      '${inspection.importCount} imports exceed $_maxShellImports',
    );
  }
  if (inspection.hasPartDirective) {
    violations.add('part/part-of directives are forbidden');
  }
  if (inspection.fileName != _controllerFileName &&
      inspection.serviceEffects.isNotEmpty) {
    violations.add(
      'service effects belong to $_controllerFileName: '
      '${inspection.serviceEffects.join(', ')}',
    );
  }

  for (final callable in inspection.callables) {
    if (callable.ccn > _maxCallableCcn) {
      violations.add(
        '${callable.name} CCN ${callable.ccn} exceeds $_maxCallableCcn',
      );
    }
    if (callable.nloc > _maxCallableNloc) {
      violations.add(
        '${callable.name} NLOC ${callable.nloc} exceeds $_maxCallableNloc',
      );
    }
  }
  for (final structure in inspection.structures) {
    if (structure.nloc > _maxClassNloc) {
      violations.add(
        '${structure.name} NLOC ${structure.nloc} exceeds $_maxClassNloc',
      );
    }
    if (structure.callableCount > _maxCallablesPerClass) {
      violations.add(
        '${structure.name} has ${structure.callableCount} callables; '
        'limit is $_maxCallablesPerClass',
      );
    }
  }
  for (final legacyType in const {'_ChatInfoViews', '_AddMembersDialogState'}) {
    if (inspection.declaredTypes.contains(legacyType)) {
      violations.add('legacy type $legacyType must stay deleted');
    }
  }
  return violations;
}

String _fileName(File file) => file.uri.pathSegments.last;

int _nloc(String source) => source
    .split('\n')
    .where((line) => line.trim().isNotEmpty && !line.trim().startsWith('//'))
    .length;

class _SourceInspection {
  const _SourceInspection({
    required this.fileName,
    required this.source,
    required this.parseErrors,
    required this.importCount,
    required this.hasPartDirective,
    required this.serviceEffects,
    required this.callables,
    required this.structures,
    required this.declaredTypes,
  });

  final String fileName;
  final String source;
  final List<String> parseErrors;
  final int importCount;
  final bool hasPartDirective;
  final Set<String> serviceEffects;
  final List<_CallableMetric> callables;
  final List<_StructureMetric> structures;
  final Set<String> declaredTypes;
}

class _CallableMetric {
  const _CallableMetric({
    required this.name,
    required this.ccn,
    required this.nloc,
  });

  final String name;
  final int ccn;
  final int nloc;
}

class _StructureMetric {
  const _StructureMetric({
    required this.name,
    required this.nloc,
    required this.callableCount,
  });

  final String name;
  final int nloc;
  final int callableCount;
}

class _ServiceEffectVisitor extends RecursiveAstVisitor<void> {
  final Set<String> names = {};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    if (_serviceEffects.contains(name)) {
      names.add(name);
    }
    super.visitMethodInvocation(node);
  }
}

class _CallableVisitor extends RecursiveAstVisitor<void> {
  _CallableVisitor(this.source);

  final String source;
  final List<_CallableMetric> metrics = [];

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

  void _record(String name, FunctionBody body) {
    final complexity = _CyclomaticComplexityVisitor();
    body.accept(complexity);
    metrics.add(
      _CallableMetric(
        name: name,
        ccn: complexity.value,
        nloc: _nloc(source.substring(body.offset, body.end)),
      ),
    );
  }
}

/// Starts at one and adds a decision for if/loops/conditional/catch, boolean
/// &&/||, collection if/for elements, and every non-default switch statement
/// or expression case. Nested functions are measured as independent callables.
class _CyclomaticComplexityVisitor extends RecursiveAstVisitor<void> {
  int value = 1;

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
  void visitSwitchCase(SwitchCase node) => _decision(node);

  @override
  void visitSwitchPatternCase(SwitchPatternCase node) => _decision(node);

  @override
  void visitSwitchExpressionCase(SwitchExpressionCase node) => _decision(node);

  @override
  void visitBinaryExpression(BinaryExpression node) {
    if (node.operator.lexeme == '&&' || node.operator.lexeme == '||') {
      value++;
    }
    super.visitBinaryExpression(node);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {}

  @override
  void visitFunctionDeclarationStatement(FunctionDeclarationStatement node) {}
}

class _StructureVisitor extends RecursiveAstVisitor<void> {
  _StructureVisitor(this.source);

  final String source;
  final List<_StructureMetric> metrics = [];

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final body = node.body;
    final members = body is BlockClassBody
        ? body.members
        : const <ClassMember>[];
    metrics.add(
      _StructureMetric(
        name: node.namePart.typeName.lexeme,
        nloc: _nloc(source.substring(node.offset, node.end)),
        callableCount: members
            .where(
              (member) =>
                  member is MethodDeclaration ||
                  member is ConstructorDeclaration,
            )
            .length,
      ),
    );
    super.visitClassDeclaration(node);
  }
}

class _TypeDeclarationVisitor extends RecursiveAstVisitor<void> {
  final Set<String> names = {};

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    names.add(node.namePart.typeName.lexeme);
    super.visitClassDeclaration(node);
  }
}
