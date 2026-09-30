import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_financial_section.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  testWidgets(
    'Director persists every pay rule, opt-out and recoverable failures',
    (tester) async {
      final h = LiveAuditHarness(tester, 'director', 'teacher-compensation');
      await h.initialize(size: const Size(1440, 1100));
      final crm = h.scope.read(magicCrmServiceProvider);
      final student = h.fixture['studentId'] as String;
      final created = await crm.createLessonRaw({
        'clientRef': {'type': 'student', 'id': student},
        'teacherId': h.fixture['teacherId'],
        'roomId': h.fixture['roomId'],
        'branchId': h.fixture['branchId'],
        'scheduledAt': DateTime(
          DateTime.now().year + 1,
          2,
          17,
          15,
        ).toUtc().toIso8601String(),
        'durationMinutes': 60,
        'isTrial': true,
        'completionType': 'standard.success',
        'clientChargeType': 'none',
        'clientChargeValue': 0,
        'teacherCompensationType': 'none',
        'teacherCompensationValue': 0,
        'financialDecision': {
          'settlementTypeKey': 'trial_lesson',
          'teacherCompensationRuleKey': 'trial_lesson',
          'clientDecisions': [
            {'clientId': student, 'chargeType': 'none'},
          ],
        },
      });
      final id = created['id'] as String;
      h.facts.add({'matrixLessonId': id});
      Finder key(String name) => find.byKey(ValueKey(name));
      LessonFinancialSectionModel model() => tester
          .widget<LessonFinancialSection>(find.byType(LessonFinancialSection))
          .model;
      Future<Map<String, dynamic>> read() async =>
          (await crm.listLessons(lessonId: id, limit: 1)).single;
      Future<void> open() async {
        final row = await read();
        await tester.pumpWidget(const SizedBox.shrink());
        await h.mount(
          Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => CreateLessonDialog.show(context, lesson: row),
                child: const Text('Открыть'),
              ),
            ),
          ),
        );
        await h.tap(find.text('Открыть'));
        await h.quiet();
      }

      Future<void> select(String label, {String? amount}) async {
        final toggle = key('lesson-compensation-edit-toggle');
        if (tester.widget<CheckboxListTile>(toggle).value != true) {
          await h.tap(toggle);
        }
        await h.tap(key('lesson-compensation-rule-field'));
        await h.tap(find.text(label).last);
        if (amount != null) {
          await h.tap(key('lesson-compensation-value-field'));
          await tester.enterText(
            key('lesson-compensation-value-field'),
            amount,
          );
        }
        await h.quiet();
      }

      Future<void> reason(String text) async {
        await h.tap(key('lesson-edit-reason'));
        await tester.enterText(key('lesson-edit-reason'), text);
      }

      Future<void> save(String text) async {
        await reason(text);
        await h.tap(find.widgetWithText(FilledButton, 'Рассчитать'));
        await h.quiet();
        expect(key('lesson-decision-preview'), findsOneWidget);
        await h.tap(find.widgetWithText(FilledButton, 'Подтвердить изменения'));
        await h.quiet();
        expect(find.byType(CreateLessonDialog), findsNothing);
      }

      await open();
      final rules = model().references.catalog!.compensationRules;
      expect(rules, isNotEmpty);
      for (final rule in rules) {
        await h.check(
          'RULE-${rule.key}',
          'Сохранить и заново открыть правило «${rule.label}»',
          () async {
            await open();
            expect(
              tester.getRect(key('lesson-compensation-edit-toggle')).top,
              greaterThanOrEqualTo(
                tester.getRect(key('lesson-compensation-rule-field')).bottom,
              ),
            );
            final amount = switch (rule.mode) {
              'percent' => '50',
              'fixed' => '350',
              'hourly' => '850',
              _ => null,
            };
            await select(rule.label, amount: amount);
            await save('X06-${rule.key}');
            await open();
            expect(model().draft.compensationRuleKey, rule.key);
            if (amount != null) {
              expect(
                model().draft.compensationValueMinor,
                '${int.parse(amount) * 100}',
              );
            }
            expect(model().draft.clientChargeType, 'none');
            h.facts.add({
              'step': h.currentStep,
              'lessonId': id,
              'rule': rule.key,
              'mode': rule.mode,
              'valueMinor': model().draft.compensationValueMinor,
              'version': (await read())['version'],
            });
          },
        );
      }
      var rejectPreview = false;
      h.api.rawDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (rejectPreview &&
                options.uri.path.endsWith('/planned-settlement/preview')) {
              rejectPreview = false;
              h.trace(options, 503, error: 'injected transport failure');
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(requestOptions: options, statusCode: 503),
                  type: DioExceptionType.badResponse,
                ),
              );
            } else {
              handler.next(options);
            }
          },
        ),
      );
      await h.check(
        'RETRY',
        'Ошибка расчёта сохраняет сумму и причину; повтор сохраняет один результат',
        () async {
          await open();
          await select('Фиксированная сумма', amount: '777');
          await reason('X06-RETRY');
          final before = await read();
          rejectPreview = true;
          await h.tap(find.widgetWithText(FilledButton, 'Рассчитать'));
          await h.quiet();
          expect(find.byType(CreateLessonDialog), findsOneWidget);
          expect(model().draft.compensationValueMinor, '77700');
          expect(model().draft.plannedSettlementReason, 'X06-RETRY');
          expect((await read())['version'], before['version']);
          await save('X06-RETRY');
          await open();
          expect(model().draft.compensationValueMinor, '77700');
        },
        expectedHttpErrors: [
          (
            method: 'POST',
            path: '/api/crm/lessons/$id/planned-settlement/preview',
            status: 503,
            maxCount: 1,
          ),
        ],
      );
      await h.check(
        'CONFLICT',
        'Конкурентная версия не теряет введённую оплату и требует новый расчёт',
        () async {
          await select('Фиксированная сумма', amount: '888');
          await reason('X06-CONFLICT');
          final before = await read();
          await crm.updateLessonNotes(
            lessonId: id,
            expectedVersion: (before['version'] as num).toInt(),
            notes: 'Concurrent note',
            identity: MagicMutationIdentity.create('audit.x06.concurrent'),
          );
          await h.tap(find.widgetWithText(FilledButton, 'Рассчитать'));
          await h.quiet();
          expect(find.byType(CreateLessonDialog), findsOneWidget);
          expect(model().draft.compensationValueMinor, '88800');
          expect(model().draft.plannedSettlementReason, 'X06-CONFLICT');
          expect(
            h.requests.any(
              (r) => r['step'] == h.currentStep && r['status'] == 409,
            ),
            isTrue,
          );
          await save('X06-CONFLICT');
          await open();
          expect(model().draft.compensationValueMinor, '88800');
          expect((await read())['notes'], 'Concurrent note');
        },
        expectedHttpErrors: [
          (
            method: 'POST',
            path: '/api/crm/lessons/$id/planned-settlement/preview',
            status: 409,
            maxCount: 1,
          ),
        ],
      );
      await h.check(
        'OPT-OUT',
        'Снятие флажка возвращает автоматическую оплату после повторного открытия',
        () async {
          final toggle = key('lesson-compensation-edit-toggle');
          if (tester.widget<CheckboxListTile>(toggle).value != true) {
            await h.tap(toggle);
          }
          await h.tap(toggle);
          expect(model().draft.compensationRuleKey, 'trial_lesson');
          expect(model().draft.compensationTouched, isFalse);
          await save('X06-AUTOMATIC');
          await open();
          expect(model().draft.compensationRuleKey, 'trial_lesson');
          expect(model().draft.teacherCompensationSource, 'automatic');
          expect(model().draft.compensationTouched, isFalse);
          h.facts.add({
            'step': h.currentStep,
            'lessonId': id,
            'source': model().draft.teacherCompensationSource,
          });
        },
      );
      await h.finish();
    },
  );
}
