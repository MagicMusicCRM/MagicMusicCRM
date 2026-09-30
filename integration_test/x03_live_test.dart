import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store_contract.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/magic_realtime_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/recurring_schedule_plan_view.dart';

import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  testWidgets(
    'X-03: two staff UIs keep one current lesson',
    (tester) async {
      final h = LiveAuditHarness(tester, 'admin', 'x03');
      await h.initialize(size: const Size(1600, 1400), liveCrmRealtime: true);
      final a = h.scope.read(magicCrmServiceProvider);
      final aAccess = await h.scope.read(capabilitySnapshotProvider.future);
      final studentId = h.fixture['studentId'] as String;
      final sourceId = h.fixture['edgeLessonId'] as String;
      final sourceDate = DateTime.parse(
        h.fixture['edgeScheduledAt'] as String,
      ).toLocal();
      final student = await a.getStudent(studentId);
      final bApi = MagicApiClient(
        baseUrl: h.fixture['baseUrl'] as String,
        tokenStore: MemoryMagicTokenStore(),
      );
      addTearDown(() => bApi.rawDio.close(force: true));
      final manager = (h.fixture['accounts'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((account) => account['role'] == 'manager');
      final login = await bApi.post<Map<String, dynamic>>(
        '/auth/login',
        authenticated: false,
        data: {'email': manager['email'], 'password': h.fixture['password']},
      );
      await bApi.saveTokens(
        MagicApiTokens.fromJson(
          Map<String, dynamic>.from(login['session'] as Map),
        ),
      );
      final bRealtime = MagicRealtimeService(
        api: bApi,
        apiBaseUrl: h.fixture['baseUrl'] as String,
      );
      addTearDown(bRealtime.resetSession);
      final bScope = ProviderContainer(
        overrides: [
          magicApiClientProvider.overrideWithValue(bApi),
          magicRealtimeServiceProvider.overrideWithValue(bRealtime),
        ],
      );
      addTearDown(bScope.dispose);
      final tab = ValueNotifier(0);
      final calendarDate = ValueNotifier(sourceDate);
      addTearDown(tab.dispose);
      addTearDown(calendarDate.dispose);
      Finder key(String value) => find.byKey(ValueKey(value));
      Future<void> showA() async {
        tab.value = 0;
        await tester.pump();
        await h.quiet();
      }

      Future<void> showB(DateTime date) async {
        calendarDate.value = date;
        tab.value = 1;
        await tester.pump();
        await h.quiet();
      }

      StudentLessonTimelineView timeline() =>
          tester.widget<StudentLessonTimelineView>(
            find.byType(StudentLessonTimelineView),
          );
      Future<String?> scanForSuccessor(
        String predecessor,
        Set<String> old,
      ) async {
        await h.waitFor(
          () =>
              !timeline().loading &&
              !timeline().paging &&
              timeline().page.items.isNotEmpty,
          'A timeline refresh settled',
        );
        final seen = <String>{};
        String? successor;
        var pages = 0;
        while (true) {
          h.facts.add({
            'step': h.currentStep,
            'page': pages,
            'count': timeline().page.items.length,
            'hasNext': timeline().page.hasNext,
            'first': timeline().page.items.first.scheduledAt.toIso8601String(),
            'last': timeline().page.items.last.scheduledAt.toIso8601String(),
          });
          for (final item in timeline().page.items) {
            seen.add(item.id);
            if (item.reschedule.predecessorId == predecessor) {
              successor = item.id;
            }
          }
          if (!timeline().page.hasNext) break;
          expect(pages++, lessThan(12));
          await h.tap(key('student-lesson-timeline-next'));
          await h.quiet();
          await h.waitFor(
            () =>
                !timeline().loading &&
                !timeline().paging &&
                timeline().page.items.isNotEmpty,
            'A next page loaded',
          );
        }
        expect(seen.intersection(old), isEmpty);
        expect(
          seen.length,
          (h.fixture['lessonIds'] as List).length - (old.length == 3 ? 1 : 0),
        );
        while (timeline().page.hasPrevious) {
          expect(pages--, greaterThan(-12));
          await h.tap(key('student-lesson-timeline-previous'));
          await h.quiet();
        }
        return successor;
      }

      await h.check(
        'OPEN',
        'A открывает карточку с пограничным уроком; B входит отдельно',
        () async {
          await h.mount(
            ValueListenableBuilder<int>(
              valueListenable: tab,
              builder: (context, selected, child) => IndexedStack(
                index: selected,
                children: [
                  TickerMode(
                    enabled: selected == 0,
                    child: MaterialApp(
                      theme: AppTheme.light,
                      home: Scaffold(
                        body: ClientCard(
                          key: const ValueKey('x03-card'),
                          lead: student,
                          entityType: 'student',
                          routed: true,
                          capabilitySnapshot: aAccess,
                        ),
                      ),
                    ),
                  ),
                  UncontrolledProviderScope(
                    container: bScope,
                    child: TickerMode(
                      enabled: selected == 1,
                      child: ValueListenableBuilder<DateTime>(
                        valueListenable: calendarDate,
                        builder: (context, date, child) => MaterialApp(
                          theme: AppTheme.light,
                          home: Scaffold(
                            body: ScheduleWidget(
                              key: ValueKey(date.toIso8601String()),
                              initialBranchId: h.fixture['branchId'],
                              initialViewState: ContextViewState(
                                date: date,
                                filters: {
                                  'view': 'day',
                                  'branchId': h.fixture['branchId'],
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
          await h.waitFor(
            () => h.crmSocketConnects > 0,
            'A real CRM socket connected',
          );
          await h.waitFor(
            () =>
                find.byType(StudentLessonTimelineView).evaluate().isNotEmpty &&
                timeline().page.items.any((item) => item.id == sourceId),
            'Page edge lesson visible',
          );
          expect(timeline().page.items.length, 30);
          h.facts.add({
            'step': h.currentStep,
            'edgeLessonId': sourceId,
            'edgeDate': sourceDate.toIso8601String(),
            'socketConnects': h.crmSocketConnects,
          });
        },
      );
      final chain = <String>[sourceId];
      final readMeasures = <Map<String, Object>>[];
      Future<void> transferB(
        String current,
        DateTime currentDate,
        DateTime target,
        int hour, {
        bool expectSocket = true,
      }) async {
        await showB(currentDate);
        await h.tap(key('schedule-lesson-$current').first);
        await h.tap(find.text('Перенести'));
        await h.quiet();
        expect(find.byType(CreateLessonDialog), findsOneWidget);
        await h.tap(key('lesson-date-field'));
        await h.tap(
          find
              .descendant(
                of: find.byType(DatePickerDialog),
                matching: find.text('${target.day}'),
              )
              .last,
        );
        await h.tap(find.text('OK').last);
        await h.tap(key('lesson-time-field'));
        final timeDialog = find.byType(TimePickerDialog);
        final local = MaterialLocalizations.of(tester.element(timeDialog));
        await h.tap(find.byTooltip(local.inputTimeModeButtonLabel));
        final fields = find.descendant(
          of: timeDialog,
          matching: find.byType(TextField),
        );
        await tester.enterText(fields.at(0), '$hour');
        await tester.enterText(fields.at(1), '0');
        await h.tap(
          find.descendant(
            of: timeDialog,
            matching: find.text(local.okButtonLabel),
          ),
        );
        await h.tap(key('lesson-edit-reason'));
        await tester.enterText(
          key('lesson-edit-reason'),
          'Проверка двух карточек',
        );
        await h.tap(find.widgetWithText(FilledButton, 'Рассчитать'));
        await h.waitFor(
          () => key('lesson-decision-preview').evaluate().isNotEmpty,
          'B transfer preview loaded',
        );
        expect(key('lesson-decision-preview'), findsOneWidget);
        final socketBefore = h.crmSocketEvents;
        await h.tap(find.widgetWithText(FilledButton, 'Подтвердить изменения'));
        await h.waitFor(
          () => find.byType(CreateLessonDialog).evaluate().isEmpty,
          'B transfer committed and editor closed',
        );
        if (expectSocket) {
          await h.waitFor(
            () => h.crmSocketEvents > socketBefore,
            'Real lesson event reached A',
          );
        }
      }

      Future<void> move(int dayOffset, int hour) async {
        final current = chain.last;
        await transferB(
          current,
          sourceDate.add(Duration(days: dayOffset - 1)),
          sourceDate.add(Duration(days: dayOffset)),
          hour,
        );
        final requestBefore = h.requests.length;
        final watch = Stopwatch()..start();
        await showA();
        final successor = await scanForSuccessor(current, chain.toSet());
        watch.stop();
        readMeasures.add({
          'move': dayOffset,
          'aRequests': h.requests.length - requestBefore,
          'aReadElapsedMs': watch.elapsedMilliseconds,
        });
        expect(successor, isNotNull);
        chain.add(successor!);
      }

      await h.check(
        'TWO-MOVES',
        'B переносит урок дважды; A видит одного successor',
        () async {
          await move(1, 11);
          h.duplicateNextCrmEvent = true;
          await move(2, 12);
          expect(h.duplicatedCrmEvents, 1);
          h.facts.add({
            'step': h.currentStep,
            'chain': chain,
            'socketEvents': h.crmSocketEvents,
            'duplicatedEvents': h.duplicatedCrmEvents,
            'readMeasures': readMeasures,
          });
        },
      );
      await h.check(
        'CANCEL-CURRENT',
        'B отменяет текущий урок; A не видит цепочку',
        () async {
          final current = chain.last;
          await showB(sourceDate.add(const Duration(days: 2)));
          await h.tap(key('schedule-lesson-$current').first);
          await h.tap(find.text('Отменить занятие'));
          await h.quiet();
          await h.tap(key('lesson-decision-reason'));
          await tester.enterText(
            key('lesson-decision-reason'),
            'Проверка актуального урока',
          );
          await h.tap(key('lesson-decision-submit'));
          await h.waitFor(
            () => key('lesson-decision-preview').evaluate().isNotEmpty,
            'B cancellation preview loaded',
          );
          expect(key('lesson-decision-preview'), findsOneWidget);
          await h.tap(key('lesson-decision-submit'));
          await h.waitFor(
            () => key('lesson-decision-submit').evaluate().isEmpty,
            'B cancellation committed and editor closed',
          );
          await showA();
          await scanForSuccessor(current, chain.toSet());
          h.facts.add({'step': h.currentStep, 'chain': chain});
        },
      );
      final recoveryId = h.fixture['recoveryLessonId'] as String;
      final recoveryDate = DateTime.parse(
        h.fixture['recoveryScheduledAt'] as String,
      ).toLocal();
      String? recoverySuccessor;
      var failNextNoteSave = false;
      var failNextTimeline = false;
      h.api.rawDio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final noteSave =
                failNextNoteSave &&
                options.method == 'PUT' &&
                options.uri.path.endsWith('/internal-note');
            final timelineRead =
                failNextTimeline &&
                options.method == 'GET' &&
                options.uri.path.endsWith('/lesson-timeline');
            if (noteSave || timelineRead) {
              if (noteSave) failNextNoteSave = false;
              if (timelineRead) failNextTimeline = false;
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 503,
                    data: {'message': 'Временная ошибка чтения или записи'},
                  ),
                  type: DioExceptionType.badResponse,
                ),
              );
              return;
            }
            handler.next(options);
          },
        ),
      );
      await h.check(
        'MISSED-EVENT',
        'Отключённый socket A пропускает перенос B; reconnect сохраняет черновик',
        () async {
          const draft = 'Черновик X-03 после разрыва связи';
          failNextNoteSave = true;
          await tester.enterText(key('client-internal-note-input'), draft);
          await tester.pump();
          expect(
            tester
                .widget<TextField>(key('client-internal-note-input'))
                .controller!
                .text,
            draft,
          );
          final socketBefore = h.crmSocketEvents;
          h.crmSocketTransport!.disconnect();
          await transferB(
            recoveryId,
            recoveryDate,
            recoveryDate.add(const Duration(days: 1)),
            11,
            expectSocket: false,
          );
          expect(h.crmSocketEvents, socketBefore);
          final eventsWhileOffline = h.crmSocketEvents - socketBefore;
          expect(failNextNoteSave, isFalse);
          h.crmSocketTransport!.connect();
          await h.waitFor(
            () => h.crmSocketConnects > 1,
            'A real CRM socket reconnected',
          );
          final requestBefore = h.requests.length;
          final watch = Stopwatch()..start();
          await showA();
          expect(
            tester
                .widget<TextField>(key('client-internal-note-input'))
                .controller!
                .text,
            draft,
          );
          await h.tap(key('client-internal-note-retry'));
          await h.waitFor(
            () => timeline().page.items.any(
              (item) => item.reschedule.predecessorId == recoveryId,
            ),
            'A recovered missed transfer after resume',
          );
          watch.stop();
          recoverySuccessor = timeline().page.items
              .singleWhere(
                (item) => item.reschedule.predecessorId == recoveryId,
              )
              .id;
          expect(
            timeline().page.items.any((item) => item.id == recoveryId),
            isFalse,
          );
          expect(
            tester
                .widget<TextField>(key('client-internal-note-input'))
                .controller!
                .text,
            draft,
          );
          expect(
            h.requests.any(
              (request) =>
                  request['step'] == h.currentStep &&
                  request['method'] == 'PUT' &&
                  request['status'] == 200 &&
                  (request['path'] as String).endsWith('/internal-note'),
            ),
            isTrue,
          );
          h.facts.add({
            'step': h.currentStep,
            'sourceId': recoveryId,
            'successorId': recoverySuccessor,
            'socketEventsWhileOffline': eventsWhileOffline,
            'socketConnects': h.crmSocketConnects,
            'refreshRequests': h.requests.length - requestBefore,
            'refreshElapsedMs': watch.elapsedMilliseconds,
            'draftPreserved': true,
            'noteSaveFailureInjectedAtClientTransport': true,
          });
        },
      );
      await h.check(
        'ERROR-RETRY',
        'Ошибка чтения видна; повтор восстанавливает актуальный урок',
        () async {
          final current = recoverySuccessor!;
          await transferB(
            current,
            recoveryDate.add(const Duration(days: 1)),
            recoveryDate.add(const Duration(days: 2)),
            12,
          );
          failNextTimeline = true;
          await showA();
          await h.waitFor(
            () => timeline().error != null,
            'A shows the failed timeline refresh',
          );
          expect(
            find.descendant(
              of: key('student-lesson-timeline'),
              matching: find.textContaining(
                'Временная ошибка чтения или записи',
              ),
            ),
            findsOneWidget,
          );
          await h.tap(
            find.descendant(
              of: key('student-lesson-timeline'),
              matching: find.text('Повторить'),
            ),
          );
          await h.waitFor(
            () =>
                timeline().error == null &&
                timeline().page.items.any(
                  (item) => item.reschedule.predecessorId == current,
                ),
            'A retry loaded current successor',
          );
          expect(
            timeline().page.items.any((item) => item.id == current),
            isFalse,
          );
          expect(failNextTimeline, isFalse);
          h.facts.add({
            'step': h.currentStep,
            'failedReadStatus': 503,
            'failureInjectedAtClientTransport': true,
            'sourceId': current,
            'successorId': timeline().page.items
                .singleWhere((item) => item.reschedule.predecessorId == current)
                .id,
          });
        },
      );
      final conflictId = h.fixture['conflictLessonId'] as String;
      final conflictDate = DateTime.parse(
        h.fixture['conflictScheduledAt'] as String,
      ).toLocal();
      await h.check(
        'CONCURRENT-VERSION',
        'Два открытых UI редактора: устаревший commit A получает конфликт',
        () async {
          await h.tap(key('student-timeline-$conflictId'));
          await h.quiet();
          await h.waitFor(
            () => find.byType(CreateLessonDialog).evaluate().isNotEmpty,
            'A editor opened for concurrent lesson',
          );
          expect(find.byType(CreateLessonDialog), findsOneWidget);
          final aTarget = conflictDate.add(const Duration(days: 1));
          await h.tap(key('lesson-date-field'));
          await h.tap(
            find
                .descendant(
                  of: find.byType(DatePickerDialog),
                  matching: find.text('${aTarget.day}'),
                )
                .last,
          );
          await h.tap(find.text('OK').last);
          await h.tap(key('lesson-time-field'));
          final timeDialog = find.byType(TimePickerDialog);
          final local = MaterialLocalizations.of(tester.element(timeDialog));
          await h.tap(find.byTooltip(local.inputTimeModeButtonLabel));
          final fields = find.descendant(
            of: timeDialog,
            matching: find.byType(TextField),
          );
          await tester.enterText(fields.at(0), '13');
          await tester.enterText(fields.at(1), '0');
          await h.tap(
            find.descendant(
              of: timeDialog,
              matching: find.text(local.okButtonLabel),
            ),
          );
          await h.tap(key('lesson-edit-reason'));
          await tester.enterText(
            key('lesson-edit-reason'),
            'Конкурентный перенос X-03',
          );
          await h.tap(find.widgetWithText(FilledButton, 'Рассчитать'));
          await h.waitFor(
            () => key('lesson-decision-preview').evaluate().isNotEmpty,
            'A stale candidate preview loaded',
          );
          await transferB(
            conflictId,
            conflictDate,
            conflictDate.add(const Duration(days: 2)),
            14,
          );
          await showA();
          await h.tap(
            find.widgetWithText(FilledButton, 'Подтвердить изменения'),
          );
          await h.waitFor(
            () => key('lesson-form-validation-error').evaluate().isNotEmpty,
            'A stale commit shows a conflict',
          );
          expect(
            find.textContaining('Это занятие уже перенесено'),
            findsOneWidget,
          );
          expect(find.text('Конкурентный перенос X-03'), findsOneWidget);
          expect(
            h.requests.any(
              (request) =>
                  request['step'] == h.currentStep && request['status'] == 409,
            ),
            isTrue,
          );
          h.facts.add({
            'step': h.currentStep,
            'staleLessonId': conflictId,
            'rejectedStatus': 409,
          });
        },
        expectedHttpErrors: [
          (
            method: 'POST',
            path: '/api/crm/lessons/$conflictId/reschedule',
            status: 409,
            maxCount: 1,
          ),
        ],
      );
      await h.finish();
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
