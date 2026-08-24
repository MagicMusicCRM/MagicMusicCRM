import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/crm_configuration_workspace.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/access_editor_sheet.dart';

import '../test/features/access/access_editor_roles_test.dart';
import '../test/features/settings/crm_configuration_workspace_test.dart';
import '../test/features/settings/system_settings_workspace_test.dart';
import 'evidence_screenshot.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('director configuration exposes centralized field options', (
    tester,
  ) async {
    _desktop(tester);
    final api = ConfigurationTestApi(
      role: 'director',
      capabilities: const [
        'config.crm.read',
        'config.crm.edit',
        'config.crm.publish',
      ],
      snapshot: inlineOptionsSnapshot(),
    );
    await tester.pumpWidget(
      _evidenceHost(api: api, child: const CrmConfigurationRouteScreen()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Варианты для полей'), findsOneWidget);
    expect(find.text('Формат занятий'), findsOneWidget);
    await captureEvidence(tester, 'configuration-fields-option-sets');

    await tester.tap(find.text('Занятия и оплата'));
    await tester.pumpAndSettle();
    expect(find.text('Типы списания занятия'), findsOneWidget);
    expect(find.text('Типы оплаты преподавателю'), findsOneWidget);
    await captureEvidence(tester, 'configuration-lesson-payment-catalogs');
  });

  testWidgets('schedule settings show branch hours and teacher assignment', (
    tester,
  ) async {
    _desktop(tester);
    final api = SettingsTestApi(
      role: 'director',
      capabilities: const [
        'system.settings.manage',
        'schedule.lesson.read.assigned',
        'schedule.lesson.write',
      ],
    );
    await tester.pumpWidget(
      _evidenceHost(
        api: api,
        child: const Scaffold(body: SystemSettingsWorkspace(role: 'director')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Расписание'));
    await tester.pumpAndSettle();
    expect(find.text('Рабочие часы филиала'), findsOneWidget);
    expect(find.text('Петрова Мария'), findsNothing);

    await tester.tap(find.text('Графики преподавателей'));
    await tester.pumpAndSettle();
    expect(find.text('Доступность преподавателя'), findsOneWidget);
    expect(find.text('Петрова Мария'), findsWidgets);
    await captureEvidence(tester, 'settings-teacher-branch-availability');
  });

  testWidgets('director can manage a manager capability with an audit reason', (
    tester,
  ) async {
    _desktop(tester);
    await tester.pumpWidget(
      RepaintBoundary(
        key: evidenceRootKey,
        child: MaterialApp(
          home: AccessEditorSheet(
            actorRole: 'director',
            userId: '11111111-1111-4111-8111-111111111111',
            userLabel: 'Анна Петрова · Управляющий',
            dataSource: AccessEditorTestDataSource()..role = 'manager',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Версия набора прав: 4'), findsOneWidget);
    expect(find.byKey(const Key('access-reason')), findsOneWidget);
    await captureEvidence(tester, 'settings-manager-capability-access');
  });
}

Widget _evidenceHost({required MagicApiClient api, required Widget child}) {
  return RepaintBoundary(
    key: evidenceRootKey,
    child: ProviderScope(
      overrides: [magicApiClientProvider.overrideWithValue(api)],
      child: MaterialApp(home: child),
    ),
  );
}

void _desktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
