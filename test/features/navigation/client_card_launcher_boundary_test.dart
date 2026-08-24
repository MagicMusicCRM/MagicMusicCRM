import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('launcher-only callers do not import routed client-card surfaces', () {
    const launcherPath =
        'lib/features/crm/presentation/client_card/client_card_launcher.dart';
    final launcherFile = File(launcherPath);

    expect(launcherFile.existsSync(), isTrue);
    if (!launcherFile.existsSync()) return;

    final launcherSource = launcherFile.readAsStringSync();
    final surfaceSource = File(
      'lib/features/crm/presentation/client_card/show_client_card.dart',
    ).readAsStringSync();
    const launcherCallers = [
      'lib/features/admin/presentation/screens/profile_detail_screen.dart',
      'lib/features/manager/presentation/widgets/finance_widget.dart',
      'lib/features/manager/presentation/widgets/leads_widget.dart',
      'lib/features/manager/presentation/widgets/students_board_widget.dart',
      'lib/features/messenger/presentation/screens/messenger_screen.dart',
      'lib/features/teacher/presentation/widgets/teacher_students_widget.dart',
    ];

    expect(launcherSource, contains('Future<bool?> showClientCard('));
    expect(surfaceSource, isNot(contains('Future<bool?> showClientCard(')));
    expect(surfaceSource, contains("export 'client_card_launcher.dart';"));

    for (final path in launcherCallers) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains('client_card_launcher.dart'),
        reason: '$path must depend only on the lightweight launcher',
      );
      expect(
        source,
        isNot(contains('show_client_card.dart')),
        reason: '$path must not import the routed surface implementation',
      );
    }
  });
}
