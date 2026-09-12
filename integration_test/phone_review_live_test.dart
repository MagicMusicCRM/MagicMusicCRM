import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['manager', 'director']) {
    testWidgets(
      '$role resolves phone review queue with reason',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'phone-review');
        await h.initialize(size: const Size(1440, 1250));
        final crm = h.scope.read(magicCrmServiceProvider),
            item = (h.fixture['phoneCases'] as Map)[role] as Map;
        final correctId = item['correctId'] as String,
            acceptId = item['acceptId'] as String,
            leadId = item['leadId'] as String;
        final phone = role == 'manager' ? '+79992223344' : '+79992223345';
        Future<List<Map<String, dynamic>>> queue() async {
          final rows = await crm.listPhoneReviewQueue(limit: 100);
          h.facts.add({'step': h.currentStep, 'queue': rows});
          return rows;
        }

        Future<void> open() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await h.mount(
            SystemSettingsRouteScreen(key: UniqueKey(), initialArea: 'data'),
          );
          await h.quiet();
        }

        Future<void> edit(String id) =>
            h.tap(find.byKey(ValueKey('resolve-phone-review-$id')));
        Finder phoneField() => find.byKey(const ValueKey('phone-review-phone'));
        Finder noteField() => find.byKey(const ValueKey('phone-review-note'));
        Finder save() =>
            find.byKey(const ValueKey('submit-phone-review-resolution'));
        Future<void> fill(Finder field, String value) async {
          await h.tap(field);
          await tester.enterText(field, value);
          await tester.pump();
        }

        await h.check('OPEN', 'Открыть очередь и обе записи роли', () async {
          await open();
          final rows = await queue();
          expect(rows.any((r) => r['id'] == correctId), true);
          expect(rows.any((r) => r['id'] == acceptId), true);
        });
        await h.check(
          'CANCEL',
          'Отмена заполненного решения сохраняет открытую запись',
          () async {
            await edit(correctId);
            await fill(phoneField(), phone);
            await fill(noteField(), 'CANCEL-RESOLUTION');
            await h.tap(find.widgetWithText(TextButton, 'Отмена'));
            expect((await queue()).any((r) => r['id'] == correctId), true);
          },
        );
        await h.check(
          'REQUIRED-REASON',
          'Без причины решения кнопка сохранения отключена',
          () async {
            await edit(correctId);
            expect(tester.widget<FilledButton>(save()).onPressed, isNull);
            await fill(noteField(), '   ');
            expect(tester.widget<FilledButton>(save()).onPressed, isNull);
            await h.tap(find.widgetWithText(TextButton, 'Отмена'));
          },
        );
        await h.check(
          'INVALID-PHONE',
          'Некорректный номер отклонён с сохранением формы и введённой причины',
          () async {
            await edit(correctId);
            await fill(phoneField(), '123');
            await fill(noteField(), 'RETAIN-INVALID-REASON');
            await h.tap(save());
            await h.quiet();
            expect((await queue()).any((r) => r['id'] == correctId), true);
            expect(noteField(), findsOneWidget);
            expect(
              tester.widget<TextField>(noteField()).controller!.text,
              'RETAIN-INVALID-REASON',
            );
          },
          expectedHttpErrors: [
            (
              method: 'PATCH',
              path: '/api/crm/phone-review-queue/$correctId',
              status: 400,
              maxCount: 1,
            ),
          ],
        );
        await h.check(
          'CORRECT',
          'Исправить номер и убрать запись из очереди',
          () async {
            await open();
            await edit(correctId);
            await fill(phoneField(), phone);
            await fill(noteField(), 'AUDIT-PHONE-CORRECTED');
            await h.tap(save());
            await h.quiet();
            expect((await queue()).any((r) => r['id'] == correctId), false);
            final lead = (await crm.getLeadCard(leadId))['lead'] as Map;
            h.facts.add({'step': h.currentStep, 'lead': lead});
            expect(lead['phone'], phone);
          },
        );
        await h.check(
          'REOPEN',
          'Повторное открытие сохраняет исправленный номер и закрытую очередь',
          () async {
            await open();
            expect(
              find.byKey(ValueKey('resolve-phone-review-$correctId')),
              findsNothing,
            );
            expect(
              ((await crm.getLeadCard(leadId))['lead'] as Map)['phone'],
              phone,
            );
          },
        );
        await h.check(
          'ACCEPT-CANCEL',
          'Оставить как есть требует причину; отмена сохраняет запись',
          () async {
            await edit(acceptId);
            await h.tap(find.text('Оставить как есть'));
            expect(phoneField(), findsNothing);
            expect(tester.widget<FilledButton>(save()).onPressed, isNull);
            await fill(noteField(), 'CANCEL-ACCEPT');
            await h.tap(find.widgetWithText(TextButton, 'Отмена'));
            expect((await queue()).any((r) => r['id'] == acceptId), true);
          },
        );
        await h.check(
          'ACCEPT',
          'Принять иностранный номер с причиной без изменения исходного значения',
          () async {
            await edit(acceptId);
            await h.tap(find.text('Оставить как есть'));
            await fill(noteField(), 'AUDIT-PHONE-ACCEPTED');
            await h.tap(save());
            await h.quiet();
            expect((await queue()).any((r) => r['id'] == acceptId), false);
          },
        );
        await h.check(
          'FINAL',
          'После повторного открытия обе разобранные записи отсутствуют',
          () async {
            await open();
            final rows = await queue();
            expect(
              rows.any((r) => [correctId, acceptId].contains(r['id'])),
              false,
            );
          },
        );
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 12)),
    );
  }
}
