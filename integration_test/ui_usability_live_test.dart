import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_employee_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_group_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_teacher_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/client_create_dialogs.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_panel.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/finance_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/students_board_widget.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/messenger_screen.dart';

import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_editor_view.dart';

import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/client_forms_api.dart';

import 'package:magic_music_crm/core/services/magic_messenger_service.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_header.dart';
import 'package:magic_music_crm/core/widgets/telegram/message_bubble.dart';

import 'package:magic_music_crm/core/navigation/context_route_state.dart';

import 'evidence_screenshot.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  testWidgets('UI usability against isolated local API', (tester) async {
    final h = LiveAuditHarness(tester, 'director', 'ui-usability');
    await h.initialize(size: const Size(1280, 800));
    final crm = h.scope.read(magicCrmServiceProvider);
    final branchId = h.fixture['branchId'] as String;
    final snapshot = await h.scope.read(capabilitySnapshotProvider.future);
    Future<void> mount(
      Widget child, {
      Size size = const Size(1280, 800),
    }) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      tester.view.physicalSize = size;
      await h.mount(Scaffold(body: child));
      await h.quiet();
    }

    Finder field(String label) => find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          (w.decoration?.labelText ??
                  (w.decoration?.label is Text
                      ? (w.decoration!.label! as Text).data
                      : null)) ==
              label,
    );
    Future<void> fill(String label, String value) async {
      await h.tap(field(label));
      await tester.enterText(field(label), value);
      await tester.pump();
    }

    Future<void> openForm(
      Future<Object?> Function(BuildContext) open,
      Size size,
    ) async {
      await mount(
        Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => open(context),
                child: const Text('Открыть'),
              ),
            ),
          ),
        ),
        size: size,
      );
      await h.tap(find.text('Открыть'));
      await h.quiet();
    }

    void expectFooter() {
      final actions = find.byKey(const ValueKey('magic-form-actions'));
      expect(actions, findsOneWidget);
      final rect = tester.getRect(actions);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(tester.view.physicalSize.height));
      expect(find.text('Отмена').hitTestable(), findsOneWidget);
    }

    await h.check(
      'STUDENT',
      'Основные поля, раскрытие, сохранность значений и закреплённые действия',
      () async {
        await openForm(
          (context) =>
              showStudentCreateSurface(context, initialBranchId: branchId),
          const Size(1000, 700),
        );
        expectFooter();
        await tester.enterText(
          find.byKey(const ValueKey('student-first-name')),
          'Черновик',
        );
        final toggle = find.byKey(const ValueKey('student-additional-toggle'));
        expect(toggle, findsOneWidget);
        final before = find.byType(TextFormField).evaluate().length;
        await h.tap(toggle);
        await tester.pumpAndSettle();
        expect(
          find.byType(TextFormField).evaluate().length,
          greaterThan(before),
        );
        final optional = find.byWidgetPredicate(
          (w) =>
              w is TextFormField && w.key.toString().contains('custom-field-'),
        );
        expect(optional, findsWidgets);
        final optionalKey = tester.widget(optional.first).key!;
        await h.tap(optional.first);
        await tester.enterText(optional.first, 'UI draft');
        await h.tap(toggle);
        await h.tap(toggle);
        await h.tap(find.byKey(optionalKey));
        expect(
          find.descendant(
            of: find.byKey(optionalKey),
            matching: find.text('UI draft'),
          ),
          findsOneWidget,
        );
        expectFooter();
        await captureEvidence(tester, 'ui-student-expanded');
        await h.tap(find.text('Отмена'));
        expect(find.text('Выйти без сохранения?'), findsOneWidget);
        await h.tap(find.text('Остаться'));
        expect(find.byKey(const ValueKey('student-submit')), findsOneWidget);
        await h.tap(find.byKey(const ValueKey('student-submit')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('student-last-name')).hitTestable(),
          findsOneWidget,
        );
      },
    );

    for (final entry in <String, Future<Object?> Function(BuildContext)>{
      'employee': showCreateEmployeeSurface,
      'teacher': showCreateTeacherSurface,
      'group': showCreateGroupSurface,
      'student': (context) =>
          showStudentCreateSurface(context, initialBranchId: branchId),
    }.entries) {
      await h.check(
        'SHORT-${entry.key}',
        'Действия формы ${entry.key} в окне 390×640',
        () async {
          await openForm(entry.value, const Size(390, 640));
          expectFooter();
          await tester.drag(
            find.byKey(const ValueKey('magic-form-fields')),
            const Offset(0, -600),
          );
          await tester.pumpAndSettle();
          expectFooter();
          await captureEvidence(tester, 'ui-short-${entry.key}');
        },
      );
    }

    await h.check(
      'STAFF',
      'Персонал А: черновик при переключении, сохранение и повторное чтение',
      () async {
        final staff = await crm.createStaff(
          firstName: 'UI-Audit',
          lastName: 'Сотрудник',
          branchIds: [branchId],
        );
        final id = staff['id'].toString();
        await mount(
          Scaffold(
            body: PersonnelWorkspace(
              snapshot: snapshot,
              initialLink: EntityLink.typed(
                entityType: EntityLinkType.user,
                entityId: id,
                variant: 'staff',
              ),
            ),
          ),
        );
        expect(find.text('Сотрудник UI-Audit'), findsWidgets);
        expect(
          find.byKey(const Key('staff-detail-save')).hitTestable(),
          findsOneWidget,
        );
        await fill('Имя *', 'UI-Changed');
        await h.tap(find.text('Преподаватели'));
        expect(find.text('Выйти без сохранения?'), findsOneWidget);
        await h.tap(find.text('Остаться'));
        expect(
          tester.widget<TextField>(field('Имя *')).controller!.text,
          'UI-Changed',
        );
        expect(find.text('Есть изменения'), findsOneWidget);
        tester.view.physicalSize = const Size(390, 800);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(field('Имя *')).controller!.text,
          'UI-Changed',
        );
        tester.view.physicalSize = const Size(1280, 800);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(field('Имя *')).controller!.text,
          'UI-Changed',
        );
        await h.tap(find.text('Отменить изменения'));
        await h.tap(find.text('Не сохранять'));
        await h.quiet();
        expect(
          tester.widget<TextField>(field('Имя *')).controller!.text,
          'UI-Audit',
        );
        expect((await crm.getStaff(id))['first_name'], 'UI-Audit');
        await fill('Имя *', 'UI-Changed');
        await h.tap(find.byKey(const Key('staff-detail-save')));
        await h.quiet();
        expect((await crm.getStaff(id))['first_name'], 'UI-Changed');
        await h.tap(find.byTooltip('Скрыть список персонала'));
        await tester.pump(const Duration(seconds: 5));
        await captureEvidence(tester, 'ui-staff-full-width');
        tester.view.physicalSize = const Size(390, 800);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('staff-detail-save')).hitTestable(),
          findsOneWidget,
        );
        await captureEvidence(tester, 'ui-staff-narrow');
        await h.tap(find.byTooltip('Закрыть карточку'));
        expect(find.text('Выйти без сохранения?'), findsNothing);
      },
    );

    await h.check(
      'TEACHER',
      'Единая карточка преподавателя сохраняет рабочие данные без изменения ставки',
      () async {
        final teacher = await crm.createTeacher(
          firstName: 'UI-Teacher',
          branchIds: [branchId],
          rate: 750,
        );
        final id = teacher['id'].toString();
        await mount(
          Scaffold(
            body: PersonnelWorkspace(
              snapshot: snapshot,
              initialLink: EntityLink.typed(
                entityType: EntityLinkType.teacher,
                variant: 'personnel_teacher',
                entityId: id,
              ),
            ),
          ),
        );
        await fill('Имя Фамилия', 'UI-Teacher Changed');
        await h.tap(find.byKey(const Key('teacher-detail-save')));
        await h.quiet();
        final saved = await crm.getTeacher(id);
        expect(
          '${saved['first_name']} ${saved['last_name']}',
          'UI-Teacher Changed',
        );
        expect(saved['current_rate'], 750);
        expect(
          find.byKey(const Key('teacher-rate-change-confirmation')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('teacher-open-availability')),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 5));
        await captureEvidence(tester, 'ui-teacher-card');
      },
    );

    await h.check(
      'FINANCE',
      'Поступления/расходы, таблица и мобильные карточки',
      () async {
        final studentId = (await crm.listStudents(
          limit: 1,
        )).single['id'].toString();
        await crm.createClientPaymentRecord(
          studentId,
          input: CreateClientPaymentRecordInput(
            amountMinor: BigInt.from(234567),
            status: ClientPaymentStatus.paid,
            reason: 'UI-INCOME',
            externalIdentifier: 'UI-RECEIPT',
            method: SubscriptionPaymentMethod.cash,
            branchId: branchId,
            occurredAt: DateTime.now(),
          ),
          identity: MagicMutationIdentity.create('audit.ui.payment'),
        );
        final expense = await crm.createExpense(
          amount: 12345.67,
          category: 'equipment',
          branchId: branchId,
          description:
              'UI-EXPENSE оборудование и длинное назначение без обрезки',
          identity: MagicMutationIdentity.create('audit.ui.expense'),
        );
        await mount(FinanceWidget(branchId: branchId));
        expect(find.text('Нет расходов за период'), findsNothing);
        expect(find.text('Клиент'), findsOneWidget);
        expect(find.text('Назначение'), findsOneWidget);
        expect(find.textContaining('345,67'), findsWidgets);
        await captureEvidence(tester, 'ui-finance-income');
        await h.tap(find.text('Экспорт'));
        expect(find.text('Экспорт CSV'), findsOneWidget);
        expect(find.text('Экспорт XLSX'), findsOneWidget);
        await tester.tapAt(const Offset(10, 10));
        await h.tap(find.text('Расходы'));
        expect(find.text('Дата'), findsOneWidget);
        expect(find.text('Категория'), findsOneWidget);
        expect(find.text('Назначение'), findsOneWidget);
        expect(
          find.byKey(ValueKey('expense-actions-${expense['id']}')),
          findsOneWidget,
        );
        await captureEvidence(tester, 'ui-finance-expenses');
        tester.view.physicalSize = const Size(390, 740);
        await tester.pumpAndSettle();
        expect(find.text('Назначение'), findsNothing);
        expect(
          find.byKey(ValueKey('expense-actions-${expense['id']}')),
          findsOneWidget,
        );
        await captureEvidence(tester, 'ui-finance-expenses-narrow');
        await h.tap(find.text('Поступления'));
        expect(
          find.byKey(ValueKey('expense-actions-${expense['id']}')),
          findsNothing,
        );
        await captureEvidence(tester, 'ui-finance');
      },
    );
    await h.check('TASKS', 'Фильтры задач доступны в узком окне', () async {
      await mount(const SharedTasksPanel(), size: const Size(390, 740));
      expect(
        find.byKey(const Key('shared-task-priority-filter')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('shared-task-calendar-toggle')).hitTestable(),
        findsOneWidget,
      );
      await captureEvidence(tester, 'ui-tasks-narrow');
    });
    await h.check(
      'BOARD',
      'Воронка показывает филиал и позволяет очистить пустой поиск',
      () async {
        await mount(const Scaffold(body: StudentsBoardWidget()));
        expect(find.textContaining('Филиал:'), findsWidgets);
        await tester.enterText(
          find.byKey(const ValueKey('students-search')),
          'UI-NO-MATCH-123456',
        );
        await tester.pump(const Duration(seconds: 1));
        await h.quiet();
        expect(find.text('Ученики не найдены'), findsOneWidget);
        await h.tap(find.widgetWithText(FilledButton, 'Очистить поиск'));
        await captureEvidence(tester, 'ui-students');
      },
    );
    await h.check(
      'CLIENT-CARD',
      'Геометрия реальной карточки ученика',
      () async {
        final students = await crm.listStudents(limit: 1);
        expect(students, isNotEmpty);
        await mount(
          Scaffold(
            body: ClientCard(
              lead: students.first,
              entityType: 'student',
              routed: true,
              capabilitySnapshot: snapshot,
            ),
          ),
          size: const Size(1440, 1000),
        );
        final heights = <double>[];
        for (final label in [
          'Тип обращения',
          'Основной филиал',
          'Цель обучения',
        ]) {
          final input = find.descendant(
            of: field(label),
            matching: find.byType(EditableText),
          );
          final container = InputDecorator.containerOf(
            tester.element(input.first),
          )!;
          heights.add(container.size.height);
        }
        expect(
          heights.every((height) => height >= 48),
          isTrue,
          reason: '$heights',
        );
        expect(
          heights.reduce((a, b) => a > b ? a : b) -
              heights.reduce((a, b) => a < b ? a : b),
          lessThanOrEqualTo(1),
        );
        await captureEvidence(tester, 'ui-client-card');
      },
    );
    for (final type in ['student', 'lead']) {
      await h.check(
        'BOOK-$type',
        'Быстрая запись: клиент, филиал и вид занятия',
        () async {
          Map<String, dynamic> client;
          if (type == 'student') {
            client = (await crm.listStudents(limit: 1)).single;
          } else {
            final forms = h.scope.read(clientFormsApiProvider);
            final source = (await forms.listSources()).first;
            final pipeline = await crm.getClientPipeline(
              clientType: 'lead',
              branchId: branchId,
            );
            client = await forms.createLead(
              identity: MagicMutationIdentity.create(
                'audit.fixture.ui-booking',
              ),
              firstName: 'UI-Lead',
              lastName: 'Booking',
              phone: '+79995554431',
              sourceId: source['id'] as String,
              branchId: branchId,
              status: pipeline.activeStages.first.key,
              customFields: [],
            );
          }
          await mount(
            Scaffold(
              body: ClientCard(
                lead: client,
                entityType: type,
                routed: true,
                capabilitySnapshot: snapshot,
              ),
            ),
            size: const Size(1440, 1000),
          );
          await h.tap(
            find.byKey(
              Key(
                type == 'student' ? 'client-book-lesson' : 'client-book-trial',
              ),
            ),
          );
          await h.quiet();
          final editor = tester.widget<CreateLessonDialog>(
            find.byType(CreateLessonDialog),
          );
          final view = tester.widget<LessonEditorView>(
            find.byType(LessonEditorView),
          );
          expect(editor.clientId, client['id']);
          expect(editor.initialIsTrial, type == 'lead');
          expect(view.model.draft.client?.id, client['id']);
          expect(view.model.draft.client?.type, type);
          expect(view.model.draft.branchId, branchId);
          expect(view.model.draft.isTrial, type == 'lead');
          expect(view.model.loadErrorMessage, isNull);
          expectFooter();
          await captureEvidence(tester, 'ui-book-$type');
          if (type == 'student') {
            tester.view.physicalSize = const Size(390, 640);
            await tester.pumpAndSettle();
            expectFooter();
            await tester.drag(
              find.byKey(const ValueKey('magic-form-fields')),
              const Offset(0, -500),
            );
            await tester.pumpAndSettle();
            expectFooter();
            await captureEvidence(tester, 'ui-book-student-narrow');
          }
          await h.tap(find.widgetWithText(TextButton, 'Отмена'));
          expect(find.byType(CreateLessonDialog), findsNothing);
        },
      );
    }
    await h.check(
      'SCHEDULE',
      'Подпись создания занятия доступна в рабочем окне',
      () async {
        await mount(ScheduleWidget(initialBranchId: branchId));
        expect(find.text('+ Занятие').hitTestable(), findsOneWidget);
        await captureEvidence(tester, 'ui-schedule');
      },
    );
    await h.check(
      'CONFLICTS',
      'Счётчик и фильтр относятся к выбранному дню и филиалу',
      () async {
        final date = DateTime.parse(
          h.fixture['conflictDate'] as String,
        ).toLocal();
        ContextViewState? saved;
        await mount(
          ScheduleWidget(
            initialBranchId: branchId,
            initialViewState: ContextViewState(
              date: date,
              filters: {'view': 'day', 'branchId': branchId},
            ),
            onViewStateChanged: (value) => saved = value,
          ),
        );
        final shortcut = find.byKey(
          const ValueKey('schedule-conflicts-shortcut'),
        );
        expect(find.text('Занятий с конфликтами: 1'), findsOneWidget);
        await h.tap(shortcut);
        expect(tester.widget<FilterChip>(shortcut).selected, isTrue);
        expect(saved?.filters['conflicts'], isTrue);
        expect(saved?.filters['branchId'], branchId);
        expect(saved?.date?.day, date.day);
        await captureEvidence(tester, 'ui-conflicts');
        await h.tap(shortcut);
        expect(tester.widget<FilterChip>(shortcut).selected, isFalse);
      },
    );
    await h.check(
      'MESSENGER',
      'Пустой поиск чатов объясняет контекст и очищается',
      () async {
        await mount(const MessengerScreen(role: 'director'));
        final search = find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.decoration?.hintText == 'Поиск по названию чата',
        );
        await tester.enterText(search, 'UI-NO-MATCH-123456');
        await tester.pumpAndSettle();
        expect(find.text('Чаты не найдены'), findsOneWidget);
        await h.tap(find.widgetWithText(FilledButton, 'Очистить поиск'));
        expect(tester.widget<TextField>(search).controller!.text, isEmpty);
        await captureEvidence(tester, 'ui-messenger');
      },
    );
    for (final channel in [false, true]) {
      await h.check(
        channel ? 'HISTORY-CHANNEL' : 'HISTORY-CHAT',
        'Поиск по всей истории и переход к старому сообщению',
        () async {
          final service = h.scope.read(magicMessengerServiceProvider);
          final id =
              h.fixture[channel ? 'historyChannelId' : 'historyChatId']
                  as String;
          Future<List<Map<String, dynamic>>> search({String? beforeId}) =>
              channel
              ? service.listChannelPosts(
                  id,
                  query: 'ЁЛКА %_',
                  limit: 50,
                  beforeId: beforeId,
                )
              : service.listMessages(
                  id,
                  query: 'ЁЛКА %_',
                  limit: 50,
                  beforeId: beforeId,
                );
          final first = await search();
          expect(first, hasLength(50));
          final second = await search(beforeId: first.first['id'].toString());
          expect(second, hasLength(5));
          expect({
            ...first.map((m) => m['id']),
            ...second.map((m) => m['id']),
          }, hasLength(55));
          final recent = channel
              ? await service.listChannelPosts(id)
              : await service.listMessages(id);
          expect(
            recent.any((m) => (m['content'] ?? '').toString().contains('ёлка')),
            isFalse,
          );
          await mount(
            const MessengerScreen(role: 'director'),
            size: const Size(1440, 1000),
          );
          await h.tap(
            find
                .textContaining(
                  channel ? 'UI-HISTORY-CHANNEL' : 'UI-HISTORY-CHAT',
                )
                .first,
          );
          await h.tap(find.byTooltip('Поиск').last);
          final searchField = find.descendant(
            of: find.byType(ChatHeader),
            matching: find.byType(TextField),
          );
          await tester.enterText(searchField, 'ЁЛКА %_');
          await tester.pump(const Duration(milliseconds: 400));
          await h.quiet();
          expect(find.text('1 / 50+'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('messenger-latest-messages')),
            findsOneWidget,
          );
          final targetId = first.last['id'];
          final bubble = find.byWidgetPredicate(
            (w) => w is MessageBubble && w.message['id'] == targetId,
          );
          await h.waitFor(
            () => find
                .descendant(
                  of: bubble,
                  matching: find.text(first.last['content'].toString()),
                )
                .hitTestable()
                .evaluate()
                .isNotEmpty,
            'Historical match is visible',
          );
          await captureEvidence(
            tester,
            channel ? 'ui-history-channel' : 'ui-history-chat',
          );
          await h.tap(find.byTooltip('Следующее совпадение'));
          await h.quiet();
          expect(find.text('2 / 50+'), findsOneWidget);
          if (!channel) {
            for (var index = 3; index <= 51; index++) {
              await h.tap(find.byTooltip('Следующее совпадение'));
              await h.waitFor(
                () => find
                    .text('$index / ${index <= 50 ? '50+' : '55'}')
                    .evaluate()
                    .isNotEmpty,
                'Search result $index opens',
              );
              await h.quiet();
            }
          }
          await h.tap(searchField);
          await tester.enterText(searchField, 'UI-NO-MATCH');
          await h.waitFor(
            () => find.text('0 совпадений').evaluate().isNotEmpty,
            'No matches is shown after the server response',
          );
          await h.tap(find.byTooltip('Закрыть поиск'));
          expect(
            find.byKey(const ValueKey('messenger-latest-messages')),
            findsNothing,
          );
        },
      );
    }
    await h.finish();
  });
}
