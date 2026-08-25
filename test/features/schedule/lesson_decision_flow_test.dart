import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision_flow.dart';

const _lessonId = '10000000-0000-4000-8000-000000000001';
const _branchId = '20000000-0000-4000-8000-000000000001';
const _replacementBranchId = '20000000-0000-4000-8000-000000000002';
const _groupLessonId = '30000000-0000-4000-8000-000000000001';
const _firstGroupStudentId = '40000000-0000-4000-8000-000000000001';
const _secondGroupStudentId = '50000000-0000-4000-8000-000000000001';

const _lesson = <String, dynamic>{
  'id': _lessonId,
  'version': 4,
  'branch_id': _branchId,
  'scheduled_at': '2026-08-07T09:00:00.000Z',
};

const _completedLesson = <String, dynamic>{
  ..._lesson,
  'lifecycle_state': 'successfully_completed',
};

const _successor = <String, dynamic>{
  'scheduledAt': '2026-08-08T10:00:00.000Z',
  'durationMinutes': 60,
};

class _LessonDecisionApi extends MagicApiClient {
  _LessonDecisionApi({
    this.conflict = false,
    this.failFirstCommit = false,
    this.staleVersionFirstCommit = false,
    this.completed = false,
    this.catalogBranchId = _branchId,
    this.operationKey = 'reschedule',
  }) : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final bool conflict;
  final bool failFirstCommit;
  final bool staleVersionFirstCommit;
  final bool completed;
  final String catalogBranchId;
  final String operationKey;
  final previews = <Map<String, dynamic>>[];
  final commits = <Map<String, dynamic>>[];
  final identities = <MagicMutationIdentity>[];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    expect(path, '/crm/configuration/lesson-decisions');
    expect(queryParameters?['branchId'], catalogBranchId);
    return <String, dynamic>{
          'settlementTypes': const [
            {
              'stableKey': 'lesson',
              'label': 'Занятие',
              'colorToken': 'success',
              'allowedContexts': ['settle'],
              'active': true,
              'order': 0,
            },
            {
              'stableKey': 'free_lesson',
              'label': 'Бесплатное занятие',
              'colorToken': 'warning',
              'allowedContexts': ['cancel', 'reschedule'],
              'active': true,
              'order': 1,
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
            {
              'stableKey': 'percent',
              'label': 'Процент ставки',
              'mode': 'percent',
              'value': '6250',
              'active': true,
              'order': 2,
            },
            {
              'stableKey': 'fixed',
              'label': 'Фиксированная сумма',
              'mode': 'fixed',
              'value': '150000',
              'active': true,
              'order': 3,
            },
            {
              'stableKey': 'hourly',
              'label': 'Почасовая сумма',
              'mode': 'hourly',
              'value': '120000',
              'active': true,
              'order': 4,
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
    expect(path, '/crm/lessons/$_lessonId/$operationKey/preview');
    previews.add(Map<String, dynamic>.from(data as Map));
    return <String, dynamic>{
          'operation': operationKey,
          'source': {
            'id': _lessonId,
            'version': previews.last['expectedVersion'],
            'state': completed ? 'successfully_completed' : 'scheduled',
          },
          'successor': _successor,
          'financialDecision': previews.last['financialDecision'],
          'violations': conflict
              ? const [
                  {
                    'code': 'TEACHER_OVERLAP',
                    'resource': {'type': 'teacher', 'id': 'teacher-1'},
                  },
                  {
                    'code': 'ROOM_OVERLAP',
                    'resource': {'type': 'room', 'id': 'room-1'},
                  },
                  {
                    'code': 'TEACHER_BRANCH_MISMATCH',
                    'resource': {'type': 'teacher', 'id': 'teacher-1'},
                  },
                  {
                    'code': 'ROOM_BRANCH_MISMATCH',
                    'resource': {'type': 'room', 'id': 'room-1'},
                  },
                ]
              : const [],
          'canConfirm': !conflict,
          'confirmRequired': true,
          if (!conflict) ...{
            'financialPreview': {
              'clientFacts': const [
                {
                  'settlementTypeKey': 'free_lesson',
                  'settlementLabel': 'Бесплатное занятие',
                  'amountMinor': '0',
                  'units': '0.00',
                },
              ],
              'teacherFact': completed
                  ? const {
                      'compensationRuleKey': 'none',
                      'compensationRuleLabel': 'Не оплачивать',
                      'amountMinor': '0',
                    }
                  : const {
                      'compensationRuleKey': 'fixed',
                      'compensationRuleLabel': 'Фиксированная сумма',
                      'amountMinor': '125000',
                    },
            },
            'warnings': [
              completed
                  ? 'COMPLETED_LESSON_EFFECTS_WILL_BE_REVERSED'
                  : 'SUCCESSOR_MAY_CHARGE_AGAIN',
            ],
            'previewToken': 'signed-preview',
          },
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
    expect(path, '/crm/lessons/$_lessonId/$operationKey');
    identities.add(identity);
    commits.add(Map<String, dynamic>.from(data as Map));
    if (staleVersionFirstCommit && commits.length == 1) {
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
    if (failFirstCommit && commits.length == 1) {
      throw const MagicApiException(statusCode: 409, message: 'Preview stale');
    }
    return <String, dynamic>{'transitionId': 'transition-1'} as T;
  }
}

class _GroupLessonDecisionApi extends MagicApiClient {
  _GroupLessonDecisionApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final previews = <Map<String, dynamic>>[];
  final commits = <Map<String, dynamic>>[];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    expect(path, '/crm/configuration/lesson-decisions');
    expect(queryParameters?['branchId'], _branchId);
    return <String, dynamic>{
          'settlementTypes': const [
            {
              'stableKey': 'lesson',
              'label': 'Занятие',
              'colorToken': 'success',
              'allowedContexts': ['settle'],
              'active': true,
              'order': 0,
            },
            {
              'stableKey': 'partially_paid_lesson',
              'label': 'Частично оплачено',
              'colorToken': 'warning',
              'allowedContexts': ['settle'],
              'active': true,
              'order': 1,
            },
          ],
          'teacherCompensationRules': const [
            {
              'stableKey': 'standard',
              'label': 'Полная стандартная ставка',
              'mode': 'standard',
              'value': '0',
              'active': true,
              'order': 0,
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
    expect(path, '/crm/lessons/$_groupLessonId/planned-settlement/preview');
    previews.add(Map<String, dynamic>.from(data as Map));
    return <String, dynamic>{
          'canConfirm': true,
          'financialPreview': {
            'clientFacts': const [
              {
                'clientId': _firstGroupStudentId,
                'settlementTypeKey': 'lesson',
                'settlementLabel': 'Занятие',
                'amountMinor': '80000',
                'units': '1.00',
              },
              {
                'clientId': _secondGroupStudentId,
                'settlementTypeKey': 'partially_paid_lesson',
                'settlementLabel': 'Частично оплачено',
                'amountMinor': '40000',
                'units': '0.50',
              },
            ],
            'teacherFact': const {
              'compensationRuleKey': 'standard',
              'compensationRuleLabel': 'Полная стандартная ставка',
              'amountMinor': '90000',
            },
          },
          'previewToken': 'group-signed-preview',
        }
        as T;
  }

  @override
  Future<T> request<T>(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
    dynamic responseType,
    MagicMutationIdentity? mutationIdentity,
  }) async {
    expect(method, 'PUT');
    expect(path, '/crm/lessons/$_groupLessonId/planned-settlement');
    expect(mutationIdentity, isNotNull);
    commits.add(Map<String, dynamic>.from(data as Map));
    return <String, dynamic>{'lessonId': _groupLessonId, 'version': 5} as T;
  }
}

Widget _host(
  _LessonDecisionApi api, {
  Map<String, dynamic> lesson = _lesson,
  Map<String, dynamic> successor = _successor,
  LessonDecisionOperation operation = LessonDecisionOperation.reschedule,
}) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => FilledButton(
        onPressed: () => showLessonDecisionFlow(
          context,
          crm: MagicCrmService(api),
          operation: operation,
          lesson: lesson,
          successor: successor,
        ),
        child: const Text('Открыть'),
      ),
    ),
  ),
);

Future<void> _openAndFill(
  WidgetTester tester,
  _LessonDecisionApi api, {
  Map<String, dynamic> lesson = _lesson,
  LessonDecisionOperation operation = LessonDecisionOperation.reschedule,
}) async {
  tester.view.physicalSize = const Size(1400, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(api, lesson: lesson, operation: operation));
  await tester.tap(find.text('Открыть'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('lesson-decision-reason')),
    'Клиент попросил перенести занятие',
  );
  await tester.tap(find.byKey(const Key('lesson-decision-settlement')));
  await tester.pumpAndSettle();
  expect(find.text('Занятие'), findsNothing);
  await tester.tap(find.text('Бесплатное занятие').last);
  await tester.pumpAndSettle();
  await tester.ensureVisible(
    find.byKey(const Key('lesson-decision-compensation')),
  );
  await tester.pump();
  await tester.tap(find.byKey(const Key('lesson-decision-compensation')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Фиксированная сумма').last);
  await tester.pumpAndSettle();
  await tester.ensureVisible(
    find.byKey(const Key('lesson-decision-compensation-value')),
  );
  await tester.pump();
  await tester.enterText(
    find.byKey(const Key('lesson-decision-compensation-value')),
    '1250',
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  test('keeps one mutation identity between preview and commit', () async {
    final api = _LessonDecisionApi();
    final controller = LessonDecisionController(
      crm: MagicCrmService(api),
      operation: LessonDecisionOperation.reschedule,
      lesson: _lesson,
      successor: _successor,
    );

    final preview = await controller.preview(
      reason: 'Перенос',
      settlementTypeKey: 'standard',
      compensationRuleKey: 'standard',
    );
    await controller.commit(preview);

    expect(api.identities, hasLength(1));
    expect(api.commits.single['previewToken'], 'signed-preview');
  });

  test(
    'clears preview identity and adopts current version after stale commit',
    () {
      final controller = LessonDecisionController(
        crm: MagicCrmService(_LessonDecisionApi()),
        operation: LessonDecisionOperation.reschedule,
        lesson: _lesson,
        successor: _successor,
      );

      final recovered = controller.recoverStaleCommit(
        const MagicApiException(
          statusCode: 409,
          message: 'stale',
          details: {'code': 'STALE_LESSON_VERSION', 'currentVersion': 7},
        ),
      );

      expect(recovered?.message, contains('Версия обновлена'));
      expect(
        () => controller.commit(
          const LessonDecisionPreview({
            'canConfirm': true,
            'previewToken': 'old',
          }),
        ),
        throwsStateError,
      );
    },
  );

  testWidgets('preview precedes commit and retry keeps input and identity', (
    tester,
  ) async {
    final api = _LessonDecisionApi(failFirstCommit: true);
    await _openAndFill(tester, api);

    await tester.ensureVisible(find.byKey(const Key('lesson-decision-submit')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('lesson-decision-submit')));
    await tester.pumpAndSettle();
    expect(api.previews, hasLength(1));
    expect(api.commits, isEmpty);
    expect(find.textContaining('0.00 ч'), findsOneWidget);
    expect(find.textContaining('250,00 ₽'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

    await tester.tap(find.byKey(const Key('lesson-decision-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lesson-decision-error')), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const Key('lesson-decision-reason')),
          )
          .controller!
          .text,
      'Клиент попросил перенести занятие',
    );

    await tester.tap(find.byKey(const Key('lesson-decision-submit')));
    await tester.pumpAndSettle();
    expect(api.commits, hasLength(2));
    expect(api.identities[0].idempotencyKey, api.identities[1].idempotencyKey);
    final body = api.commits.last;
    expect(body['expectedVersion'], 4);
    expect(body['successor'], _successor);
    expect(body['reasonText'], 'Клиент попросил перенести занятие');
    expect(body['financialDecision'], {
      'settlementTypeKey': 'free_lesson',
      'teacherCompensationRuleKey': 'fixed',
      'teacherCompensationValueMinor': '125000',
    });
    expect(body['previewToken'], 'signed-preview');
    expect(body['confirm'], isTrue);
  });

  testWidgets(
    'cancel recovers from a stale lesson version and requires a fresh preview',
    (tester) async {
      final lesson = Map<String, dynamic>.from(_lesson);
      final api = _LessonDecisionApi(
        operationKey: 'cancel',
        staleVersionFirstCommit: true,
      );
      await _openAndFill(
        tester,
        api,
        lesson: lesson,
        operation: LessonDecisionOperation.cancel,
      );

      final submit = find.byKey(const Key('lesson-decision-submit'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(api.previews.single['expectedVersion'], 4);

      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(api.commits, hasLength(1));
      expect(lesson['version'], 4);
      expect(find.textContaining('Версия обновлена'), findsOneWidget);
      expect(find.text('Рассчитать'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('lesson-decision-reason')),
            )
            .controller!
            .text,
        'Клиент попросил перенести занятие',
      );

      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(api.previews, hasLength(2));
      expect(api.previews.last['expectedVersion'], 5);
      expect(find.text('Отменить занятие'), findsOneWidget);

      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(api.commits, hasLength(2));
      expect(api.commits.last['expectedVersion'], 5);
      expect(
        api.identities.first.idempotencyKey,
        isNot(api.identities.last.idempotencyKey),
      );
    },
  );

  testWidgets('conflict keeps source uncommitted and offers recalculation', (
    tester,
  ) async {
    final api = _LessonDecisionApi(conflict: true);
    await _openAndFill(tester, api);
    await tester.ensureVisible(find.byKey(const Key('lesson-decision-submit')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('lesson-decision-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Изменение заблокировано'), findsOneWidget);
    expect(
      find.textContaining('У преподавателя уже есть занятие в это время'),
      findsOneWidget,
    );
    expect(find.textContaining('Аудитория уже занята'), findsOneWidget);
    expect(
      find.textContaining('Преподаватель не назначен в выбранный филиал'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Аудитория относится к другому филиалу'),
      findsOneWidget,
    );
    expect(find.text('Повторить расчёт'), findsOneWidget);
    expect(api.commits, isEmpty);
  });

  testWidgets('reschedule loads financial decisions for successor branch', (
    tester,
  ) async {
    final api = _LessonDecisionApi(catalogBranchId: _replacementBranchId);
    await tester.pumpWidget(
      _host(
        api,
        successor: const {..._successor, 'branchId': _replacementBranchId},
      ),
    );
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('lesson-decision-reason')), findsOneWidget);
    expect(find.text('Не удалось загрузить правила'), findsNothing);
  });

  testWidgets(
    'completed reschedule fixes reversal decision and explains preserved history',
    (tester) async {
      final api = _LessonDecisionApi(completed: true);
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(api, lesson: _completedLesson));
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('completed-reschedule-notice')),
        findsOneWidget,
      );
      expect(find.textContaining('без удаления истории'), findsOneWidget);
      expect(find.byKey(const Key('lesson-decision-settlement')), findsNothing);
      expect(
        find.byKey(const Key('lesson-decision-compensation')),
        findsNothing,
      );

      await tester.enterText(
        find.byKey(const Key('lesson-decision-reason')),
        'Исправление ошибочно завершённого занятия',
      );
      await tester.ensureVisible(
        find.byKey(const Key('lesson-decision-submit')),
      );
      await tester.tap(find.byKey(const Key('lesson-decision-submit')));
      await tester.pumpAndSettle();

      expect(api.previews.single['financialDecision'], {
        'settlementTypeKey': 'free_lesson',
        'teacherCompensationRuleKey': 'none',
      });
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

      await tester.tap(find.byKey(const Key('lesson-decision-submit')));
      await tester.pumpAndSettle();
      expect(api.commits, hasLength(1));
      expect(api.commits.single['financialDecision'], {
        'settlementTypeKey': 'free_lesson',
        'teacherCompensationRuleKey': 'none',
      });
    },
  );

  testWidgets('all five pay rules are selectable and override needs reason', (
    tester,
  ) async {
    final api = _LessonDecisionApi();
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(api));
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('lesson-decision-settlement')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Бесплатное занятие').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('lesson-decision-compensation')),
    );
    await tester.tap(find.byKey(const Key('lesson-decision-compensation')));
    await tester.pumpAndSettle();
    for (final label in const [
      'Не оплачивать',
      'Полная стандартная ставка',
      'Процент ставки',
      'Фиксированная сумма',
      'Почасовая сумма',
    ]) {
      expect(find.text(label), findsWidgets);
    }
    await tester.tap(find.text('Почасовая сумма').last);
    await tester.pumpAndSettle();

    final valueField = find.byKey(
      const Key('lesson-decision-compensation-value'),
    );
    expect(valueField, findsOneWidget);
    expect(find.text('Ставка за час, ₽ *'), findsOneWidget);
    await tester.enterText(valueField, '1250');
    await tester.ensureVisible(find.byKey(const Key('lesson-decision-submit')));
    await tester.tap(find.byKey(const Key('lesson-decision-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Укажите причину'), findsOneWidget);
    expect(api.previews, isEmpty);

    await tester.enterText(
      find.byKey(const Key('lesson-decision-reason')),
      'Почасовой override согласован директором',
    );
    await tester.tap(find.byKey(const Key('lesson-decision-submit')));
    await tester.pumpAndSettle();

    expect(api.previews, hasLength(1));
    expect(
      api.previews.single['reasonText'],
      'Почасовой override согласован директором',
    );
    expect(api.previews.single['financialDecision'], {
      'settlementTypeKey': 'free_lesson',
      'teacherCompensationRuleKey': 'hourly',
      'teacherCompensationValueMinor': '125000',
    });
  });

  testWidgets(
    'group lesson sends common settlement and one named participant override',
    (tester) async {
      final api = _GroupLessonDecisionApi();
      tester.view.physicalSize = const Size(1500, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showLessonDecisionFlow(
                  context,
                  crm: MagicCrmService(api),
                  operation: LessonDecisionOperation.plannedSettlement,
                  lesson: const {
                    'id': _groupLessonId,
                    'version': 4,
                    'branchId': _branchId,
                    'groupId': '60000000-0000-4000-8000-000000000001',
                    'scheduledAt': '2026-08-13T09:00:00.000Z',
                    'groupParticipants': [
                      {
                        'clientId': _firstGroupStudentId,
                        'clientName': 'Анна Иванова',
                      },
                      {
                        'clientId': _secondGroupStudentId,
                        'clientName': 'Борис Петров',
                      },
                    ],
                  },
                ),
                child: const Text('Открыть группу'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Открыть группу'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('lesson-decision-client-overrides')),
        findsOneWidget,
      );
      expect(find.text('Анна Иванова'), findsOneWidget);
      expect(find.text('Борис Петров'), findsOneWidget);
      expect(find.text('Как у всей группы'), findsNWidgets(2));

      await tester.enterText(
        find.byKey(const Key('lesson-decision-reason')),
        'Анне начисляется полное занятие',
      );
      await tester.tap(find.byKey(const Key('lesson-decision-settlement')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Частично оплачено').last);
      await tester.pumpAndSettle();
      final firstOverride = find.byKey(
        const Key('lesson-decision-client-$_firstGroupStudentId'),
      );
      await tester.ensureVisible(firstOverride);
      await tester.tap(firstOverride);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Занятие').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('lesson-decision-compensation')),
      );
      await tester.tap(find.byKey(const Key('lesson-decision-compensation')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Полная стандартная ставка').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('lesson-decision-submit')),
      );
      await tester.tap(find.byKey(const Key('lesson-decision-submit')));
      await tester.pumpAndSettle();

      expect(api.previews.single['financialDecision'], {
        'settlementTypeKey': 'partially_paid_lesson',
        'clientDecisions': [
          {'clientId': _firstGroupStudentId, 'settlementTypeKey': 'lesson'},
        ],
        'teacherCompensationRuleKey': 'standard',
      });
      expect(find.textContaining('Анна Иванова: Занятие'), findsOneWidget);
      expect(
        find.textContaining('Борис Петров: Частично оплачено'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('lesson-decision-submit')));
      await tester.pumpAndSettle();
      expect(api.commits, hasLength(1));
      expect(
        api.commits.single['financialDecision'],
        api.previews.single['financialDecision'],
      );
    },
  );
}
