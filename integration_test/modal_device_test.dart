import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/core/widgets/searchable_select.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision_flow.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_details_sheet.dart';

import 'evidence_screenshot.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('representative lesson surfaces follow the adaptive policy', (
    tester,
  ) async {
    await initializeDateFormatting('ru');
    await tester.pumpWidget(
      RepaintBoundary(
        key: evidenceRootKey,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const _ModalDeviceHome(),
        ),
      ),
    );

    await tester.tap(find.text('Быстрый просмотр'));
    await tester.pumpAndSettle();
    expect(find.text('Анна Смирнова'), findsNWidgets(2));
    expect(find.text('Конфликт'), findsOneWidget);
    expect(find.textContaining('Причина конфликта'), findsOneWidget);
    expect(find.textContaining('ConflictException'), findsNothing);
    expect(find.text('Исправить расчёт'), findsOneWidget);
    expect(find.text('Перенести или изменить'), findsOneWidget);
    await captureEvidence(tester, 'lesson-quick-view');
    await captureEvidence(tester, 'lesson-settlement-review-required');
    if (const bool.fromEnvironment('V6_VISUAL_CHECK')) {
      debugPrint('V6_MODAL_SCREENSHOT_READY');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 30)),
      );
    }

    await tester.tap(find.text('Перенести или изменить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выбрать клиента'));
    await tester.pumpAndSettle();
    expect(find.text('Поиск по ФИО'), findsOneWidget);
    await tester.tap(find.text('Анна Смирнова').last);
    await tester.pumpAndSettle();
    expect(find.text('Выбрано: Анна Смирнова'), findsOneWidget);
    await tester.tap(find.text('LessonDecision v7'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('lesson-decision-reason')),
      'Клиент попросил перенести',
    );
    await tester.ensureVisible(
      find.byKey(const Key('lesson-decision-settlement')),
    );
    await tester.tap(find.byKey(const Key('lesson-decision-settlement')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Бесплатное занятие').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('lesson-decision-compensation')),
    );
    await tester.tap(find.byKey(const Key('lesson-decision-compensation')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Не оплачивать').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('lesson-decision-submit')));
    await tester.tap(find.byKey(const Key('lesson-decision-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lesson-decision-preview')), findsOneWidget);
    expect(find.textContaining('Клиент:'), findsOneWidget);
    expect(find.textContaining('Преподаватель:'), findsOneWidget);
    await captureEvidence(tester, 'lesson-reschedule-reason-preview');
    await tester.ensureVisible(find.byKey(const Key('lesson-decision-submit')));
    await tester.tap(find.byKey(const Key('lesson-decision-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Решение: применено'), findsOneWidget);

    await tester.tap(find.text('Перенести завершённое занятие'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('completed-reschedule-notice')),
      findsOneWidget,
    );
    expect(find.textContaining('без удаления истории'), findsOneWidget);
    expect(find.byKey(const Key('lesson-decision-settlement')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('lesson-decision-reason')),
      'Исправление ошибочно завершённого занятия',
    );
    await tester.ensureVisible(find.byKey(const Key('lesson-decision-submit')));
    await tester.tap(find.byKey(const Key('lesson-decision-submit')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'Прежние списание и оплата преподавателю будут отменены',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('COMPLETED_LESSON_EFFECTS_WILL_BE_REVERSED'),
      findsNothing,
    );
    await captureEvidence(
      tester,
      'lesson-completed-reschedule-reversal-preview',
    );
    await tester.ensureVisible(find.byKey(const Key('lesson-decision-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lesson-decision-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Перенос завершённого занятия: применён'), findsOneWidget);

    await tester.tap(find.text('Отменить занятие'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('lesson-decision-reason')),
      'Клиент предупредил об отмене заранее',
    );
    await tester.tap(find.byKey(const Key('lesson-decision-settlement')));
    await tester.pumpAndSettle();
    for (final label in const [
      'Бесплатное занятие',
      'Оплачиваемый пропуск',
      'Частично оплачиваемый пропуск',
      'Неоплачиваемый пропуск',
      'Занятие со штрафом',
    ]) {
      expect(find.text(label), findsWidgets);
    }
    await captureEvidence(tester, 'lesson-cancel-applicable-types');
    await tester.tap(find.text('Частично оплачиваемый пропуск').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('lesson-decision-compensation')),
    );
    await tester.tap(find.byKey(const Key('lesson-decision-compensation')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Полная стандартная ставка').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('lesson-decision-submit')));
    await tester.tap(find.byKey(const Key('lesson-decision-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('0.50 ч'), findsOneWidget);
    expect(find.textContaining('700,00 ₽'), findsOneWidget);
    await captureEvidence(tester, 'lesson-cancel-financial-preview');

    await tester.tap(find.byKey(const Key('lesson-decision-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Версия обновлена'), findsOneWidget);
    expect(find.text('Рассчитать'), findsOneWidget);
    await captureEvidence(tester, 'lesson-cancel-stale-version-recovered');

    await tester.tap(find.byKey(const Key('lesson-decision-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lesson-decision-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Отмена занятия: применена'), findsOneWidget);
    debugPrint('V6_MODAL_DEVICE_PASS');
  });

  testWidgets('real form reschedules a lesson without drag-and-drop', (
    tester,
  ) async {
    await initializeDateFormatting('ru');
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _DecisionDeviceApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicApiClientProvider.overrideWithValue(api)],
        child: RepaintBoundary(
          key: evidenceRootKey,
          child: MaterialApp(
            theme: AppTheme.dark,
            home: _RescheduleFormDeviceHome(api: api),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Открыть форму переноса'));
    await tester.pumpAndSettle();
    expect(find.text('Перенести или изменить занятие'), findsOneWidget);
    expect(
      tester
          .widget<SearchablePickerField>(
            find.byKey(const ValueKey('lesson-client-field')),
          )
          .selectedLabel,
      'Анна Смирнова · Student',
    );
    expect(find.text('07.08.2026'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('lesson-date-field')));
    await tester.tap(find.byKey(const ValueKey('lesson-date-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('8'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('08.08.2026'), findsOneWidget);
    await captureEvidence(tester, 'lesson-reschedule-real-form');

    await tester.ensureVisible(find.text('Перейти к расчёту'));
    await tester.tap(find.text('Перейти к расчёту'));
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.enterText(
      find.byKey(const Key('lesson-decision-reason')),
      'Клиент попросил перенести на субботу',
    );
    await tester.tap(find.byKey(const Key('lesson-decision-settlement')));
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Бесплатное занятие').last);
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.ensureVisible(
      find.byKey(const Key('lesson-decision-compensation')),
    );
    await tester.tap(find.byKey(const Key('lesson-decision-compensation')));
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Не оплачивать').last);
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.ensureVisible(find.byKey(const Key('lesson-decision-submit')));
    await tester.tap(find.byKey(const Key('lesson-decision-submit')));
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('lesson-decision-preview')), findsOneWidget);
    await captureEvidence(tester, 'lesson-reschedule-real-form-preview');
    await tester.ensureVisible(find.byKey(const Key('lesson-decision-submit')));
    await tester.tap(find.byKey(const Key('lesson-decision-submit')));
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Форма переноса: применена'), findsOneWidget);
    expect(api.previews, hasLength(1));
    expect(api.commits, hasLength(1));
    final preview = api.previews.single;
    final commit = api.commits.single;
    expect(preview['expectedVersion'], 4);
    expect(preview['reasonText'], 'Клиент попросил перенести на субботу');
    expect(preview['successor']['scheduledAt'], '2026-08-08T09:00:00.000Z');
    expect(commit['successor'], preview['successor']);
    expect(commit['financialDecision'], {
      'settlementTypeKey': 'free_lesson',
      'teacherCompensationRuleKey': 'none',
    });
    debugPrint('UAT_090_REAL_FORM_DEVICE_PASS');
  });

  testWidgets('real form substitutes an allowed teacher and room', (
    tester,
  ) async {
    await initializeDateFormatting('ru');
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _DecisionDeviceApi(replacementOptions: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicApiClientProvider.overrideWithValue(api)],
        child: RepaintBoundary(
          key: evidenceRootKey,
          child: MaterialApp(
            theme: AppTheme.dark,
            home: _RescheduleFormDeviceHome(api: api),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Открыть форму переноса'));
    await tester.pumpAndSettle();
    final teacherField = tester.widget<SearchablePickerField>(
      find.byKey(const ValueKey('lesson-teacher-field')),
    );
    expect(teacherField.items.map((item) => item.label), [
      'Пётр Педагогов',
      'Мария Сменова',
    ]);
    final roomField = tester.widget<SearchablePickerField>(
      find.byKey(const ValueKey('lesson-room-field')),
    );
    expect(roomField.items.map((item) => item.label), ['Зал 1', 'Зал 2']);
    expect(
      find.byKey(const ValueKey('lesson-replacement-availability-hint')),
      findsOneWidget,
    );

    await _chooseDeviceSearchable(
      tester,
      const ValueKey('lesson-teacher-field'),
      'Мария Сменова',
    );
    await _chooseDeviceSearchable(
      tester,
      const ValueKey('lesson-room-field'),
      'Зал 2',
    );
    await captureEvidence(tester, 'lesson-replacement-options');

    await tester.ensureVisible(find.text('Перейти к расчёту'));
    await tester.tap(find.text('Перейти к расчёту'));
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.enterText(
      find.byKey(const Key('lesson-decision-reason')),
      'Согласованная подмена преподавателя и аудитории',
    );
    await tester.tap(find.byKey(const Key('lesson-decision-settlement')));
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Бесплатное занятие').last);
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.ensureVisible(
      find.byKey(const Key('lesson-decision-compensation')),
    );
    await tester.tap(find.byKey(const Key('lesson-decision-compensation')));
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Не оплачивать').last);
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.ensureVisible(find.byKey(const Key('lesson-decision-submit')));
    await tester.tap(find.byKey(const Key('lesson-decision-submit')));
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('lesson-decision-preview')), findsOneWidget);
    await captureEvidence(tester, 'lesson-replacement-preview');
    await tester.tap(find.byKey(const Key('lesson-decision-submit')));
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(api.previews, hasLength(1));
    expect(api.commits, hasLength(1));
    expect(
      api.commits.single['successor']['teacherId'],
      '40000000-0000-4000-8000-000000000002',
    );
    expect(
      api.commits.single['successor']['roomId'],
      '50000000-0000-4000-8000-000000000002',
    );
    debugPrint('UAT_091_REPLACEMENT_DEVICE_PASS');
  });

  testWidgets('constraint preview blocks commit with human-readable reasons', (
    tester,
  ) async {
    await initializeDateFormatting('ru');
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _DecisionDeviceApi(constraintViolations: true);
    debugPrint('UAT_092_STEP_START');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicApiClientProvider.overrideWithValue(api)],
        child: RepaintBoundary(
          key: evidenceRootKey,
          child: MaterialApp(
            theme: AppTheme.dark,
            home: _RescheduleFormDeviceHome(api: api),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Открыть форму переноса'));
    await tester.pumpAndSettle();
    debugPrint('UAT_092_STEP_FORM_OPEN');
    await tester.ensureVisible(find.byKey(const ValueKey('lesson-date-field')));
    await tester.tap(find.byKey(const ValueKey('lesson-date-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('8'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    debugPrint('UAT_092_STEP_DATE_CHANGED');
    await tester.ensureVisible(find.text('Перейти к расчёту'));
    await tester.tap(find.text('Перейти к расчёту'));
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    debugPrint('UAT_092_STEP_DECISION_OPEN');
    await tester.enterText(
      find.byKey(const Key('lesson-decision-reason')),
      'Проверка ограничений перед переносом',
    );
    await tester.tap(find.byKey(const Key('lesson-decision-settlement')));
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Бесплатное занятие').last);
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.ensureVisible(
      find.byKey(const Key('lesson-decision-compensation')),
    );
    await tester.tap(find.byKey(const Key('lesson-decision-compensation')));
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Не оплачивать').last);
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.ensureVisible(find.byKey(const Key('lesson-decision-submit')));
    await tester.tap(find.byKey(const Key('lesson-decision-submit')));
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    debugPrint('UAT_092_STEP_PREVIEW_READY');

    expect(find.text('Изменение заблокировано'), findsOneWidget);
    for (final reason in const [
      'Некорректное время занятия',
      'Филиал закрыт в это время',
      'Преподаватель недоступен',
      'Преподаватель не назначен в выбранный филиал',
      'Аудитория относится к другому филиалу',
      'У преподавателя уже есть занятие в это время',
      'У клиента уже есть занятие в это время',
      'Аудитория уже занята',
    ]) {
      expect(find.textContaining(reason), findsOneWidget);
    }
    expect(api.previews, hasLength(1));
    expect(api.commits, isEmpty);
    debugPrint('UAT_092_STEP_ASSERTED');
    await captureEvidence(tester, 'lesson-constraint-blocked-preview');
    debugPrint('UAT_092_STEP_SCREENSHOT_WRITTEN');
    debugPrint('UAT_092_CONSTRAINT_DEVICE_PASS');
  });

  testWidgets('authoritative create race keeps the losing Manager draft', (
    tester,
  ) async {
    await initializeDateFormatting('ru');
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _DecisionDeviceApi(authoritativeCreateConflict: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicApiClientProvider.overrideWithValue(api)],
        child: RepaintBoundary(
          key: evidenceRootKey,
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const _CreateLessonRaceDeviceHome(),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Открыть создание занятия'));
    await tester.pumpAndSettle();
    await _chooseDeviceSearchable(
      tester,
      const ValueKey('lesson-client-field'),
      'Анна Смирнова',
    );
    await _chooseDeviceSearchable(
      tester,
      const ValueKey('lesson-teacher-field'),
      'Пётр Педагогов',
    );
    await _chooseDeviceSearchable(
      tester,
      const ValueKey('lesson-room-field'),
      'Зал 1',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('lesson-settlement-type-field')),
    );
    await tester.tap(
      find.byKey(const ValueKey('lesson-settlement-type-field')),
    );
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Бесплатное занятие').last);
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(
      find.byKey(const ValueKey('lesson-compensation-rule-field')),
    );
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Не оплачивать').last);
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.ensureVisible(
      find.byKey(const ValueKey('lesson-duration-field')),
    );
    await tester.tap(find.byKey(const ValueKey('lesson-duration-field')));
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('90 мин').last);
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byKey(const ValueKey('lesson-trial-toggle')));
    await tester.ensureVisible(find.text('Создать'));
    await tester.tap(find.text('Создать'));
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(api.lessonConstraintPreviews, hasLength(1));
    expect(api.createAttempts, hasLength(1));
    expect(find.text('Занятие не сохранено'), findsOneWidget);
    expect(find.text('Аудитория уже занята'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('conflict-lesson-10000000-0000-4000-8000-000000000093'),
      ),
      findsOneWidget,
    );
    expect(find.text('Всё равно назначить'), findsNothing);
    await captureEvidence(tester, 'lesson-concurrent-manager-conflict');

    await tester.tap(find.text('Исправить'));
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Новое занятие'), findsOneWidget);
    expect(
      tester
          .widget<SearchablePickerField>(
            find.byKey(const ValueKey('lesson-client-field')),
          )
          .selectedId,
      'student:30000000-0000-4000-8000-000000000001',
    );
    expect(
      tester
          .widget<SearchablePickerField>(
            find.byKey(const ValueKey('lesson-teacher-field')),
          )
          .selectedId,
      '40000000-0000-4000-8000-000000000001',
    );
    expect(
      tester
          .widget<SearchablePickerField>(
            find.byKey(const ValueKey('lesson-room-field')),
          )
          .selectedId,
      '50000000-0000-4000-8000-000000000001',
    );
    expect(
      tester
          .state<FormFieldState<int>>(
            find.byKey(const ValueKey('lesson-duration-field')),
          )
          .value,
      90,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('lesson-trial-toggle')),
          )
          .value,
      isTrue,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('lesson-client-field')),
    );
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await captureEvidence(tester, 'lesson-concurrent-manager-draft-retained');
    debugPrint('UAT_093_MANAGER_RACE_DEVICE_PASS');
  });
}

Future<void> _chooseDeviceSearchable(
  WidgetTester tester,
  Key field,
  String option,
) async {
  await tester.ensureVisible(find.byKey(field));
  await tester.tap(find.byKey(field));
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.tap(
    find.descendant(
      of: find.byType(Scrollbar).last,
      matching: find.text(option),
    ),
  );
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _RescheduleFormDeviceHome extends StatefulWidget {
  const _RescheduleFormDeviceHome({required this.api});

  final _DecisionDeviceApi api;

  @override
  State<_RescheduleFormDeviceHome> createState() =>
      _RescheduleFormDeviceHomeState();
}

class _RescheduleFormDeviceHomeState extends State<_RescheduleFormDeviceHome> {
  bool _applied = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('UAT-090 · перенос через форму')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              onPressed: () async {
                final changed = await CreateLessonDialog.show(
                  context,
                  lesson: const {
                    'id': '10000000-0000-4000-8000-000000000090',
                    'version': 4,
                    'student_id': '30000000-0000-4000-8000-000000000001',
                    'student_name': 'Анна Смирнова',
                    'teacher_id': '40000000-0000-4000-8000-000000000001',
                    'branch_id': '20000000-0000-4000-8000-000000000001',
                    'room_id': '50000000-0000-4000-8000-000000000001',
                    'scheduled_at': '2026-08-07T09:00:00.000Z',
                    'duration_minutes': 60,
                    'snapshot_trial': false,
                    'completion_type': 'standard.success',
                    'client_charge_type': 'none',
                    'client_charge_value': 0,
                    'teacher_compensation_type': 'none',
                    'teacher_compensation_value': 0,
                  },
                );
                if (mounted && changed == true) {
                  setState(() => _applied = true);
                }
              },
              child: const Text('Открыть форму переноса'),
            ),
            const SizedBox(height: 12),
            Text('Форма переноса: ${_applied ? 'применена' : 'не применена'}'),
          ],
        ),
      ),
    );
  }
}

class _CreateLessonRaceDeviceHome extends StatelessWidget {
  const _CreateLessonRaceDeviceHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('UAT-093 · гонка двух Manager')),
      body: Center(
        child: FilledButton(
          onPressed: () => CreateLessonDialog.show(context),
          child: const Text('Открыть создание занятия'),
        ),
      ),
    );
  }
}

class _ModalDeviceHome extends StatefulWidget {
  const _ModalDeviceHome();

  @override
  State<_ModalDeviceHome> createState() => _ModalDeviceHomeState();
}

class _ModalDeviceHomeState extends State<_ModalDeviceHome> {
  String? _selected;
  bool _decisionApplied = false;
  bool _completedDecisionApplied = false;
  bool _cancelDecisionApplied = false;
  final _decisionApi = _DecisionDeviceApi();
  final _completedDecisionApi = _DecisionDeviceApi(completed: true);
  final _cancelDecisionApi = _DecisionDeviceApi(staleFirstCommit: true);
  final Map<String, dynamic> _cancelLesson = {
    'id': '10000000-0000-4000-8000-000000000003',
    'version': 4,
    'branch_id': '20000000-0000-4000-8000-000000000001',
    'scheduled_at': '2026-08-10T09:00:00.000Z',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('V6 surface QA')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          FilledButton(
            onPressed: () => showLessonDetailsSheet(
              context,
              teacherName: 'Пётр Педагогов',
              studentName: 'Анна Смирнова',
              roomName: 'Зал 1',
              timeRange: '14:00–15:00',
              currentStatus: 'settlement_pending',
              conflicts: const [],
              settlementIssue: lessonSettlementIssueLabel('ConflictException'),
              lessonId: 'lesson-1',
              onEdit: () {},
              onCancel: () async {},
              onSettle: () async {},
            ),
            child: const Text('Быстрый просмотр'),
          ),
          FilledButton(
            onPressed: () => SearchableSelect.show(
              context: context,
              title: 'Выберите клиента',
              hintText: 'Поиск по ФИО',
              items: [
                SearchableSelectItem(id: 'student-1', label: 'Анна Смирнова'),
              ],
              isNullable: false,
              onSelected: (item) => setState(() => _selected = item?.label),
            ),
            child: const Text('Выбрать клиента'),
          ),
          Text('Выбрано: ${_selected ?? '—'}'),
          FilledButton(
            onPressed: () async {
              final result = await showLessonDecisionFlow(
                context,
                crm: MagicCrmService(_decisionApi),
                operation: LessonDecisionOperation.reschedule,
                lesson: const {
                  'id': '10000000-0000-4000-8000-000000000001',
                  'version': 4,
                  'branch_id': '20000000-0000-4000-8000-000000000001',
                  'scheduled_at': '2026-08-07T09:00:00.000Z',
                },
                successor: const {
                  'scheduledAt': '2026-08-08T10:00:00.000Z',
                  'durationMinutes': 60,
                },
              );
              if (mounted && result == true) {
                setState(() => _decisionApplied = true);
              }
            },
            child: const Text('LessonDecision v7'),
          ),
          Text('Решение: ${_decisionApplied ? 'применено' : 'не применено'}'),
          FilledButton(
            onPressed: () async {
              final result = await showLessonDecisionFlow(
                context,
                crm: MagicCrmService(_completedDecisionApi),
                operation: LessonDecisionOperation.reschedule,
                lesson: const {
                  'id': '10000000-0000-4000-8000-000000000002',
                  'version': 7,
                  'branch_id': '20000000-0000-4000-8000-000000000001',
                  'scheduled_at': '2026-08-06T09:00:00.000Z',
                  'lifecycle_state': 'successfully_completed',
                },
                successor: const {
                  'scheduledAt': '2026-08-09T10:00:00.000Z',
                  'durationMinutes': 60,
                },
              );
              if (mounted && result == true) {
                setState(() => _completedDecisionApplied = true);
              }
            },
            child: const Text('Перенести завершённое занятие'),
          ),
          Text(
            'Перенос завершённого занятия: '
            '${_completedDecisionApplied ? 'применён' : 'не применён'}',
          ),
          FilledButton(
            onPressed: () async {
              final result = await showLessonDecisionFlow(
                context,
                crm: MagicCrmService(_cancelDecisionApi),
                operation: LessonDecisionOperation.cancel,
                lesson: _cancelLesson,
              );
              if (mounted && result == true) {
                setState(() => _cancelDecisionApplied = true);
              }
            },
            child: const Text('Отменить занятие'),
          ),
          Text(
            'Отмена занятия: '
            '${_cancelDecisionApplied ? 'применена' : 'не применена'}',
          ),
        ],
      ),
    );
  }
}

class _DecisionDeviceApi extends MagicApiClient {
  _DecisionDeviceApi({
    this.completed = false,
    this.replacementOptions = false,
    this.constraintViolations = false,
    this.authoritativeCreateConflict = false,
    this.staleFirstCommit = false,
  }) : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final bool completed;
  final bool replacementOptions;
  final bool constraintViolations;
  final bool authoritativeCreateConflict;
  final bool staleFirstCommit;
  final previews = <Map<String, dynamic>>[];
  final commits = <Map<String, dynamic>>[];
  final lessonConstraintPreviews = <Map<String, dynamic>>[];
  final createAttempts = <Map<String, dynamic>>[];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/teachers') {
      return <String, dynamic>{
            'items': [
              {
                'id': '40000000-0000-4000-8000-000000000001',
                'firstName': 'Пётр',
                'lastName': 'Педагогов',
                'status': 'active',
                'assignedBranches': [
                  {
                    'id': '20000000-0000-4000-8000-000000000001',
                    'name': 'Главный филиал',
                  },
                ],
              },
              if (replacementOptions) ...[
                {
                  'id': '40000000-0000-4000-8000-000000000002',
                  'firstName': 'Мария',
                  'lastName': 'Сменова',
                  'status': 'active',
                  'assignedBranches': [
                    {
                      'id': '20000000-0000-4000-8000-000000000001',
                      'name': 'Главный филиал',
                    },
                  ],
                },
                {
                  'id': '40000000-0000-4000-8000-000000000003',
                  'firstName': 'Ирина',
                  'lastName': 'Неактивная',
                  'status': 'inactive',
                  'assignedBranches': [
                    {
                      'id': '20000000-0000-4000-8000-000000000001',
                      'name': 'Главный филиал',
                    },
                  ],
                },
              ],
            ],
          }
          as T;
    }
    if (path == '/crm/branches') {
      return <String, dynamic>{
            'items': [
              {
                'id': '20000000-0000-4000-8000-000000000001',
                'name': 'Главный филиал',
                'utcOffsetMinutes': 180,
              },
            ],
          }
          as T;
    }
    if (path == '/crm/rooms') {
      return <String, dynamic>{
            'items': [
              {
                'id': '50000000-0000-4000-8000-000000000001',
                'name': 'Зал 1',
                'branchId': '20000000-0000-4000-8000-000000000001',
              },
              if (replacementOptions) ...[
                {
                  'id': '50000000-0000-4000-8000-000000000002',
                  'name': 'Зал 2',
                  'branchId': '20000000-0000-4000-8000-000000000001',
                },
                {
                  'id': '50000000-0000-4000-8000-000000000003',
                  'name': 'Чужой зал',
                  'branchId': '20000000-0000-4000-8000-000000000099',
                },
              ],
            ],
          }
          as T;
    }
    if (path == '/crm/clients/search') {
      return <String, dynamic>{
            'items': const [
              {
                'ref': {
                  'type': 'student',
                  'id': '30000000-0000-4000-8000-000000000001',
                },
                'label': 'Анна Смирнова',
                'branchId': '20000000-0000-4000-8000-000000000001',
                'lifecycleState': 'active',
                'tombstone': false,
                'version': 1,
                'links': [],
              },
            ],
          }
          as T;
    }
    if (path == '/crm/subscriptions') {
      return <String, dynamic>{'items': const []} as T;
    }
    if (path.startsWith('/crm/students/') && path.endsWith('/commerce')) {
      return <String, dynamic>{
            'projection': 'admin_scoped',
            'student': {
              'studentId': '30000000-0000-4000-8000-000000000001',
              'accounts': const [],
              'subscriptions': const [],
              'movements': const [],
              'technicalHistory': const [],
              'lessonBalance': const {
                'activeSubscriptionCount': 0,
                'total': 0,
                'used': 0,
                'reserved': 0,
                'paid': 0,
                'available': 0,
                'debts': [],
                'nextPaymentAt': null,
                'expiresAt': null,
              },
            },
          }
          as T;
    }
    return <String, dynamic>{
          'settlementTypes': const [
            {
              'stableKey': 'free_lesson',
              'label': 'Бесплатное занятие',
              'colorToken': 'warning',
              'allowedContexts': ['cancel', 'reschedule', 'settle'],
              'active': true,
              'order': 0,
              'hourShareBasisPoints': 0,
              'fixedPenaltyMinor': '0',
            },
            {
              'stableKey': 'paid_miss',
              'label': 'Оплачиваемый пропуск',
              'colorToken': 'blue',
              'allowedContexts': ['cancel', 'reschedule', 'settle'],
              'active': true,
              'order': 1,
              'hourShareBasisPoints': 10000,
              'fixedPenaltyMinor': '0',
            },
            {
              'stableKey': 'partially_paid_miss',
              'label': 'Частично оплачиваемый пропуск',
              'colorToken': 'cyan',
              'allowedContexts': ['cancel', 'reschedule', 'settle'],
              'active': true,
              'order': 2,
              'hourShareBasisPoints': 5000,
              'fixedPenaltyMinor': '0',
            },
            {
              'stableKey': 'unpaid_miss',
              'label': 'Неоплачиваемый пропуск',
              'colorToken': 'neutral',
              'allowedContexts': ['cancel', 'reschedule', 'settle'],
              'active': true,
              'order': 3,
              'hourShareBasisPoints': 0,
              'fixedPenaltyMinor': '0',
            },
            {
              'stableKey': 'penalty_lesson',
              'label': 'Занятие со штрафом',
              'colorToken': 'violet',
              'allowedContexts': ['cancel', 'reschedule', 'settle'],
              'active': true,
              'order': 4,
              'hourShareBasisPoints': 10000,
              'fixedPenaltyMinor': '0',
            },
          ],
          'teacherCompensationRules': const [
            {
              'stableKey': 'none',
              'label': 'Не оплачивать',
              'mode': 'none',
              'value': '0',
              'active': true,
              'order': 0,
            },
            {
              'stableKey': 'standard',
              'label': 'Полная стандартная ставка',
              'mode': 'standard',
              'value': '0',
              'active': true,
              'order': 1,
            },
          ],
        }
        as T;
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/lessons/constraints/preview') {
      lessonConstraintPreviews.add(Map<String, dynamic>.from(data as Map));
      return <String, dynamic>{'valid': true, 'violations': const []} as T;
    }
    if (path == '/crm/lessons') {
      createAttempts.add(Map<String, dynamic>.from(data as Map));
      if (authoritativeCreateConflict) {
        throw MagicApiException(
          statusCode: 422,
          message: 'Lesson draft violates schedule constraints.',
          details: const {
            'code': 'LESSON_CONSTRAINT_VIOLATIONS',
            'violations': [
              {
                'code': 'ROOM_OVERLAP',
                'resource': {
                  'type': 'room',
                  'id': '50000000-0000-4000-8000-000000000001',
                },
                'conflictingLessonIds': [
                  '10000000-0000-4000-8000-000000000093',
                ],
                'ruleIds': [],
              },
            ],
          },
        );
      }
      return <String, dynamic>{
            'id': '10000000-0000-4000-8000-000000000094',
            'version': 1,
          }
          as T;
    }
    previews.add(Map<String, dynamic>.from(data as Map));
    final decision = Map<String, dynamic>.from(
      previews.last['financialDecision'] as Map,
    );
    final settlementKey = decision['settlementTypeKey']?.toString();
    const settlementLabels = {
      'free_lesson': 'Бесплатное занятие',
      'paid_miss': 'Оплачиваемый пропуск',
      'partially_paid_miss': 'Частично оплачиваемый пропуск',
      'unpaid_miss': 'Неоплачиваемый пропуск',
      'penalty_lesson': 'Занятие со штрафом',
    };
    const settlementUnits = {
      'free_lesson': '0.00',
      'paid_miss': '1.00',
      'partially_paid_miss': '0.50',
      'unpaid_miss': '0.00',
      'penalty_lesson': '1.00',
    };
    final standardCompensation =
        decision['teacherCompensationRuleKey'] == 'standard';
    return <String, dynamic>{
          'source': {
            'state': completed ? 'successfully_completed' : 'scheduled',
          },
          'successor': const {'state': 'scheduled'},
          'canConfirm': !constraintViolations,
          if (!constraintViolations) 'previewToken': 'device-preview',
          'violations': [
            if (constraintViolations) ...const [
              {
                'code': 'INVALID_INTERVAL',
                'resource': {'type': 'interval', 'id': 'candidate'},
              },
              {
                'code': 'OUTSIDE_BRANCH_HOURS',
                'resource': {'type': 'branch', 'id': 'branch-1'},
              },
              {
                'code': 'TEACHER_UNAVAILABLE',
                'resource': {'type': 'teacher', 'id': 'teacher-1'},
              },
              {
                'code': 'TEACHER_BRANCH_MISMATCH',
                'resource': {'type': 'teacher', 'id': 'teacher-1'},
              },
              {
                'code': 'ROOM_BRANCH_MISMATCH',
                'resource': {'type': 'room', 'id': 'room-1'},
              },
              {
                'code': 'TEACHER_OVERLAP',
                'resource': {'type': 'teacher', 'id': 'teacher-1'},
              },
              {
                'code': 'CLIENT_OVERLAP',
                'resource': {'type': 'client', 'id': 'student-1'},
              },
              {
                'code': 'ROOM_OVERLAP',
                'resource': {'type': 'room', 'id': 'room-1'},
              },
            ],
          ],
          if (!constraintViolations)
            'financialPreview': {
              'clientFacts': [
                {
                  'settlementLabel': settlementLabels[settlementKey],
                  'units': settlementUnits[settlementKey],
                  'amountMinor': '0',
                },
              ],
              'teacherFact': <String, dynamic>{
                'compensationRuleLabel': standardCompensation
                    ? 'Полная стандартная ставка'
                    : 'Не оплачивать',
                'amountMinor': standardCompensation ? '70000' : '0',
              },
            },
          'warnings': [
            if (completed) 'COMPLETED_LESSON_EFFECTS_WILL_BE_REVERSED',
          ],
        }
        as T;
  }

  @override
  Future<T> postIdempotent<T>(
    String path, {
    required MagicMutationIdentity identity,
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    commits.add(Map<String, dynamic>.from(data as Map));
    if (staleFirstCommit && commits.length == 1) {
      throw const MagicApiException(
        statusCode: 409,
        message: 'Conflict',
        details: {
          'code': 'STALE_LESSON_VERSION',
          'expectedVersion': 4,
          'currentVersion': 5,
        },
      );
    }
    return <String, dynamic>{'transitionId': 'device-transition'} as T;
  }
}
