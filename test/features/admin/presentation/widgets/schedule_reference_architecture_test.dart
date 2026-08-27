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

  test('provider-derived receivers cannot hide future service effects', () {
    final violations = _architectureViolations([
      inspectDartSource(_shellFilename, r'''
void direct(dynamic ref) {
  ref.read(magicCrmServiceProvider).futureScheduleWrite();
}
void alias(dynamic ref) {
  final crm = ref.read(magicCrmServiceProvider);
  crm.futureAliasedScheduleWrite();
}
void reassigned(dynamic ref) {
  dynamic crm;
  crm = ref.read(magicCrmServiceProvider);
  crm.futureReassignedScheduleWrite();
}
'''),
    ]);

    expect(
      violations,
      containsAll([
        contains('futureScheduleWrite outside controller'),
        contains('futureAliasedScheduleWrite outside controller'),
        contains('futureReassignedScheduleWrite outside controller'),
      ]),
    );
  });

  test('provider ownership stays inside its lexical binding scope', () {
    final inspection = inspectDartSource(_shellFilename, r'''
void providerOwner(dynamic ref) {
  final crm = ref.read(magicCrmServiceProvider);
  crm.futureScopedWrite();
}
void unrelatedOwner() {
  final crm = LocalSchedulePreview();
  crm.refreshUnrelatedPreview();
}
void nestedOwners(dynamic ref) {
  {
    final crm = ref.read(magicCrmServiceProvider);
    crm.futureNestedWrite();
  }
  {
    final crm = LocalSchedulePreview();
    crm.refreshNestedPreview();
  }
}
''');

    expect(
      inspection.invocationsOnProviderDerivedReceivers(const {
        'magicCrmServiceProvider',
      }),
      {'futureScopedWrite', 'futureNestedWrite'},
    );
  });

  test('reassignment clears provider ownership before unrelated calls', () {
    final inspection = inspectDartSource(_shellFilename, r'''
void reassignedAway(dynamic ref) {
  dynamic crm = ref.read(magicCrmServiceProvider);
  crm = LocalSchedulePreview();
  crm.refreshLocalPreview();
}
''');

    expect(
      inspection.invocationsOnProviderDerivedReceivers(const {
        'magicCrmServiceProvider',
      }),
      isEmpty,
    );
  });

  test('control-flow joins retain every feasible provider origin', () {
    final inspection = inspectDartSource(_shellFilename, r'''
void conditionalClear(dynamic ref, bool useLocal) {
  dynamic crm = ref.read(magicCrmServiceProvider);
  if (useLocal) crm = LocalSchedulePreview();
  crm.futureConditionalClearWrite();
}
void branched(dynamic ref, bool useProvider) {
  dynamic crm = LocalSchedulePreview();
  if (useProvider) {
    crm = ref.read(magicCrmServiceProvider);
  } else {
    crm = LocalSchedulePreview();
  }
  crm.futureIfElseWrite();
}
void switched(dynamic ref, int mode) {
  dynamic crm = LocalSchedulePreview();
  switch (mode) {
    case 0:
      crm = ref.read(magicCrmServiceProvider);
      break;
    default:
      crm = LocalSchedulePreview();
  }
  crm.futureSwitchWrite();
}
void zeroIteration(dynamic ref, bool enabled) {
  dynamic crm = ref.read(magicCrmServiceProvider);
  while (enabled) {
    crm = LocalSchedulePreview();
  }
  crm.futureZeroIterationWrite();
}
void loopBody(dynamic ref, bool enabled) {
  dynamic crm = LocalSchedulePreview();
  while (enabled) {
    crm = ref.read(magicCrmServiceProvider);
  }
  crm.futureLoopBodyWrite();
}
void forZeroIteration(dynamic ref, int count) {
  dynamic crm = ref.read(magicCrmServiceProvider);
  for (var index = 0; index < count; index++) {
    crm = LocalSchedulePreview();
  }
  crm.futureForZeroIterationWrite();
}
void caught(dynamic ref) {
  dynamic crm = LocalSchedulePreview();
  try {
    crm = ref.read(magicCrmServiceProvider);
  } catch (_) {
    crm = LocalSchedulePreview();
  }
  crm.futureTryWrite();
}
void expressionBranches(dynamic ref, bool useProvider, int mode) {
  final p = magicCrmServiceProvider;
  final read = ref.read;
  dynamic crm = useProvider ? read(p) : LocalSchedulePreview();
  crm.futureConditionalExpressionWrite();
  crm = switch (mode) {
    0 => ref.read(p),
    _ => LocalSchedulePreview(),
  };
  crm.futureSwitchExpressionWrite();
}
''');

    expect(
      inspection.invocationsOnProviderDerivedReceivers(const {
        'magicCrmServiceProvider',
      }),
      {
        'futureConditionalClearWrite',
        'futureIfElseWrite',
        'futureSwitchWrite',
        'futureZeroIterationWrite',
        'futureLoopBodyWrite',
        'futureForZeroIterationWrite',
        'futureTryWrite',
        'futureConditionalExpressionWrite',
        'futureSwitchExpressionWrite',
      },
    );
  });

  test('definite branch and finally overwrites clear provider ownership', () {
    final inspection = inspectDartSource(_shellFilename, r'''
void allBranchesLocal(dynamic ref, bool first) {
  dynamic crm = ref.read(magicCrmServiceProvider);
  if (first) {
    crm = LocalSchedulePreview();
  } else {
    crm = OtherLocalSchedulePreview();
  }
  crm.refreshAfterBranches();
}
void finallyLocal(dynamic ref) {
  dynamic crm = LocalSchedulePreview();
  try {
    crm = ref.read(magicCrmServiceProvider);
  } catch (_) {
    crm = ref.read(magicCrmServiceProvider);
  } finally {
    crm = LocalSchedulePreview();
  }
  crm.refreshAfterFinally();
}
void localExpressions(bool first, int mode) {
  dynamic crm = first
      ? LocalSchedulePreview()
      : OtherLocalSchedulePreview();
  crm.refreshConditionalExpression();
  crm = switch (mode) {
    0 => LocalSchedulePreview(),
    _ => OtherLocalSchedulePreview(),
  };
  crm.refreshSwitchExpression();
}
''');

    expect(
      inspection.invocationsOnProviderDerivedReceivers(const {
        'magicCrmServiceProvider',
      }),
      isEmpty,
    );
  });

  test('catch parameters shadow provider-owned outer bindings', () {
    final inspection = inspectDartSource(_shellFilename, r'''
void catchShadow(dynamic ref) {
  final crm = ref.read(magicCrmServiceProvider);
  final stack = crm;
  try {
    throw StateError('failed');
  } catch (crm, stack) {
    crm.refreshLocal();
    stack.toString();
  }
  crm.futureOuterCrmWrite();
  stack.futureOuterStackWrite();
}
''');

    expect(
      inspection.invocationsOnProviderDerivedReceivers(const {
        'magicCrmServiceProvider',
      }),
      {'futureOuterCrmWrite', 'futureOuterStackWrite'},
    );
  });

  test('provider token and read aliases cannot hide derived receivers', () {
    final inspection = inspectDartSource(_shellFilename, r'''
void transitiveProvider(dynamic ref) {
  final p = magicCrmServiceProvider;
  final p2 = p;
  final crm = ref.read(p2);
  crm.futureTransitiveProviderWrite();
}
void readTearoff(dynamic ref) {
  final p = magicCrmServiceProvider;
  final read = ref.read;
  final crm = read(p);
  crm.futureReadTearoffWrite();
}
''');

    expect(
      inspection.invocationsOnProviderDerivedReceivers(const {
        'magicCrmServiceProvider',
      }),
      {'futureTransitiveProviderWrite', 'futureReadTearoffWrite'},
    );
  });

  test('field parenthesized and cascade origins stay provider-derived', () {
    final inspection = inspectDartSource(_shellFilename, r'''
class FieldOwner {
  FieldOwner(dynamic ref) : crm = ref.read(magicCrmServiceProvider);

  final dynamic crm;

  void mutate() {
    crm.futureFieldWrite();
  }
}
void parenthesized(dynamic ref) {
  ((ref.read(magicCrmServiceProvider))).futureParenthesizedWrite();
}
void cascaded(dynamic ref) {
  (ref.read(magicCrmServiceProvider))..futureCascadeWrite();
}
''');

    expect(
      inspection.invocationsOnProviderDerivedReceivers(const {
        'magicCrmServiceProvider',
      }),
      {'futureFieldWrite', 'futureParenthesizedWrite', 'futureCascadeWrite'},
    );
  });

  test('cross-method field summaries stay class scoped', () {
    final inspection = inspectDartSource(_shellFilename, r'''
class ProviderFieldOwner {
  dynamic crm = LocalSchedulePreview();

  void mutate() {
    crm.futureCrossMethodWrite();
  }

  void initialize(dynamic ref) {
    final p = magicCrmServiceProvider;
    final read = ref.read;
    crm = read(p);
  }
}
class LocalFieldOwner {
  dynamic crm = LocalSchedulePreview();

  void mutate() {
    crm.refreshLocalField();
  }

  void initialize() {
    crm = OtherLocalSchedulePreview();
  }
}
''');

    expect(
      inspection.invocationsOnProviderDerivedReceivers(const {
        'magicCrmServiceProvider',
      }),
      {'futureCrossMethodWrite'},
    );
  });

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
      ...inspection.invocationsOnProviders(const {'magicCrmServiceProvider'}),
      ...inspection.invocationsOnProviderDerivedReceivers(const {
        'magicCrmServiceProvider',
      }),
    };
    for (final effect in effects) {
      violations.add(
        '${inspection.fileName}: service effect $effect outside controller',
      );
    }
  }
  return violations.toSet().toList()..sort();
}
