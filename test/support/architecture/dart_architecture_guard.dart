import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

import 'src/dart_architecture_visitors.dart';

export 'src/dart_architecture_visitors.dart' show ExecutableMetric, TypeMetric;

/// Deterministic source metrics belong here. RepoWise health (>=7 and no
/// god/brain findings) depends on indexed history and stays a tier/global gate.
Map<String, String> discoverDartSources({
  required String directoryPath,
  required String filePrefix,
}) {
  final files =
      Directory(
          directoryPath,
        ).listSync(followLinks: false).whereType<File>().where((file) {
          final name = dartBasename(file.path);
          return name.startsWith(filePrefix) && name.endsWith('.dart');
        }).toList()
        ..sort((left, right) => left.path.compareTo(right.path));

  return <String, String>{
    for (final file in files) dartBasename(file.path): file.readAsStringSync(),
  };
}

String dartBasename(String path) => path.replaceAll('\\', '/').split('/').last;

List<DartSourceInspection> inspectDartSources(Map<String, String> sources) =>
    sources.entries
        .map((entry) => inspectDartSource(entry.key, entry.value))
        .toList();

DartSourceInspection inspectDartSource(String fileName, String source) {
  final result = parseString(
    content: source,
    path: fileName,
    throwIfDiagnostics: false,
  );
  final unit = result.unit;
  final ast = collectArchitectureAst(unit, result.lineInfo);

  return DartSourceInspection(
    fileName: fileName,
    parseErrors: result.errors.map((error) => error.toString()).toList(),
    ownerNloc: tokenNloc(unit, result.lineInfo),
    importCount: unit.directives.whereType<ImportDirective>().length,
    hasPartDirective: unit.directives.any(
      (directive) => directive is PartDirective || directive is PartOfDirective,
    ),
    executables: ast.executables,
    types: ast.types,
    declaredTypes: ast.declaredTypes,
    methodNames: ast.methodNames,
    invocations: ast.invocations,
    aliases: ast.aliases,
  );
}

class DartArchitectureBudget {
  const DartArchitectureBudget({
    this.ownerNlocLimit = 500,
    this.shellFileName,
    this.shellNlocLimit,
    this.shellImportLimit,
    this.executableCcnLimit = 10,
    this.executableNlocLimit,
    this.typeNlocLimit,
    this.typeMemberLimit,
    this.typeCallableLimit,
    this.namedTypeNlocLimits = const {},
    this.forbidPartDirectives = false,
  });

  final int ownerNlocLimit;
  final String? shellFileName;
  final int? shellNlocLimit;
  final int? shellImportLimit;
  final int executableCcnLimit;
  final int? executableNlocLimit;
  final int? typeNlocLimit;
  final int? typeMemberLimit;
  final int? typeCallableLimit;
  final Map<String, int> namedTypeNlocLimits;
  final bool forbidPartDirectives;
}

List<String> auditDartArchitecture(
  Iterable<DartSourceInspection> inspections,
  DartArchitectureBudget budget,
) {
  final violations = <String>[];
  for (final inspection in inspections) {
    final fileName = inspection.fileName;
    if (inspection.parseErrors.isNotEmpty) {
      violations.add(
        '$fileName: parse errors: ${inspection.parseErrors.join('; ')}',
      );
      continue;
    }
    if (inspection.ownerNloc > budget.ownerNlocLimit) {
      violations.add(
        '$fileName: owner NLOC ${inspection.ownerNloc} exceeds ${budget.ownerNlocLimit}',
      );
    }
    if (fileName == budget.shellFileName) {
      final shellNlocLimit = budget.shellNlocLimit;
      if (shellNlocLimit != null && inspection.ownerNloc > shellNlocLimit) {
        violations.add(
          '$fileName: shell NLOC ${inspection.ownerNloc} exceeds $shellNlocLimit',
        );
      }
      final shellImportLimit = budget.shellImportLimit;
      if (shellImportLimit != null &&
          inspection.importCount > shellImportLimit) {
        violations.add(
          '$fileName: shell imports ${inspection.importCount} exceeds $shellImportLimit',
        );
      }
    }
    if (budget.forbidPartDirectives && inspection.hasPartDirective) {
      violations.add('$fileName: part/part-of directives are forbidden');
    }
    for (final executable in inspection.executables) {
      if (executable.ccn > budget.executableCcnLimit) {
        violations.add(
          '$fileName: executable ${executable.name} CCN ${executable.ccn} exceeds ${budget.executableCcnLimit}',
        );
      }
      final nlocLimit = budget.executableNlocLimit;
      if (nlocLimit != null && executable.nloc > nlocLimit) {
        violations.add(
          '$fileName: executable ${executable.name} NLOC ${executable.nloc} exceeds $nlocLimit',
        );
      }
    }
    for (final type in inspection.types) {
      final nlocLimit =
          budget.namedTypeNlocLimits[type.name] ?? budget.typeNlocLimit;
      if (nlocLimit != null && type.nloc > nlocLimit) {
        violations.add(
          '$fileName: type ${type.name} NLOC ${type.nloc} exceeds $nlocLimit',
        );
      }
      final memberLimit = budget.typeMemberLimit;
      if (memberLimit != null && type.memberCount > memberLimit) {
        violations.add(
          '$fileName: type ${type.name} members ${type.memberCount} exceeds $memberLimit',
        );
      }
      final callableLimit = budget.typeCallableLimit;
      if (callableLimit != null && type.callableCount > callableLimit) {
        violations.add(
          '$fileName: type ${type.name} callables ${type.callableCount} exceeds $callableLimit',
        );
      }
    }
  }
  return violations.toSet().toList()..sort();
}

class DartSourceInspection {
  const DartSourceInspection({
    required this.fileName,
    required this.parseErrors,
    required this.ownerNloc,
    required this.importCount,
    required this.hasPartDirective,
    required this.executables,
    required this.types,
    required this.declaredTypes,
    required this.methodNames,
    required this.invocations,
    required AstAliasOwnership aliases,
  }) : _aliases = aliases;

  final String fileName;
  final List<String> parseErrors;
  final int ownerNloc;
  final int importCount;
  final bool hasPartDirective;
  final List<ExecutableMetric> executables;
  final List<TypeMetric> types;
  final Set<String> declaredTypes;
  final Set<String> methodNames;
  final List<AstInvocation> invocations;
  final AstAliasOwnership _aliases;

  Set<String> get invocationNames =>
      invocations.map((invocation) => invocation.name).toSet();

  Set<String> invocationsOn({
    Set<String> receiverNames = const {},
    Set<String> receiverTypeNames = const {},
  }) {
    final owned = _aliases.identifiers(
      names: receiverNames,
      typeNames: receiverTypeNames,
    );
    return invocations
        .where((invocation) => owned.contains(invocation.targetIdentifier))
        .map((invocation) => invocation.name)
        .toSet();
  }

  Set<String> invokedCallableAliases({
    Set<String> names = const {},
    Set<String> typeNames = const {},
  }) {
    final owned = _aliases.identifiers(names: names, typeNames: typeNames);
    return invocations
        .where((invocation) => owned.contains(invocation.name))
        .map((invocation) => invocation.name)
        .toSet();
  }

  Set<String> invocationsOnProviders(
    Set<String> providerNames, {
    Set<String> receiverNames = const {'ref'},
  }) {
    final ownedReceivers = _aliases.identifiers(names: receiverNames);
    return invocations
        .where(
          (invocation) =>
              providerNames.contains(invocation.providerTargetIdentifier) &&
              ownedReceivers.contains(invocation.providerReceiverIdentifier),
        )
        .map((invocation) => invocation.name)
        .toSet();
  }

  Set<String> providerReads({Set<String> receiverNames = const {'ref'}}) {
    final owned = _aliases.identifiers(names: receiverNames);
    return invocations
        .where(
          (invocation) =>
              owned.contains(invocation.targetIdentifier) &&
              (invocation.name == 'read' || invocation.name == 'watch'),
        )
        .expand((invocation) => invocation.argumentIdentifiers)
        .toSet();
  }
}
