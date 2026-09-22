import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/shared/widgets/audit_event_card.dart';
import '../test/features/crm/client_card/card_fake_api.dart';
import '../test/features/crm/client_card/client_card_density_test.dart'
    show densityApi;
import '../test/features/crm/client_card/client_card_desktop_editing_test.dart'
    show desktopStudent, desktopManager;
import 'evidence_screenshot.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('populated card first screen and compact journals on Windows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpClientCard(
      tester,
      api: densityApi(),
      seed: desktopStudent,
      entityType: 'student',
      routed: true,
      capabilitySnapshot: desktopManager,
      theme: AppTheme.production,
      textScale: 1.25,
      topChromeHeight: 64,
    );
    final cell = find.byKey(const ValueKey('student-timeline-density-0'));
    expect(cell.hitTestable(), findsOneWidget);
    expect(
      tester.getBottomRight(cell).dy,
      lessThanOrEqualTo(
        tester
            .getBottomRight(find.byKey(const Key('client-desktop-canvas')))
            .dy,
      ),
    );
    await captureEvidence(tester, 'client-density-first-screen-1366x768-125');
    final history = find.byKey(
      const Key('client-section-heading-history_tasks'),
    );
    await tester.ensureVisible(history);
    await tester.pumpAndSettle();
    expect(find.byType(AuditEventCard), findsNWidgets(3));
    await captureEvidence(tester, 'client-density-tasks-history');
    final more = find.byKey(const Key('client-operational-history-more'));
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(find.byType(AuditEventCard), findsNWidgets(10));
    expect(tester.takeException(), isNull);
  });
}
