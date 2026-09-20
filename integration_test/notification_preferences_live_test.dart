import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/models/notification_preference.dart';
import 'package:magic_music_crm/core/services/magic_notifications_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/notification_preferences_dialog.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final role in ['director', 'manager']) {
    testWidgets(
      '$role saves every visible notification routing cell',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'notification-preferences');
        await h.initialize(size: const Size(1440, 1100));
        final service = h.scope.read(magicNotificationsServiceProvider);
        final modal = find.byType(NotificationPreferencesDialog);
        Future<void> open() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await h.mount(
            SystemSettingsRouteScreen(key: UniqueKey(), initialArea: 'users'),
          );
          await h.quiet();
          await h.tap(find.byTooltip('Настройки уведомлений'));
          await h.quiet();
          expect(modal, findsOneWidget);
        }

        List<NotificationPreference> baseline = [];
        await h.check(
          'OPEN',
          'Открыть настройки из списка доступов и получить полную матрицу получателей',
          () async {
            await open();
            baseline = await service.listPreferences();
            expect(baseline, isNotEmpty);
            expect(
              baseline.every(
                (p) =>
                    notificationEventLabels.containsKey(p.eventType) &&
                    notificationRoleLabels.containsKey(p.role),
              ),
              true,
            );
            h.facts.add({
              'step': h.currentStep,
              'cells': baseline
                  .map(
                    (p) => {
                      'role': p.role,
                      'eventType': p.eventType,
                      'enabled': p.enabled,
                      'channels': p.channels,
                    },
                  )
                  .toList(),
            });
          },
        );
        Future<Finder> rowFor(NotificationPreference preference) async {
          final eventLabel = find.text(
            notificationEventLabels[preference.eventType]!,
          );
          final scrollable = find
              .descendant(of: modal, matching: find.byType(Scrollable))
              .first;
          await tester.scrollUntilVisible(
            eventLabel,
            200,
            scrollable: scrollable,
          );
          await h.quiet();
          final section = find
              .ancestor(of: eventLabel, matching: find.byType(Column))
              .first;
          final roleLabel = find.descendant(
            of: section,
            matching: find.text(notificationRoleLabels[preference.role]!),
          );
          final row = find
              .ancestor(of: roleLabel, matching: find.byType(Row))
              .first;
          await tester.ensureVisible(row);
          await tester.pump();
          return row;
        }

        Future<NotificationPreference> read(
          NotificationPreference preference,
        ) async => (await service.listPreferences()).singleWhere(
          (p) =>
              p.role == preference.role && p.eventType == preference.eventType,
        );
        for (final preference in baseline) {
          await h.check(
            '${preference.eventType}-${preference.role}',
            'Включение и каналы: ${notificationEventLabels[preference.eventType]} → ${notificationRoleLabels[preference.role]}',
            () async {
              await open();
              var row = await rowFor(preference);
              Finder toggle() =>
                  find.descendant(of: row, matching: find.byType(Switch));
              expect(tester.widget<Switch>(toggle()).value, preference.enabled);
              await h.tap(toggle());
              await h.quiet();
              expect((await read(preference)).enabled, !preference.enabled);
              await h.tap(toggle());
              await h.quiet();
              expect((await read(preference)).enabled, preference.enabled);
              if (!preference.enabled) {
                await h.tap(toggle());
                await h.quiet();
              }
              for (final channel in notificationChannelLabels.entries) {
                final chip = find.descendant(
                  of: row,
                  matching: find.widgetWithText(FilterChip, channel.value),
                );
                final selected = tester.widget<FilterChip>(chip).selected;
                await h.tap(chip);
                await h.quiet();
                expect(
                  (await read(preference)).channels.contains(channel.key),
                  !selected,
                );
                await h.tap(chip);
                await h.quiet();
                expect(
                  (await read(preference)).channels.contains(channel.key),
                  selected,
                );
              }
              if (!preference.enabled) {
                await h.tap(toggle());
                await h.quiet();
              }
              final saved = await read(preference);
              expect(saved.enabled, preference.enabled);
              expect(saved.channels.toSet(), preference.channels.toSet());
              h.facts.add({
                'step': h.currentStep,
                'saved': {
                  'role': saved.role,
                  'eventType': saved.eventType,
                  'enabled': saved.enabled,
                  'channels': saved.channels,
                },
              });
            },
          );
        }
        await h.check(
          'REOPEN',
          'Повторное открытие сохраняет итоговую матрицу без изменения соседних получателей',
          () async {
            await open();
            final saved = await service.listPreferences();
            expect(saved.length, baseline.length);
            for (final before in baseline) {
              final after = saved.singleWhere(
                (p) => p.role == before.role && p.eventType == before.eventType,
              );
              expect(after.enabled, before.enabled);
              expect(after.channels.toSet(), before.channels.toSet());
            }
            await h.tap(
              find.descendant(of: modal, matching: find.byTooltip('Закрыть')),
            );
            expect(modal, findsNothing);
          },
        );
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 25)),
    );
  }
}
