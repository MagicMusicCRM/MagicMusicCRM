import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../../support/architecture/dart_architecture_guard.dart';

const _directory = 'lib/features/admin/presentation/widgets';
const _shellFilename = 'schedule_reference_settings.dart';
const _controllerFilename = 'schedule_reference_controller.dart';
const _requiredOwners = {
  _shellFilename,
  _controllerFilename,
  'schedule_reference_models.dart',
  'schedule_reference_view.dart',
  'schedule_reference_cards.dart',
  'schedule_reference_dialogs.dart',
};
const _serviceEffects = {
  'listBranches',
  'listTeachers',
  'getBranchScheduleHours',
  'getScheduleReference',
  'replaceBranchHours',
  'replaceTeacherBranches',
  'replaceTeacherAvailability',
};
const _budget = DartArchitectureBudget(
  ownerNlocLimit: 500,
  shellFileName: _shellFilename,
  shellNlocLimit: 120,
  shellImportLimit: 8,
  executableCcnLimit: 10,
  executableNlocLimit: 100,
  typeNlocLimit: 400,
  typeMemberLimit: 50,
  typeCallableLimit: 30,
  forbidPartDirectives: true,
);

void main() {
  test(
    'all dynamically discovered schedule reference owners pass AST guard',
    () {
      final sources = discoverDartSources(
        directoryPath: _directory,
        filePrefix: 'schedule_reference_',
      );

      expect(sources.keys, containsAll(_requiredOwners));
      expect(_architectureViolations(inspectDartSources(sources)), isEmpty);
    },
  );

  test(
    'comments and strings cannot hide whitespace or alias service effects',
    () {
      final violations = _architectureViolations([
        inspectDartSource('schedule_reference_future.dart', r'''
void leak(MagicCrmService crm) {
  // crm.replaceBranchHours(); is not executable code.
  const decoy = 'replaceTeacherBranches();';
  final service = crm;
  service
      . replaceTeacherAvailability
      ();
  final save = crm.replaceBranchHours;
  save();
}
void providerLeak(dynamic ref) {
  final alias = ref;
  alias.read(magicCrmServiceProvider);
}
'''),
      ]);

      expect(
        violations,
        containsAll([
          contains('replaceTeacherAvailability outside controller'),
          contains('save outside controller'),
          contains('provider read outside shell'),
        ]),
      );
      expect(violations.join('\n'), isNot(contains('replaceTeacherBranches')));
    },
  );

  test('dynamic discovery and syntax guard reject a new malformed owner', () {
    final directory = Directory.systemTemp.createTempSync(
      'schedule-reference-architecture-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    File(
      '${directory.path}${Platform.pathSeparator}schedule_reference_future.dart',
    ).writeAsStringSync('void futureOwner() {}');
    File(
      '${directory.path}${Platform.pathSeparator}unrelated.dart',
    ).writeAsStringSync('void unrelated() {}');

    final sources = discoverDartSources(
      directoryPath: directory.path,
      filePrefix: 'schedule_reference_',
    );
    expect(sources.keys, ['schedule_reference_future.dart']);
    expect(
      _architectureViolations([
        inspectDartSource('schedule_reference_broken.dart', 'void broken( {'),
      ]),
      contains(contains('parse errors:')),
    );
  });

  test('CCN and type proxies reject future brain and god owners', () {
    final methods = List.generate(31, (index) => 'void m$index() {}').join();
    final violations = _architectureViolations([
      inspectDartSource('schedule_reference_tangled.dart', '''
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
'''),
      inspectDartSource(
        'schedule_reference_god.dart',
        'class FutureOwner {$methods}',
      ),
    ]);

    expect(violations, contains(contains('CCN ')));
    expect(violations, contains(contains('callables 31 exceeds 30')));
  });
}

List<String> _architectureViolations(
  Iterable<DartSourceInspection> inspections,
) {
  final inspected = inspections.toList();
  final violations = auditDartArchitecture(inspected, _budget);
  for (final inspection in inspected) {
    final providers = inspection.providerReads();
    if (inspection.fileName != _shellFilename && providers.isNotEmpty) {
      violations.add('${inspection.fileName}: provider read outside shell');
    }
    if (inspection.fileName == _shellFilename &&
        !providers.contains('magicCrmServiceProvider')) {
      violations.add('$_shellFilename: service provider read missing');
    }
    if (inspection.fileName == _controllerFilename) continue;
    final effects = <String>{
      ...inspection.invocationNames.intersection(_serviceEffects),
      ...inspection.invocationsOn(receiverTypeNames: const {'MagicCrmService'}),
      ...inspection.invokedCallableAliases(names: _serviceEffects),
    };
    for (final effect in effects) {
      violations.add(
        '${inspection.fileName}: service effect $effect outside controller',
      );
    }
  }
  return violations.toSet().toList()..sort();
}
