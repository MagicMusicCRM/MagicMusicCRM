import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/architecture/dart_architecture_guard.dart';

const _telegramPath = 'lib/core/widgets/telegram';
const _controllerFileName = 'chat_info_controller.dart';
const _shellFileName = 'chat_info_dialog.dart';
const _serviceEffects = {
  'listMessages',
  'listChannelPosts',
  'listProfileNotes',
  'createProfileNote',
  'updateGroupMembers',
};
const _budget = DartArchitectureBudget(
  ownerNlocLimit: 500,
  shellFileName: _shellFileName,
  shellNlocLimit: 260,
  shellImportLimit: 12,
  executableCcnLimit: 10,
  executableNlocLimit: 100,
  typeNlocLimit: 300,
  typeCallableLimit: 24,
  forbidPartDirectives: true,
);

void main() {
  test('all chat info owners satisfy the AST architecture budget', () {
    final sources = discoverDartSources(
      directoryPath: _telegramPath,
      filePrefix: 'chat_info_',
    );
    final inspections = inspectDartSources(sources);

    expect(sources, isNotEmpty);
    expect(sources, contains(_shellFileName));
    expect(_architectureViolations(inspections), isEmpty);

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
    final tricky = inspectDartSource('chat_info_future.dart', trickySource);

    expect(tricky.parseErrors, isEmpty);
    expect(tricky.invocationNames.intersection(_serviceEffects), {
      'listMessages',
    });
    expect(
      tricky.executables
          .singleWhere((callable) => callable.name == 'renamedOwner')
          .ccn,
      15,
    );

    final partInspection = inspectDartSource(
      'chat_info_part.dart',
      "part /* comments and whitespace do not hide this */ 'owner.dart';",
    );
    expect(partInspection.parseErrors, isEmpty);
    expect(partInspection.hasPartDirective, isTrue);

    final classInspection = inspectDartSource(
      'chat_info_brain.dart',
      'class FutureOwner {${List.generate(25, (index) => 'void m$index() {}').join()}}',
    );
    expect(classInspection.types.single.callableCount, 25);
    expect(
      _architectureViolations([classInspection]),
      contains(contains('callables 25 exceeds 24')),
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

    expect(
      discoverDartSources(
        directoryPath: fixtureDirectory.path,
        filePrefix: 'chat_info_',
      ).keys,
      ['chat_info_future.dart'],
    );
  });
}

List<String> _architectureViolations(
  Iterable<DartSourceInspection> inspections,
) {
  final inspected = inspections.toList();
  final violations = auditDartArchitecture(inspected, _budget);
  for (final inspection in inspected) {
    final effects = inspection.invocationNames.intersection(_serviceEffects);
    if (inspection.fileName != _controllerFileName && effects.isNotEmpty) {
      violations.add(
        '${inspection.fileName}: service effects belong to '
        '$_controllerFileName: ${effects.join(', ')}',
      );
    }
    for (final legacyType in const {
      '_ChatInfoViews',
      '_AddMembersDialogState',
    }) {
      if (inspection.declaredTypes.contains(legacyType)) {
        violations.add(
          '${inspection.fileName}: legacy type $legacyType must stay deleted',
        );
      }
    }
  }
  return violations.toSet().toList()..sort();
}
