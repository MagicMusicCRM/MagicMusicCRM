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
      '$role lead merge winner cancellation and undo',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'lead-merge');
        await h.initialize(size: const Size(1440, 1250));
        final crm = h.scope.read(magicCrmServiceProvider),
            item = (h.fixture['mergeCases'] as Map)[role] as Map;
        final winner = item['winnerId'] as String,
            loser = item['loserId'] as String,
            comment = item['commentId'] as String,
            name = 'MERGE-$role Аудит';
        Future<bool> candidate() async => (await crm.listMergeCandidates(
          limit: 100,
        )).any((r) => r['loserId'] == winner && r['winnerId'] == loser);
        Future<void> commentsAt(String id, bool exists) async {
          final rows = await crm.listComments(entityType: 'lead', entityId: id);
          h.facts.add({
            'step': h.currentStep,
            'entityId': id,
            'comments': rows,
          });
          expect(rows.any((r) => r['id'] == comment), exists);
        }

        Future<void> open() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await h.mount(
            SystemSettingsRouteScreen(key: UniqueKey(), initialArea: 'data'),
          );
          await h.quiet();
        }

        Future<void> mergeDialog() async {
          final card = find
              .ancestor(
                of: find.text(name),
                matching: find.byWidgetPredicate(
                  (w) => w.runtimeType.toString() == '_MergeCandidateCard',
                ),
              )
              .first;
          await h.tap(
            find.descendant(
              of: card,
              matching: find.widgetWithText(ElevatedButton, 'Объединить'),
            ),
          );
          await h.quiet();
        }

        Future<void> commit() async {
          await h.tap(find.text('Запись 1').last);
          await h.tap(find.widgetWithText(TextButton, 'Объединить'));
          await h.quiet();
        }

        await h.check(
          'OPEN',
          'Найти пару дублей по имени и нормализованному телефону',
          () async {
            await open();
            expect(await candidate(), true);
            expect(find.text(name), findsOneWidget);
          },
        );
        await h.check(
          'CANCEL',
          'Выбор основной записи и отмена не объединяют лиды',
          () async {
            await mergeDialog();
            await h.tap(find.text('Запись 1').last);
            await h.tap(find.widgetWithText(TextButton, 'Отмена'));
            expect(await candidate(), true);
            await commentsAt(loser, true);
          },
        );
        await h.check(
          'REQUIRED-WINNER',
          'Подтверждение недоступно до выбора основной карточки',
          () async {
            await mergeDialog();
            expect(
              tester
                  .widget<TextButton>(
                    find.widgetWithText(TextButton, 'Объединить'),
                  )
                  .onPressed,
              isNull,
            );
            await h.tap(find.widgetWithText(TextButton, 'Отмена'));
          },
        );
        await h.check(
          'MERGE',
          'Подтверждение объединяет пару и переносит исходный комментарий на выбранную карточку',
          () async {
            await mergeDialog();
            await commit();
            expect(find.text('Лиды объединены'), findsOneWidget);
            expect(await candidate(), false);
            await commentsAt(winner, true);
          },
        );
        await h.check(
          'UNDO',
          'Отмена объединения возвращает дубль и его комментарий',
          () async {
            await h.tap(
              find.widgetWithText(TextButton, 'Отменить объединение'),
            );
            await h.quiet();
            expect(await candidate(), true);
            await commentsAt(loser, true);
            await commentsAt(winner, false);
          },
        );
        await h.check(
          'REOPEN',
          'Повторное открытие показывает восстановленную пару',
          () async {
            await open();
            expect(await candidate(), true);
            expect(find.text(name), findsOneWidget);
          },
        );
        await h.check(
          'MERGE-KEEP',
          'Повторное объединение и Готово сохраняют окончательный результат',
          () async {
            await mergeDialog();
            await commit();
            await h.tap(find.widgetWithText(TextButton, 'Готово'));
            await h.quiet();
            expect(await candidate(), false);
            await commentsAt(winner, true);
          },
        );
        await h.check(
          'FINAL',
          'После повторного открытия объединённая пара не появляется снова',
          () async {
            await open();
            expect(await candidate(), false);
            expect(find.text(name), findsNothing);
            await commentsAt(winner, true);
          },
        );
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 12)),
    );
  }
}
