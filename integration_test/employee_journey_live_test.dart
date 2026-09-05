import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store_contract.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/utils/money_format.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/client_create_dialogs.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision_flow.dart';

import 'evidence_screenshot.dart';

// Product widgets/providers and authenticated HTTP. Fault injection drops a
// successful response after commit; it never manufactures a server result.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'employee journey persists once across failures and conflicts',
    (tester) async {
      final raw = Platform.environment['HTTP_JOURNEY_FIXTURE'];
      expect(
        raw,
        isNotNull,
        reason: 'Run scripts/http-journey-check.cjs --release-journeys',
      );
      final fixture = jsonDecode(raw!) as Map<String, dynamic>;
      final uri = Uri.parse(fixture['baseUrl'] as String);
      expect(uri.scheme, 'http');
      expect(uri.host, '127.0.0.1');
      await initializeDateFormatting('ru');
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = MagicApiClient(
        baseUrl: uri.toString(),
        tokenStore: MemoryMagicTokenStore(),
      );
      addTearDown(() => api.rawDio.close(force: true));
      final login = await api.post<Map<String, dynamic>>(
        '/auth/login',
        authenticated: false,
        data: {'email': fixture['email'], 'password': fixture['password']},
      );
      await api.saveTokens(
        MagicApiTokens.fromJson(
          Map<String, dynamic>.from(login['session'] as Map),
        ),
      );
      final scope = ProviderContainer(
        overrides: [
          magicApiClientProvider.overrideWithValue(api),
          // Model an employee session whose push connection is unavailable.
          // Reloads and commands still use the real HTTP API.
          crmRealtimeProvider.overrideWith(
            (ref) => const Stream<CrmChangedEvent>.empty(),
          ),
        ],
      );
      addTearDown(scope.dispose);
      final access = await scope.read(capabilitySnapshotProvider.future);
      expect(access.role, 'director');
      final crm = scope.read(magicCrmServiceProvider);
      final responses = <Response<dynamic>>[];
      final paymentKeys = <String>[];
      var losePaymentResponse = false;
      api.rawDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.method == 'POST' &&
                options.path.endsWith('/payment-records')) {
              paymentKeys.add(options.headers['Idempotency-Key'].toString());
            }
            handler.next(options);
          },
          onResponse: (response, handler) {
            responses.add(response);
            if (losePaymentResponse &&
                response.requestOptions.method == 'POST' &&
                response.requestOptions.path.endsWith('/payment-records')) {
              losePaymentResponse = false;
              handler.reject(
                DioException(
                  requestOptions: response.requestOptions,
                  type: DioExceptionType.connectionError,
                  message: 'Synthetic response loss after commit',
                ),
              );
            } else {
              handler.next(response);
            }
          },
        ),
      );
      final completed = <String>[];
      Future<void> waitFor(bool Function() ready, String description) async {
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (!ready() && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        if (!ready()) {
          await captureEvidence(tester, 'employee-failure');
          debugPrint('Checkpoint failed: $description');
        }
        expect(ready(), isTrue, reason: description);
        expect(tester.takeException(), isNull);
      }

      Future<void> tap(Finder finder) async {
        await waitFor(
          () => finder.evaluate().isNotEmpty,
          'Missing control: $finder',
        );
        if (finder.hitTestable().evaluate().isEmpty) {
          await tester.ensureVisible(finder);
          await tester.pump(const Duration(milliseconds: 300));
        }
        await waitFor(
          () => finder.hitTestable().evaluate().isNotEmpty,
          'Control must be interactive: $finder',
        );
        await tester.tap(finder.hitTestable());
        await tester.pump(const Duration(milliseconds: 500));
      }

      Future<void> show(Widget Function(BuildContext) builder) async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: scope,
            child: RepaintBoundary(
              key: evidenceRootKey,
              child: MaterialApp(
                theme: AppTheme.light,
                home: Scaffold(body: Builder(builder: builder)),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
      }

      Future<void> card(String id, {String section = 'payments'}) async {
        final saved = await crm.getStudent(id);
        await show(
          (context) => ClientCard(
            key: UniqueKey(),
            lead: saved,
            entityType: 'student',
            routed: true,
            initialSection: section,
            capabilitySnapshot: access,
          ),
        );
        await waitFor(
          () =>
              find
                  .byKey(const Key('open-payment-form'))
                  .evaluate()
                  .isNotEmpty ||
              (section == 'overview' &&
                  find
                      .widgetWithText(TextFormField, 'Имя')
                      .evaluate()
                      .isNotEmpty) ||
              (section == 'lessons' &&
                  find
                      .byKey(const Key('student-lesson-timeline'))
                      .evaluate()
                      .isNotEmpty),
          'Student card loaded from HTTP',
        );
        await tester.pump(const Duration(seconds: 1));
        final jump = find.byKey(Key('client-section-jump-$section'));
        if (jump.evaluate().isNotEmpty) {
          await tap(jump);
          await tester.pump(const Duration(milliseconds: 500));
        }
      }

      Future<void> balance(String id, int expected) async {
        final projection = await crm.getStudentCommerceProjection(id);
        expect(
          projection.student.accounts.single.balanceMinor,
          BigInt.from(expected),
        );
        await card(id);
        await waitFor(
          () => find
              .descendant(
                of: find.byKey(const Key('client-payments-tab')),
                matching: find.text(formatPaymentMinor(BigInt.from(expected))),
              )
              .hitTestable()
              .evaluate()
              .isNotEmpty,
          'Reopened UI must show the persisted balance $expected',
        );
      }

      Future<void> evidence(String name) async {
        await captureEvidence(tester, 'employee-$name');
        completed.add(name);
      }

      Future<void> visibleLesson(
        String studentId,
        String lessonId,
        String label,
      ) async {
        await card(studentId, section: 'lessons');
        final row = find.byKey(Key('student-timeline-$lessonId'));
        await waitFor(
          () => row.evaluate().isNotEmpty,
          'Saved lesson appears in the timeline',
        );
        await tester.ensureVisible(row);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(row));
        await tester.pump(const Duration(seconds: 1));
        expect(find.textContaining(label), findsWidgets);
        await mouse.removePointer();
        await tester.pumpAndSettle();
      }

      Map<String, dynamic>? student;
      await show(
        (context) => FilledButton(
          onPressed: () async {
            student = await showDialog<Map<String, dynamic>>(
              context: context,
              builder: (_) => StudentCreateDialog(
                initialBranchId: fixture['branchId'] as String,
              ),
            );
          },
          child: const Text('Создать ученика'),
        ),
      );
      await tap(find.text('Создать ученика'));
      await waitFor(
        () => find.byKey(const Key('student-first-name')).evaluate().isNotEmpty,
        'Student form metadata',
      );
      await tester.enterText(
        find.byKey(const Key('student-first-name')),
        'Сценарий',
      );
      await tester.enterText(
        find.byKey(const Key('student-last-name')),
        'Выпуска',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('student-phone')),
          matching: find.byType(TextField),
        ),
        '9995554433',
      );
      await tap(find.byKey(const Key('student-source')));
      await tap(find.text('Сайт').last);
      await tap(find.byKey(const Key('student-submit')));
      await waitFor(() => student != null, 'Student saved through form');
      final id = student!['id'] as String;
      expect((await crm.getStudent(id))['first_name'], 'Сценарий');
      await card(id);
      await evidence('student-created');

      await tap(find.byKey(const Key('open-payment-form')));
      await tester.enterText(find.byKey(const Key('payment-amount')), '5000');
      await tap(find.byKey(const Key('payment-status')));
      await tap(find.text('Оплачен').last);
      await tester.enterText(
        find.byKey(const Key('payment-invoice')),
        'RELEASE-UI-RECEIPT',
      );
      losePaymentResponse = true;
      final submit = find.byKey(const Key('payment-submit'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.tap(submit);
      await waitFor(
        () => find.byKey(const Key('payment-error')).evaluate().isNotEmpty,
        'Lost response is visible',
      );
      expect(
        paymentKeys,
        hasLength(1),
        reason: 'Double tap must be guarded while pending',
      );
      expect(find.text('5000'), findsOneWidget);
      expect(
        find.textContaining('Действие могло сохраниться.'),
        findsOneWidget,
      );
      await evidence('network-loss-draft-preserved');
      await tap(submit);
      await waitFor(
        () => find.byKey(const Key('payment-submit')).evaluate().isEmpty,
        'Explicit retry completes',
      );
      expect(paymentKeys, hasLength(2));
      expect(paymentKeys.first, isNot('null'));
      expect(paymentKeys.toSet(), hasLength(1));
      await balance(id, 500000);
      final paymentId = (await crm.getStudentCommerceProjection(
        id,
      )).student.movements.firstWhere((item) => item.status == 'paid').id;
      await evidence('payment-retried-once');

      Future<String> createLesson(DateTime scheduled) async {
        final before = responses.length;
        await show(
          (context) => FilledButton(
            onPressed: () => CreateLessonDialog.show(
              context,
              initialDate: scheduled.toLocal(),
              clientType: 'student',
              clientId: id,
              clientName: 'Сценарий Выпуска',
              initialBranchId: fixture['branchId'] as String,
              initialRoomId: fixture['roomId'] as String,
            ),
            child: const Text('Записать'),
          ),
        );
        await tap(find.text('Записать'));
        final teacher = find.byKey(const Key('lesson-teacher-field'));
        await tap(teacher);
        await tester.enterText(
          find.descendant(of: teacher, matching: find.byType(TextField)),
          'Teacher0',
        );
        await tap(
          find
              .widgetWithText(MenuItemButton, 'Teacher0 HTTP test')
              .hitTestable(),
        );
        await tap(find.byKey(ValueKey('lesson-client-charge-type-$id')));
        await tap(find.text('С личного счёта').last);
        final price = find.byKey(ValueKey('lesson-client-price-$id'));
        await tester.ensureVisible(price);
        await tester.enterText(price, '1500');
        await tap(find.text('Создать'));
        await waitFor(
          () => responses
              .skip(before)
              .any(
                (r) =>
                    r.requestOptions.method == 'POST' &&
                    r.requestOptions.uri.path == '/api/crm/lessons',
              ),
          'Lesson committed through UI',
        );
        final result =
            responses
                    .skip(before)
                    .firstWhere(
                      (r) =>
                          r.requestOptions.method == 'POST' &&
                          r.requestOptions.uri.path == '/api/crm/lessons',
                    )
                    .data
                as Map;
        return result['id'] as String;
      }

      Future<Map<String, dynamic>> lesson(String lessonId) async =>
          (await crm.listLessons(lessonId: lessonId, limit: 1)).single;
      Future<void> decision(
        String lessonId,
        LessonDecisionOperation operation,
      ) async {
        final saved = await lesson(lessonId);
        bool? done;
        await show(
          (context) => FilledButton(
            onPressed: () async {
              done = await showLessonDecisionFlow(
                context,
                crm: crm,
                operation: operation,
                lesson: saved,
                canManageTeacherCompensation: true,
              );
            },
            child: Text(operation.title),
          ),
        );
        await tap(find.text(operation.title));
        final reason = find.byKey(const Key('lesson-decision-reason'));
        await waitFor(() => reason.evaluate().isNotEmpty, 'Decision loaded');
        await tester.enterText(reason, 'Проверка выпуска');
        await tap(find.byKey(const Key('lesson-decision-submit')));
        await waitFor(
          () => find
              .byKey(const Key('lesson-decision-preview'))
              .evaluate()
              .isNotEmpty,
          'Signed preview displayed',
        );
        await tap(find.byKey(const Key('lesson-decision-submit')));
        await waitFor(() => done == true, 'Decision committed');
      }

      final scheduled = DateTime.parse(fixture['scheduledAt'] as String);
      final completedLesson = await createLesson(
        scheduled.subtract(const Duration(days: 3)),
      );
      await evidence('lesson-booked');
      // Completion follows the product rule: the durable worker settles due lessons.
      for (var attempt = 0; attempt < 100; attempt++) {
        if ((await lesson(completedLesson))['status'] == 'completed') break;
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect((await lesson(completedLesson))['status'], 'completed');
      await balance(id, 350000);
      await visibleLesson(id, completedLesson, 'Завершено');
      await evidence('lesson-completed');
      final cancelledLesson = await createLesson(
        scheduled.add(const Duration(days: 2)),
      );
      await decision(cancelledLesson, LessonDecisionOperation.cancel);
      expect((await lesson(cancelledLesson))['status'], 'cancelled');
      await balance(id, 350000);
      await visibleLesson(id, cancelledLesson, 'Отменено');
      await evidence('lesson-cancelled');

      await card(id);
      await tap(find.text('Поступления и списания'));
      await tap(find.byKey(Key('adjust-payment-$paymentId')));
      await tester.enterText(
        find.byKey(const Key('adjustment-amount')),
        '3500',
      );
      await tester.enterText(
        find.byKey(const Key('adjustment-reason')),
        'Возврат остатка по заявлению',
      );
      await tap(find.byKey(const Key('adjustment-submit')));
      await waitFor(
        () => find.byKey(const Key('adjustment-submit')).evaluate().isEmpty,
        'Refund committed',
      );
      await balance(id, 0);
      await evidence('refund-balanced');

      // Independent mounted product cards retain separate versions.
      final stale = await crm.getStudent(id);
      await show(
        (context) => Row(
          children: [
            for (final key in ['editor-a', 'editor-b'])
              Expanded(
                child: ClientCard(
                  key: Key(key),
                  lead: stale,
                  entityType: 'student',
                  routed: true,
                  initialSection: 'overview',
                  capabilitySnapshot: access,
                ),
              ),
          ],
        ),
      );
      Finder editor(String key) => find.descendant(
        of: find.byKey(Key(key)),
        matching: find.widgetWithText(TextFormField, 'Имя'),
      );
      await waitFor(
        () =>
            editor('editor-a').evaluate().isNotEmpty &&
            editor('editor-b').evaluate().isNotEmpty,
        'Both editors loaded',
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.enterText(editor('editor-a'), 'Первый');
      await tester.pump(const Duration(seconds: 2));
      expect((await crm.getStudent(id))['first_name'], 'Первый');
      await tester.enterText(editor('editor-b'), 'Второй');
      await waitFor(
        () => find
            .byKey(const Key('client-autosave-retry'))
            .evaluate()
            .isNotEmpty,
        'Stale editor exposes conflict',
      );
      expect(
        (await crm.getStudent(id))['first_name'],
        'Первый',
        reason: 'No silent overwrite',
      );
      expect(
        find.text('Второй'),
        findsWidgets,
        reason: 'Conflicting draft remains available',
      );
      await evidence('concurrent-edit-conflict');
      await card(id, section: 'overview');
      expect(find.text('Первый'), findsWidgets);
      await evidence('reopened-saved-state');
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
      final result = {
        'studentId': id,
        'paymentId': paymentId,
        'completedLessonId': completedLesson,
        'cancelledLessonId': cancelledLesson,
        'scenarios': completed,
        'paymentAttempts': paymentKeys.length,
        'balanceMinor': '0',
      };
      await File(
        '${Platform.environment['EVIDENCE_SCREENSHOT_DIR']}/employee-result.json',
      ).writeAsString(jsonEncode(result));
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
