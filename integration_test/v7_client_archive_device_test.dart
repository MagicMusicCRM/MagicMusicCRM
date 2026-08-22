import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_archive_button.dart';

import '../test/features/crm/client_card/client_card_roles_test.dart';
import 'evidence_screenshot.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('archive preview and commit preserve linked facts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ClientCardRolesTestApi();
    var archived = false;
    await tester.pumpWidget(
      RepaintBoundary(
        key: evidenceRootKey,
        child: ProviderScope(
          overrides: [magicApiClientProvider.overrideWithValue(api)],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              body: Center(
                child: StatefulBuilder(
                  builder: (context, setHostState) => archived
                      ? const Text('Карточка перемещена в архив')
                      : ClientArchiveButton(
                          entityType: 'student',
                          entityId: 'student-a',
                          allowed: true,
                          onArchived: () {
                            setHostState(() => archived = true);
                          },
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('client-archive-open')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.text('Финансовые факты останутся неизменными.'),
      findsOneWidget,
    );
    expect(
      find.text('Связанные карточки: 1. Они не будут архивированы.'),
      findsOneWidget,
    );
    await captureEvidence(tester, 'client-archive-impact-preview');

    await tester.tap(find.byKey(const ValueKey('client-archive-confirm')));
    await tester.pumpAndSettle();

    expect(archived, isTrue);
    expect(api.posts.last.path, '/crm/clients/archive');
    expect(api.posts.last.data, {
      'type': 'student',
      'id': 'student-a',
      'expectedVersion': 7,
      'confirm': true,
      'reason': 'crm.client.archive.inactive',
    });
    expect(find.text('Карточка перемещена в архив'), findsOneWidget);
    await captureEvidence(tester, 'client-archive-completed');
    expect(tester.takeException(), isNull);
  });
}
