import 'package:flutter_test/flutter_test.dart';

import '../../support/architecture/dart_architecture_guard.dart';

const _widgetDirectory = 'lib/features/manager/presentation/widgets';
const _shellFilename = 'teacher_stats_widget.dart';
const _controllerFilename = 'teacher_stats_controller.dart';
const _budget = DartArchitectureBudget(
  ownerNlocLimit: 500,
  shellFileName: _shellFilename,
  shellNlocLimit: 240,
  shellImportLimit: 12,
  executableCcnLimit: 10,
  executableNlocLimit: 130,
  typeNlocLimit: 420,
  typeMemberLimit: 30,
);
const _requiredShellMethods = {
  'initState',
  'didUpdateWidget',
  'dispose',
  'build',
};
const _requiredShellProviders = {
  'magicCrmServiceProvider',
  'magicSettingsServiceProvider',
  'reportFileOpenerProvider',
};
const _controllerLifecycleMethods = {
  'addListener',
  'removeListener',
  'initialize',
  'updateSharedFilter',
  'updateCorrectionPolicy',
};
const _serviceEffectMethods = {
  'getTeacherStatsReport',
  'exportTeacherStatsReport',
  'setLessonsTeacherRate',
  'updateGroup',
};

void main() {
  test('all discovered teacher statistics owners pass the AST guard', () {
    final sources = discoverDartSources(
      directoryPath: _widgetDirectory,
      filePrefix: 'teacher_stats_',
    );

    expect(sources, isNotEmpty);
    expect(sources, contains(_shellFilename));
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
  refAlias . read (magicCrmServiceProvider) . renamedProviderEffect ();
}
''',
    });

    expect(
      violations,
      containsAll(<String>[
        'teacher_stats_hidden.dart: MagicCrmService invocation renamedEffect outside controller',
        'teacher_stats_hidden.dart: MagicCrmService invocation renamedProviderEffect outside controller',
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
    final methods = List.generate(31, (index) => 'void m$index() {}').join();
    final violations = _auditSources({
      'teacher_stats_surprise.dart': 'class Surprise {$methods}',
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

List<String> _auditSources(Map<String, String> sources) {
  final inspections = inspectDartSources(sources);
  final violations = auditDartArchitecture(inspections, _budget);
  for (final inspection in inspections) {
    final providers = inspection.providerReads();
    if (inspection.fileName != _shellFilename && providers.isNotEmpty) {
      violations.add('${inspection.fileName}: provider read outside shell');
    }

    final crmInvocations = <String>{
      ...inspection.invocationsOn(receiverTypeNames: const {'MagicCrmService'}),
      ...inspection.invocationsOnProviders(const {'magicCrmServiceProvider'}),
      ...inspection.invocationNames.intersection(_serviceEffectMethods),
    };
    if (inspection.fileName != _controllerFilename) {
      for (final method in crmInvocations) {
        violations.add(
          '${inspection.fileName}: MagicCrmService invocation $method outside controller',
        );
      }
    }

    final lifecycleInvocations = inspection
        .invocationsOn(receiverTypeNames: const {'TeacherStatsController'})
        .intersection(_controllerLifecycleMethods);
    if (inspection.fileName != _shellFilename) {
      for (final method in lifecycleInvocations) {
        violations.add(
          '${inspection.fileName}: controller lifecycle invocation $method outside shell',
        );
      }
    }

    if (inspection.fileName == _shellFilename) {
      if (!inspection.declaredTypes.contains('TeacherStatsWidget')) {
        violations.add(
          '$_shellFilename: TeacherStatsWidget shell class missing',
        );
      }
      for (final method in _requiredShellMethods.difference(
        inspection.methodNames,
      )) {
        violations.add(
          '$_shellFilename: shell lifecycle method $method missing',
        );
      }
      for (final provider in _requiredShellProviders.difference(providers)) {
        violations.add(
          '$_shellFilename: shell provider read $provider missing',
        );
      }
    }
  }
  return violations.toSet().toList()..sort();
}
