import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:magic_music_crm/core/services/alert_policy.dart';
import 'package:magic_music_crm/core/services/alert_sound_service.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/lead_notification_listener.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/magic_notifications_service.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';
import 'package:magic_music_crm/features/auth/providers/release_gate_provider.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/client_create_dialogs.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'package:magic_music_crm/features/crm/presentation/staff_workspace_screen.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/clients_widget.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';

import 'live_audit_harness.dart';

class _SoundProbe extends AlertSoundService {
  int calls = 0;

  @override
  Future<bool> play() async {
    calls++;
    return true;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets(
    'manual lead is quiet; inbound lead reaches two live sessions',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('local_notifier'),
        (call) async {
          if (call.method == 'setup') return true;
          if (call.method == 'notify') {
            calls.add(Map<String, dynamic>.from(call.arguments as Map));
          }
          return null;
        },
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('local_notifier'),
          null,
        ),
      );
      await localNotifier.setup(appName: 'MagicMusic CRM audit');

      final admin = LiveAuditHarness(tester, 'admin', 'notification-source');
      final manager = LiveAuditHarness(
        tester,
        'manager',
        'notification-source',
      );
      final foreign = LiveAuditHarness(
        tester,
        'manager',
        'notification-source-foreign',
      );
      final adminSound = _SoundProbe(),
          managerSound = _SoundProbe(),
          foreignSound = _SoundProbe();
      addTearDown(adminSound.dispose);
      addTearDown(managerSound.dispose);
      addTearDown(foreignSound.dispose);
      await admin.initialize(
        size: const Size(1440, 1100),
        liveCrmRealtime: true,
        alertSoundService: adminSound,
      );
      await manager.initialize(
        size: const Size(1440, 1100),
        liveCrmRealtime: true,
        alertSoundService: managerSound,
      );
      await foreign.initialize(
        size: const Size(1440, 1100),
        accountRole: 'foreign-manager',
        liveCrmRealtime: true,
        alertSoundService: foreignSound,
      );
      for (final h in [admin, manager, foreign]) {
        h.scope.listen(magicAuthStateProvider, (_, _) {});
        await h.waitFor(
          () => h.scope.read(magicAuthStateProvider).asData?.value != null,
          'Authenticated session reached the app stream',
        );
        expect(
          (await h.scope.read(releaseGateStatusProvider.future)).role,
          h.role,
        );
        h.scope.listen(currentUserIdProvider, (_, _) {});
        await h.waitFor(
          () => h.scope.read(currentUserIdProvider).asData?.value != null,
          'Current user id resolved',
        );
        h.scope
            .read(activeViewProvider.notifier)
            .set(crmTab: CrmSection.clients);
        h.scope.read(leadNotificationListenerProvider);
        final events = <Map<String, dynamic>>[];
        h.facts.add({'step': 'socket', 'events': events});
        h.scope.listen(crmRealtimeProvider, (_, next) {
          final event = next.value;
          if (event == null || event.isFallbackPoll) return;
          events.add({
            'entity': event.entity,
            'action': event.action,
            'id': event.id,
            'notificationType': event.notificationType,
            'recipients': event.affectedUserIds.length,
          });
        });
      }
      await tester.pump(const Duration(seconds: 2));

      Map<String, dynamic>? created;
      await admin.check(
        'MANUAL',
        'Создать лид через форму без системного уведомления',
        () async {
          await admin.mount(
            Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    created = await showDialog<Map<String, dynamic>>(
                      context: context,
                      builder: (_) => const LeadCreateDialog(),
                    );
                  },
                  child: const Text('Новый лид'),
                ),
              ),
            ),
          );
          await admin.tap(find.text('Новый лид'));
          await admin.quiet();
          Future<void> fill(String field, String value) async {
            final finder = find.byKey(ValueKey(field));
            await admin.tap(finder);
            await tester.enterText(finder, value);
            await tester.pump();
          }

          await fill('lead-first-name', 'ST02');
          await fill('lead-last-name', 'Ручной');
          await fill('lead-phone', '9991234567');
          await admin.tap(find.byKey(const ValueKey('lead-branch')));
          await admin.tap(find.text('HTTP test'));
          final source = tester.widget<SearchablePickerField>(
            find.byKey(const ValueKey('lead-source')),
          );
          await admin.tap(find.byKey(const ValueKey('lead-source')));
          await admin.tap(find.text(source.items.first.label));
          await admin.tap(find.byKey(const ValueKey('lead-submit')));
          await admin.quiet();
          expect(created?['id'], isNotNull);
          await admin.mount(const Scaffold(body: ClientsWidget()));
          await admin.waitFor(
            () => find.text('ST02 Ручной').evaluate().isNotEmpty,
            'Manual lead appears on the live lead board',
          );
          await tester.pump(const Duration(seconds: 2));
          expect(calls, isEmpty);
          expect(adminSound.calls + managerSound.calls + foreignSound.calls, 0);
          admin.facts.add({
            'step': admin.currentStep,
            'leadId': created!['id'],
            'osCalls': calls.length,
          });
        },
      );

      await admin.check(
        'MANUAL-UPDATE',
        'Изменить имя лида через карточку без системного уведомления',
        () async {
          admin.scope
              .read(activeViewProvider.notifier)
              .set(crmTab: CrmSection.schedule);
          final id = created!['id'] as String;
          final crm = admin.scope.read(magicCrmServiceProvider);
          final card = await crm.getLeadCard(id);
          final access = await admin.scope.read(
            capabilitySnapshotProvider.future,
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await admin.mount(
            Scaffold(
              body: ClientCard(
                lead: Map<String, dynamic>.from(card['lead'] as Map),
                entityType: 'lead',
                routed: true,
                initialSection: 'overview',
                capabilitySnapshot: access,
              ),
            ),
          );
          await admin.quiet();
          await admin.tap(find.byKey(const Key('client-edit-name')));
          await tester.enterText(
            find.byKey(const Key('client-name-first')),
            'ST02Edited',
          );
          await admin.tap(find.byKey(const Key('client-name-apply')));
          await tester.pump(const Duration(seconds: 2));
          await admin.quiet();
          final updated = await crm.getLeadCard(id);
          expect((updated['lead'] as Map)['first_name'], 'ST02Edited');
          expect(calls, isEmpty);
          expect(adminSound.calls + managerSound.calls + foreignSound.calls, 0);
          admin.facts.add({
            'step': admin.currentStep,
            'leadId': id,
            'osCalls': 0,
          });
        },
      );

      await admin.check(
        'INBOUND',
        'Внешний лид виден двум адресным сеансам один раз',
        () async {
          for (final h in [admin, manager, foreign]) {
            h.scope
                .read(activeViewProvider.notifier)
                .set(crmTab: CrmSection.schedule);
          }
          final directory = Directory(admin.fixture['controlDir'] as String);
          File('${directory.path}/trigger').writeAsStringSync('inbound');
          final result = File('${directory.path}/inbound-result.json');
          await admin.waitFor(
            () => result.existsSync(),
            'External webhook completed',
          );
          final inbound =
              jsonDecode(result.readAsStringSync()) as Map<String, dynamic>;
          expect(inbound['replayed'], true);
          await admin.waitFor(
            () => calls.length >= 2,
            'Both desktop sessions reached OS boundary',
          );
          await tester.pump(const Duration(seconds: 2));
          expect(calls.length, 2);
          expect(adminSound.calls, 1);
          expect(managerSound.calls, 1);
          expect(foreignSound.calls, 0);
          final foreignSocket = foreign.facts.firstWhere(
            (fact) => fact['step'] == 'socket',
          );
          expect(
            (foreignSocket['events'] as List).where(
              (event) => event['entity'] == 'notification',
            ),
            isEmpty,
          );
          expect(calls.every((call) => call['title'] == 'Новая заявка'), true);
          final id = inbound['leadId'] as String;
          for (final h in [admin, manager]) {
            final inbox = await h.scope
                .read(magicNotificationsServiceProvider)
                .list();
            expect(inbox.where((n) => n['data']?['entityId'] == id).length, 1);
          }
          final foreignInbox = await foreign.scope
              .read(magicNotificationsServiceProvider)
              .list();
          expect(
            foreignInbox.where((n) => n['data']?['entityId'] == id),
            isEmpty,
          );
          await expectLater(
            foreign.scope.read(magicCrmServiceProvider).getLeadCard(id),
            throwsA(isA<Exception>()),
          );
          admin.facts.add({
            'step': admin.currentStep,
            'leadId': id,
            'osCalls': calls.length,
            'appSoundCalls': [adminSound.calls, managerSound.calls],
          });
          await admin.mount(const StaffWorkspaceScreen());
          await admin.quiet();
          await admin.tap(find.byTooltip('Уведомления'));
          await admin.quiet();
          expect(find.text('Новая заявка'), findsWidgets);
          await admin.tap(find.text('Новая заявка'));
          await admin.quiet();
          expect(find.byType(ClientCard), findsOneWidget);
          expect(
            tester.widget<ClientCard>(find.byType(ClientCard)).lead['id'],
            id,
          );
          expect(find.textContaining('Входящий'), findsWidgets);
        },
      );
      await admin.finish();
      await manager.finish();
      await foreign.finish();
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
