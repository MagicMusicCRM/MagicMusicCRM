// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:crypto/crypto.dart';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/generate_dart_code_map.dart <lib> <output>',
    );
    exitCode = 64;
    return;
  }

  final root = Directory(args[0]);
  final files =
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final digestInput = BytesBuilder(copy: false);
  final imports = <Map<String, Object?>>[];
  final declarations = <Map<String, Object?>>[];
  final providers = <Map<String, Object?>>[];
  final apiCalls = <Map<String, Object?>>[];
  final constructorCalls = <Map<String, Object?>>[];
  final methodInvocations = <String>[];

  for (final file in files) {
    final source = file.readAsStringSync();
    final path = file.path.replaceAll('\\', '/');
    digestInput.add(utf8.encode('$path\n$source\n'));
    final parsed = parseString(content: source, path: path);
    final collector = _Collector(path, parsed.lineInfo);
    parsed.unit.accept(collector);
    imports.addAll(collector.imports);
    declarations.addAll(collector.declarations);
    providers.addAll(collector.providers);
    apiCalls.addAll(collector.apiCalls);
    constructorCalls.addAll(collector.constructorCalls);
    methodInvocations.addAll(collector.methodInvocations);
  }
  final sourceDigest = sha256.convert(digestInput.takeBytes()).toString();
  final invocationCounts = <String, int>{};
  for (final name in methodInvocations) {
    invocationCounts.update(name, (count) => count + 1, ifAbsent: () => 1);
  }
  for (final call in apiCalls) {
    call['callable_invocations'] = invocationCounts[call['callable']] ?? 0;
  }

  int count(String kind) =>
      declarations.where((row) => row['kind'] == kind).length;
  final widgets = declarations.where((row) => row['is_widget'] == true).length;
  final screens = declarations.where((row) => row['is_screen'] == true).length;
  if (files.isEmpty ||
      declarations.isEmpty ||
      widgets == 0 ||
      apiCalls.isEmpty) {
    throw StateError(
      'Incomplete Dart map: files=${files.length}, declarations=${declarations.length}, widgets=$widgets, apiCalls=${apiCalls.length}',
    );
  }

  int compareRows(Map<String, Object?> a, Map<String, Object?> b) {
    final file = '${a['file']}'.compareTo('${b['file']}');
    if (file != 0) return file;
    return (a['line'] as int).compareTo(b['line'] as int);
  }

  for (final rows in [
    imports,
    declarations,
    providers,
    apiCalls,
    constructorCalls,
  ]) {
    rows.sort(compareRows);
  }
  final output = {
    'schema_version': 1,
    'source_digest_sha256': sourceDigest,
    'scope': 'production Flutter source under lib/',
    'summary': {
      'files': files.length,
      'classes': count('class'),
      'constructors': count('constructor'),
      'methods': count('method'),
      'functions': count('function'),
      'widgets': widgets,
      'screens': screens,
      'providers': providers.length,
      'api_calls': apiCalls.length,
      'constructor_calls': constructorCalls.length,
    },
    'imports': imports,
    'declarations': declarations,
    'providers': providers,
    'api_calls': apiCalls,
    'constructor_calls': constructorCalls,
  };
  final target = File(args[1]);
  target.parent.createSync(recursive: true);
  target.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(output)}\n',
  );
  stdout.writeln(jsonEncode(output['summary']));
}

class _Collector extends RecursiveAstVisitor<void> {
  _Collector(this.file, this.lineInfo);

  final String file;
  final LineInfo lineInfo;
  final imports = <Map<String, Object?>>[];
  final declarations = <Map<String, Object?>>[];
  final providers = <Map<String, Object?>>[];
  final apiCalls = <Map<String, Object?>>[];
  final constructorCalls = <Map<String, Object?>>[];
  final methodInvocations = <String>[];
  String? _className;
  String? _callable;

  int _line(AstNode node) => lineInfo.getLocation(node.offset).lineNumber;

  @override
  void visitImportDirective(ImportDirective node) {
    imports.add({
      'uri': node.uri.stringValue,
      'file': file,
      'line': _line(node),
    });
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final previous = _className;
    final name = node.namePart.toSource();
    final supertype = node.extendsClause?.superclass.toSource();
    final isWidget = supertype?.endsWith('Widget') ?? false;
    declarations.add({
      'kind': 'class',
      'name': name,
      'extends': supertype,
      'is_widget': isWidget,
      'is_screen': isWidget && RegExp(r'(Screen|Page|View)$').hasMatch(name),
      'file': file,
      'line': _line(node),
    });
    _className = name;
    node.visitChildren(this);
    _className = previous;
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    declarations.add({
      'kind': 'constructor',
      'name':
          '${_className ?? ''}${node.name == null ? '' : '.${node.name!.lexeme}'}',
      'class': _className,
      'file': file,
      'line': _line(node),
    });
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final previous = _callable;
    _callable = node.name.lexeme;
    declarations.add({
      'kind': 'method',
      'name': node.name.lexeme,
      'class': _className,
      'return_type': node.returnType?.toSource(),
      'static': node.isStatic,
      'file': file,
      'line': _line(node),
    });
    node.visitChildren(this);
    _callable = previous;
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final previous = _callable;
    _callable = node.name.lexeme;
    declarations.add({
      'kind': 'function',
      'name': node.name.lexeme,
      'return_type': node.returnType?.toSource(),
      'file': file,
      'line': _line(node),
    });
    node.visitChildren(this);
    _callable = previous;
  }

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    for (final variable in node.variables.variables) {
      final initializer = variable.initializer?.toSource() ?? '';
      if (variable.name.lexeme.endsWith('Provider') ||
          RegExp(
            r'\b[A-Za-z]*Provider(?:\.family)?\s*\(',
          ).hasMatch(initializer)) {
        providers.add({
          'name': variable.name.lexeme,
          'declared_type': node.variables.type?.toSource(),
          'initializer': initializer,
          'file': file,
          'line': _line(variable),
        });
      }
    }
    super.visitTopLevelVariableDeclaration(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    const verbs = {
      'get',
      'post',
      'postIdempotent',
      'put',
      'patch',
      'delete',
      'request',
    };
    final method = node.methodName.name;
    methodInvocations.add(method);
    final target = node.target?.toSource() ?? '';
    if (verbs.contains(method) &&
        RegExp(r'(^|\.)_?api$|dio', caseSensitive: false).hasMatch(target)) {
      final arguments = node.argumentList.arguments;
      final isApiRequest =
          method == 'request' && !target.toLowerCase().contains('dio');
      apiCalls.add({
        'verb': method,
        'target': target,
        'http_method_expression': isApiRequest && arguments.isNotEmpty
            ? arguments.first.toSource()
            : null,
        'path_expression': arguments.length > (isApiRequest ? 1 : 0)
            ? arguments[isApiRequest ? 1 : 0].toSource()
            : null,
        'class': _className,
        'callable': _callable,
        'file': file,
        'line': _line(node),
      });
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    constructorCalls.add({
      'type': node.constructorName.type.toSource(),
      'constructor': node.constructorName.name?.name,
      'class': _className,
      'callable': _callable,
      'file': file,
      'line': _line(node),
    });
    super.visitInstanceCreationExpression(node);
  }
}
