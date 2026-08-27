import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/architecture/dart_architecture_guard.dart';

const _directory = 'lib/features/admin/presentation/widgets';
const _shellFilename = 'staff_detail_dialog.dart';
const _controllerFilename = 'staff_detail_controller.dart';
const _requiredFiles = {
  _shellFilename,
  'staff_detail_model.dart',
  _controllerFilename,
  'staff_detail_content.dart',
  'staff_detail_access_flow.dart',
};
const _requiredTypes = <String, Set<String>>{
  _shellFilename: {'StaffDetailDialog', '_StaffDetailDialogState'},
  'staff_detail_model.dart': {'StaffDetailDraft'},
  _controllerFilename: {
    'StaffDetailController',
    'StaffDetailValidationException',
  },
  'staff_detail_content.dart': {'StaffDetailContent'},
  'staff_detail_access_flow.dart': {'StaffDetailAccessFlow'},
};
const _serviceEffects = {
  'listBranches',
  'updateStaff',
  'getStaffAccess',
  'provisionStaffAccess',
};
const _forbiddenShellMethods = {
  'updateStaff',
  'getStaffAccess',
  'provisionStaffAccess',
  '_credentialHelper',
  '_branchesText',
  '_dropdownItems',
};
const _budget = DartArchitectureBudget(
  ownerNlocLimit: 500,
  shellFileName: _shellFilename,
  shellNlocLimit: 240,
  shellImportLimit: 14,
  executableCcnLimit: 10,
  executableNlocLimit: 130,
  typeNlocLimit: 420,
  typeMemberLimit: 38,
  typeCallableLimit: 30,
  forbidPartDirectives: true,
);

void main() {
  test('all discovered staff detail owners pass the AST guard', () {
    final sources = discoverDartSources(
      directoryPath: _directory,
      filePrefix: 'staff_detail_',
    );

    expect(sources.keys, containsAll(_requiredFiles));
    expect(_auditSources(sources), isEmpty);
  });

  test('AST ownership follows aliases and ignores lexical decoys', () {
    final violations = _auditSources({
      'staff_detail_future.dart': r'''
void leak(MagicCrmService crm, dynamic ref) {
  // magicCrmServiceProvider and updateStaff are not executable here.
  const decoy = 'getStaffAccess updateStaff magicCrmServiceProvider';
  final serviceAlias = crm;
  final refAlias = ref;
  serviceAlias . updateStaff ('staff-a');
  refAlias . read (magicCrmServiceProvider);
  final mutate = crm.updateStaff;
  mutate('staff-b');
  final read = ref.read;
  read(magicCrmServiceProvider);
}
''',
      _shellFilename: r'''
class StaffDetailDialog {}
void shell(dynamic ref) {
  ref.read(magicCrmServiceProvider);
}
''',
      _controllerFilename: 'class StaffDetailController {}',
    });

    expect(
      violations,
      containsAll(<String>[
        'staff_detail_future.dart: MagicCrmService invocation updateStaff outside controller',
        'staff_detail_future.dart: MagicCrmService invocation mutate outside controller',
        'staff_detail_future.dart: provider read outside shell',
      ]),
    );
    expect(
      violations.where((violation) => violation.contains('decoy')),
      isEmpty,
    );
  });

  test('dynamic discovery rejects future brain and god owners', () {
    final methods = List.generate(31, (index) => 'void m$index() {}').join();
    final violations = _auditSources({
      'staff_detail_tangled.dart': '''
int tangled(List<int> values, int x) {
  if (x > 0) x++;
  for (final value in values) { x += value; }
  while (x < 3) { x++; }
  do { x--; } while (x > 20);
  try { x++; } catch (_) { x--; }
  final choice = x > 0 ? 1 : 0;
  final boolean = x > 0 && x < 10 || x == 20;
  final collection = <int>[if (x > 0) choice, for (final v in values) v];
  return switch (x) { 1 => collection.length, _ => boolean ? 1 : 0 };
}
''',
      'staff_detail_brain.dart': 'class FutureOwner {$methods}',
      'staff_detail_broken.dart': 'void broken( {',
    });

    expect(violations, contains(contains('CCN ')));
    expect(violations, contains(contains('callables 31 exceeds 30')));
    expect(violations, contains(contains('parse errors:')));
  });
}

List<String> _auditSources(Map<String, String> sources) {
  final inspections = inspectDartSources(sources);
  final violations = auditDartArchitecture(inspections, _budget);
  for (final inspection in inspections) {
    final requiredTypes =
        _requiredTypes[inspection.fileName] ?? const <String>{};
    for (final type in requiredTypes.difference(inspection.declaredTypes)) {
      violations.add('${inspection.fileName}: required type $type missing');
    }
    final providers = _providerReads(inspection);
    if (inspection.fileName != _shellFilename && providers.isNotEmpty) {
      violations.add('${inspection.fileName}: provider read outside shell');
    }

    final serviceInvocations = <String>{
      ...inspection.invocationsOn(receiverTypeNames: const {'MagicCrmService'}),
      ...inspection.invocationsOnProviders(const {'magicCrmServiceProvider'}),
      ...inspection.invocationNames.intersection(_serviceEffects),
      ...inspection.invokedCallableAliases(names: _serviceEffects),
    };
    if (inspection.fileName != _controllerFilename) {
      for (final method in serviceInvocations) {
        violations.add(
          '${inspection.fileName}: MagicCrmService invocation $method outside controller',
        );
      }
    }

    if (inspection.fileName == _shellFilename) {
      final forbidden = <String>{
        ...inspection.methodNames,
        ...inspection.invocationNames,
      }.intersection(_forbiddenShellMethods);
      for (final method in forbidden) {
        violations.add('$_shellFilename: forbidden shell method $method');
      }
      final providerOccurrences = _identifierCount(
        sources[_shellFilename]!,
        'magicCrmServiceProvider',
      );
      if (providerOccurrences > 1) {
        violations.add(
          '$_shellFilename: magicCrmServiceProvider occurrences $providerOccurrences exceeds 1',
        );
      }
    }
  }
  return violations.toSet().toList()..sort();
}

Set<String> _providerReads(DartSourceInspection inspection) {
  const providerNames = {'magicCrmServiceProvider'};
  final callableAliases = inspection.invokedCallableAliases(
    names: const {'read', 'watch'},
  );
  return {
    ...inspection.providerReads(),
    for (final invocation in inspection.invocations)
      if (callableAliases.contains(invocation.name))
        ...invocation.argumentIdentifiers.intersection(providerNames),
  };
}

int _identifierCount(String source, String name) {
  final result = parseString(content: source, throwIfDiagnostics: false);
  final visitor = _IdentifierCountVisitor(name);
  result.unit.accept(visitor);
  return visitor.count;
}

class _IdentifierCountVisitor extends RecursiveAstVisitor<void> {
  _IdentifierCountVisitor(this.name);

  final String name;
  int count = 0;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name == name) count++;
    super.visitSimpleIdentifier(node);
  }
}
