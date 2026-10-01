import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/models/notification_preference.dart';
import 'package:magic_music_crm/core/services/magic_notifications_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/notification_preferences_dialog.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/services/magic_profile_admin_service.dart';
import 'package:magic_music_crm/features/admin/presentation/screens/profile_detail_screen.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/user_roles_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/access_editor_sheet.dart';
import 'package:magic_music_crm/features/crm/presentation/staff_workspace_screen.dart';
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
            SystemSettingsRouteScreen(
              key: UniqueKey(),
              initialArea: 'notifications',
            ),
          );
          await h.quiet();
          expect(modal, findsOneWidget);
          expect(find.byType(Dialog), findsNothing);
          expect(find.text('Доступ и уведомления'), findsNothing);
        }

        List<NotificationPreference> baseline = [];
        String? selectedProfileName;
        await h.check(
          'OPEN',
          'Открыть отдельную страницу уведомлений и получить матрицу получателей',
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
            expect(find.byType(Dialog), findsNothing);
          },
        );
        await h.check(
          'NARROW',
          'Уведомления доступны на узком экране',
          () async {
            tester.view.physicalSize = const Size(390, 844);
            await open();
            expect(find.byType(Dialog), findsNothing);
            expect(find.byType(Switch), findsWidgets);
            tester.view.physicalSize = const Size(1440, 1100);
          },
        );
        await h.check(
          'USERS',
          'Поиск и карточка пользователя внутри настроек',
          () async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            await h.mount(
              StaffWorkspaceScreen(
                key: UniqueKey(),
                initialLink: EntityLink.typed(
                  entityType: EntityLinkType.report,
                  entityId: '__section__',
                  variant: 'configuration',
                  optionalFocus: EntityLinkFocus(focus: 'users'),
                ),
              ),
            );
            await h.quiet();
            final profiles = await h.scope
                .read(magicProfileAdminServiceProvider)
                .listProfiles(role: 'client');
            final profile = profiles.firstWhere(
              (p) => (p['linked_students'] as num) > 0,
            );
            selectedProfileName =
                '${profile['last_name']} ${profile['first_name']}'.trim();
            final search = find.byWidgetPredicate(
              (w) =>
                  w is TextField &&
                  w.decoration?.hintText ==
                      'Поиск по имени, почте, телефону...',
            );
            await tester.enterText(search, profile['email'] as String);
            await h.quiet();
            await h.tap(
              find
                  .text(
                    '${profile['last_name']} ${profile['first_name']}'.trim(),
                  )
                  .first,
            );
            await h.quiet();
            expect(find.byType(ProfileDetailScreen), findsOneWidget);
            expect(find.byType(Dialog), findsNothing);
            expect(find.text('Связанные карточки'), findsOneWidget);
            if (role == 'director') {
              await h.tap(
                find.widgetWithText(FilledButton, 'Настроить доступ'),
              );
              await h.quiet();
              expect(find.byType(AccessEditorSheet), findsOneWidget);
              expect(find.byType(Dialog), findsNothing);
              await h.tap(find.text('К карточке пользователя'));
            } else {
              expect(find.text('Настроить доступ'), findsNothing);
            }
            await h.tap(find.text('К списку пользователей'));
            await h.quiet();
            expect(
              tester.widget<TextField>(search).controller!.text,
              profile['email'],
            );
            expect(find.byType(UserRolesWidget), findsOneWidget);
          },
        );
        await h.check(
          'LINKED-CLIENT',
          'Связанный клиент открывается в рабочей области',
          () async {
            await h.tap(find.text(selectedProfileName!).first);
            await h.quiet();
            await h.tap(find.widgetWithText(ListTile, 'Ученик').first);
            await h.quiet();
            expect(find.byType(Dialog), findsNothing);
            expect(find.text('Связанные карточки'), findsNothing);
          },
        );
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 25)),
    );
  }
}
