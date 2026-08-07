import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_archive_button.dart';

import '../test/features/v4/client_card_roles_test.dart';
import 'evidence_screenshot.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('archive preview shows preserved finance and linked cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ClientCardRolesTestApi();
    await tester.pumpWidget(
      RepaintBoundary(
        key: evidenceRootKey,
        child: ProviderScope(
          overrides: [magicApiClientProvider.overrideWithValue(api)],
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: ClientArchiveButton(
                  entityType: 'student',
                  entityId: 'student-a',
                  allowed: true,
                  onArchived: () {},
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
  });
}
