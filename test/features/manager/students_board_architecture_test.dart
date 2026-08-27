import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/architecture/dart_architecture_guard.dart';

const _owners = <String>[
  'students_board_controller.dart',
  'students_board_reconciliation_runtime.dart',
  'students_board_status_coordinator.dart',
];
const _budget = DartArchitectureBudget(
  ownerNlocLimit: 300,
  executableCcnLimit: 10,
  executableNlocLimit: 70,
  typeNlocLimit: 260,
  typeMemberLimit: 30,
  typeCallableLimit: 20,
  forbidPartDirectives: true,
);

void main() {
  test(
    'students board state owners stay split and within complexity budgets',
    () {
      const root = 'lib/features/manager/presentation/widgets';
      final missing = <String>[];
      final sources = <String, String>{};
      for (final owner in _owners) {
        final file = File('$root/$owner');
        if (!file.existsSync()) {
          missing.add(owner);
          continue;
        }
        sources[owner] = file.readAsStringSync();
      }

      expect(missing, isEmpty, reason: 'Missing students-board owner(s)');
      final violations = auditDartArchitecture(
        inspectDartSources(sources),
        _budget,
      );
      expect(violations, isEmpty);
    },
  );
}
