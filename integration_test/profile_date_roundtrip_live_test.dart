import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/features/profile/presentation/screens/profile_screen.dart';

import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final role in ['admin', 'manager', 'director', 'teacher', 'client']) {
    testWidgets(
      '$role date-only profile roundtrip',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'profile-date');
        await h.initialize(size: const Size(1440, 1100));
        await h.api.patch<Map<String, dynamic>>(
          '/profile/me',
          data: {'dob': '1994-05-17'},
        );
        final field = find.widgetWithText(TextField, 'Имя (обязательно)');
        Future<void> open() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await h.mount(ProfileScreen(key: UniqueKey()));
          await h.waitFor(() => field.evaluate().isNotEmpty, 'Profile loaded');
          await h.quiet();
          final tile = tester.widget<ListTile>(
            find.widgetWithText(ListTile, 'День рождения'),
          );
          h.facts.add({
            'step': h.currentStep,
            'visibleDob': (tile.subtitle! as Text).data,
          });
        }

        await h.check(
          'OPEN-DATE',
          'Сохранённый день рождения открывается без изменения даты и времени',
          () async {
            await open();
            expect(find.text('1994-05-17'), findsOneWidget);
          },
        );
        for (final edit in [1, 2]) {
          await h.check(
            'NAME-$edit',
            'Правка имени №$edit не должна менять день рождения',
            () async {
              await open();
              await h.tap(field);
              await tester.enterText(field, 'Дата-$edit');
              await tester.pump();
              await h.tap(find.byTooltip('Сохранить'));
              await h.quiet();
              expect(find.text('Изменения сохранены'), findsOneWidget);
              final profile = await h.api.get<Map<String, dynamic>>(
                '/profile/me',
              );
              h.facts.add({
                'step': h.currentStep,
                'firstName': profile['firstName'],
                'dob': profile['dob'],
                'profileId': profile['id'],
              });
              expect(profile['firstName'], 'Дата-$edit');
              expect(
                profile['dob'].toString().substring(0, 10),
                '1994-05-17',
                reason: 'Editing a name must preserve date of birth',
              );
            },
          );
        }
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );
  }
}
