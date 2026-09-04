import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision/lesson_decision_sections.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision_flow.dart';

const _lessonId = '10000000-0000-4000-8000-000000000001';
const _branchId = '20000000-0000-4000-8000-000000000001';
const _replacementBranchId = '20000000-0000-4000-8000-000000000002';
const _groupLessonId = '30000000-0000-4000-8000-000000000001';
const _firstGroupStudentId = '40000000-0000-4000-8000-000000000001';
const _secondGroupStudentId = '50000000-0000-4000-8000-000000000001';
const _crossPayerSubscriptionId = '70000000-0000-4000-8000-000000000001';
const _leadId = '80000000-0000-4000-8000-000000000001';

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
  final normalizedDecisions = <Map<String, dynamic>>[];
  final commits = <Map<String, dynamic>>[];
  final identities = <MagicMutationIdentity>[];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/students/$_firstGroupStudentId/commerce') {
      return _studentCommerce(
            _firstGroupStudentId,
            subscriptionId: _crossPayerSubscriptionId,
          )
          as T;
    }
    expect(path, '/crm/configuration/lesson-decisions');
    expect(queryParameters?['branchId'], catalogBranchId);
    return <String, dynamic>{
          'settlementTypes': const [
            {
              'stableKey': 'lesson',
              'label': 'Занятие',
              'colorToken': 'success',
              'clientDurationMode': 'full',
              'teacherDurationMode': 'full',
              'defaultTeacherCompensationRuleKey': 'standard',
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
            {
              'stableKey': 'paid_miss',
              'label': 'Оплачиваемый пропуск',
              'colorToken': 'info',
              'clientDurationMode': 'full',
              'teacherDurationMode': 'full',
              'defaultTeacherCompensationRuleKey': 'standard',
              'allowedContexts': ['cancel'],
              'active': true,
              'order': 2,
            },
            {
              'stableKey': 'partially_paid_miss',
              'label': 'Частично оплачиваемый пропуск',
              'colorToken': 'warning',
              'clientDurationMode': 'manual',
              'teacherDurationMode': 'manual',
              'defaultTeacherCompensationRuleKey': 'percent',
              'allowedContexts': ['cancel'],
              'active': true,
              'order': 3,
            },
            {
              'stableKey': 'unpaid_miss',
              'label': 'Неоплачиваемый пропуск',
              'colorToken': 'warning',
              'clientDurationMode': 'zero',
              'teacherDurationMode': 'zero',
              'defaultTeacherCompensationRuleKey': 'none',
              'allowedContexts': ['cancel'],
              'active': true,
              'order': 4,
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
    final decisionKey = operationKey == 'reschedule'
        ? 'successorFinancialDecision'
        : 'financialDecision';
    final requestDecision = Map<String, dynamic>.from(
      previews.last[decisionKey] as Map,
    );
    final normalizedDecision = operationKey == 'cancel'
        ? _normalizeCancelDecision(requestDecision)
        : requestDecision;
    normalizedDecisions.add(normalizedDecision);
    return <String, dynamic>{
          'operation': operationKey,
          'source': {
            'id': _lessonId,
            'version': previews.last['expectedVersion'],
            'state': completed ? 'successfully_completed' : 'scheduled',
          },
          'successor': _successor,
          'financialDecision': normalizedDecision,
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
    return <String, dynamic>{
          'source': {'id': _lessonId, 'state': 'rescheduled', 'version': 5},
          'successor': null,
          'transitionId': 'transition-1',
          'clientFinancialFactIds': const <String>[],
          'teacherFinancialFactId': 'teacher-fact-1',
          'successorFinancialDecision':
              commits.last['successorFinancialDecision'],
          'replayed': commits.length > 1,
        }
        as T;
  }
}

class _GroupLessonDecisionApi extends MagicApiClient {
  _GroupLessonDecisionApi({this.operationKey = 'planned-settlement'})
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final String operationKey;
  final previews = <Map<String, dynamic>>[];
  final commits = <Map<String, dynamic>>[];
  final payerQueries = <Map<String, dynamic>>[];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/clients/search') {
      payerQueries.add(Map<String, dynamic>.from(queryParameters ?? const {}));
      expect(queryParameters?['type'], 'student');
      expect(queryParameters?['branchId'], isNull);
      expect(queryParameters?['limit'], 50);
      return <String, dynamic>{
            'items': const [
              {
                'ref': {'type': 'student', 'id': _firstGroupStudentId},
                'label': 'Анна Иванова',
                'branchId': _branchId,
              },
            ],
          }
          as T;
    }
    if (path == '/crm/students/$_firstGroupStudentId/commerce') {
      return _studentCommerce(
            _firstGroupStudentId,
            subscriptionId: _crossPayerSubscriptionId,
          )
          as T;
    }
    if (path == '/crm/students/$_secondGroupStudentId/commerce') {
      return _studentCommerce(_secondGroupStudentId) as T;
    }
    expect(path, '/crm/configuration/lesson-decisions');
    expect(queryParameters?['branchId'], _branchId);
    return <String, dynamic>{
          'settlementTypes': const [
            {
              'stableKey': 'lesson',
              'label': 'Занятие',
              'colorToken': 'success',
              'allowedContexts': ['settle', 'reschedule'],
              'active': true,
              'order': 0,
            },
            {
              'stableKey': 'partially_paid_lesson',
              'label': 'Частично оплачено',
              'colorToken': 'warning',
              'clientDurationMode': 'manual',
              'teacherDurationMode': 'manual',
              'defaultTeacherCompensationRuleKey': 'percent',
              'allowedContexts': ['settle', 'reschedule'],
              'active': true,
              'order': 1,
            },
            {
              'stableKey': 'partially_paid_lesson_alt',
              'label': 'Частично оплачено по соглашению',
              'colorToken': 'warning',
              'clientDurationMode': 'manual',
              'teacherDurationMode': 'manual',
              'defaultTeacherCompensationRuleKey': 'percent',
              'allowedContexts': ['settle', 'reschedule'],
              'active': true,
              'order': 2,
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
            {
              'stableKey': 'percent',
              'label': 'Процент ставки',
              'mode': 'percent',
              'value': '10000',
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
    expect(path, '/crm/lessons/$_groupLessonId/$operationKey/preview');
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
    expect(path, '/crm/lessons/$_groupLessonId/$operationKey');
    expect(mutationIdentity, isNotNull);
    commits.add(Map<String, dynamic>.from(data as Map));
    return <String, dynamic>{'lessonId': _groupLessonId, 'version': 5} as T;
  }
}

Map<String, dynamic> _studentCommerce(
  String studentId, {
  String? subscriptionId,
}) => {
  'projection': 'manager_scoped',
  'student': {
    'studentId': studentId,
    'accounts': const [],
    'subscriptions': [
      if (subscriptionId != null)
        {
          'id': subscriptionId,
          'status': 'active',
          'startsAt': '2026-08-01T00:00:00.000Z',
          'expiresAt': '2026-12-31T00:00:00.000Z',
          'units': const {
            'total': 10,
            'used': 2,
            'reserved': 0,
            'paid': 2,
            'available': 8,
            'remaining': 8,
          },
          'financial': const {
            'actualPaidMinor': '800000',
            'obligationMinor': '800000',
            'debtMinor': '0',
            'pendingMinor': '0',
            'remainingObligationMinor': '0',
            'overpaymentMinor': '0',
            'nextPaymentAt': null,
          },
          'terms': const {
            'displayName': 'Семейный абонемент',
            'validityDays': 120,
            'basePriceMinor': '800000',
            'finalPriceMinor': '800000',
            'currencyCode': 'RUB',
            'discount': {'type': 'none'},
            'surcharge': {'type': 'none'},
          },
          'installments': const [],
        },
    ],
    'movements': const [],
    'technicalHistory': const [],
    'lessonBalance': {
      'activeSubscriptionCount': subscriptionId == null ? 0 : 1,
      'total': subscriptionId == null ? 0 : 10,
      'used': subscriptionId == null ? 0 : 2,
      'reserved': 0,
      'paid': subscriptionId == null ? 0 : 2,
      'available': subscriptionId == null ? 0 : 8,
      'debts': const [],
      'nextPaymentAt': null,
      'expiresAt': subscriptionId == null ? null : '2026-12-31T00:00:00.000Z',
    },
  },
};

Widget _host(
  _LessonDecisionApi api, {
  Map<String, dynamic> lesson = _lesson,
  Map<String, dynamic> successor = _successor,
  LessonDecisionOperation operation = LessonDecisionOperation.reschedule,
  bool canManageTeacherCompensation = true,
  LessonDecisionCommitted? afterCommit,
}) => MaterialApp(
  theme: ThemeData(platform: TargetPlatform.windows),
  home: Scaffold(
    body: Builder(
      builder: (context) => FilledButton(
        onPressed: () => showLessonDecisionFlow(
          context,
          crm: MagicCrmService(api),
          canManageTeacherCompensation: canManageTeacherCompensation,
          operation: operation,
          lesson: lesson,
          successor: successor,
          afterCommit: afterCommit,
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

Map<String, dynamic> _normalizeCancelDecision(Map<String, dynamic> decision) {
  final settlementTypeKey = decision['settlementTypeKey']?.toString();
  final recommendedMinutes = switch (settlementTypeKey) {
    'paid_miss' => 60,
    'unpaid_miss' => 0,
    _ => null,
  };
  return {
    ...decision,
    'clientDecisions': [
      for (final item in decision['clientDecisions'] as List? ?? const [])
        if (item is Map)
          {
            ...Map<String, dynamic>.from(item),
            if (item['chargeDurationMinutes'] == null &&
                recommendedMinutes != null)
              'chargeDurationMinutes': recommendedMinutes,
          },
    ],
  };
}

void main() {
  testWidgets(
    'cancel opens unpaid and paid miss autofills full duration once',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _LessonDecisionApi(operationKey: 'cancel');
      await tester.pumpWidget(
        _host(
          api,
          operation: LessonDecisionOperation.cancel,
          lesson: const {
            ..._lesson,
            'studentId': _firstGroupStudentId,
            'studentName': 'Анна Иванова',
            'durationMinutes': 60,
            'financialDecision': {
              'settlementTypeKey': 'lesson',
              'teacherCompensationRuleKey': 'standard',
              'teacherCreditedDurationMinutes': 60,
              'teacherCompensationSource': 'automatic',
              'clientDecisions': [
                {
                  'clientId': _firstGroupStudentId,
                  'chargeType': 'subscription',
                  'payerStudentId': _firstGroupStudentId,
                  'subscriptionId': _crossPayerSubscriptionId,
                },
              ],
            },
          },
        ),
      );
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();

      final settlement = tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const Key('lesson-decision-settlement')),
      );
      expect(settlement.initialValue, 'unpaid_miss');

      await tester.enterText(
        find.byKey(const Key('lesson-decision-reason')),
        'Отмена по просьбе клиента',
      );
      await tester.ensureVisible(
        find.byKey(const Key('lesson-decision-submit')),
      );
      await tester.tap(find.byKey(const Key('lesson-decision-submit')));
      await tester.pumpAndSettle();
      expect(api.previews.single['financialDecision'], {
        'settlementTypeKey': 'unpaid_miss',
        'clientDecisions': [
          {'clientId': _firstGroupStudentId, 'chargeType': 'none'},
        ],
        'teacherCompensationRuleKey': 'none',
        'teacherCreditedDurationMinutes': 0,
        'teacherCompensationSource': 'automatic',
      });

      await tester.tap(find.byKey(const Key('lesson-decision-submit')));
      await tester.pumpAndSettle();
      final paidApi = _LessonDecisionApi(operationKey: 'cancel');
      await tester.pumpWidget(
        _host(
          paidApi,
          operation: LessonDecisionOperation.cancel,
          lesson: const {
            ..._lesson,
            'studentId': _firstGroupStudentId,
            'durationMinutes': 60,
            'financialDecision': {
              'settlementTypeKey': 'lesson',
              'clientDecisions': [
                {
                  'clientId': _firstGroupStudentId,
                  'chargeType': 'subscription',
                  'payerStudentId': _firstGroupStudentId,
                  'subscriptionId': _crossPayerSubscriptionId,
                },
              ],
            },
          },
        ),
      );
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('lesson-decision-settlement')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Оплачиваемый пропуск').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('lesson-decision-reason')),
        'Оплачиваемый пропуск по правилу',
      );
      await tester.ensureVisible(
        find.byKey(const Key('lesson-decision-submit')),
      );
      await tester.tap(find.byKey(const Key('lesson-decision-submit')));
      await tester.pumpAndSettle();
      expect(paidApi.previews.single['financialDecision'], {
        'settlementTypeKey': 'paid_miss',
        'clientDecisions': [
          {
            'clientId': _firstGroupStudentId,
            'chargeType': 'subscription',
            'payerStudentId': _firstGroupStudentId,
            'subscriptionId': _crossPayerSubscriptionId,
          },
        ],
        'teacherCompensationRuleKey': 'standard',
        'teacherCreditedDurationMinutes': 60,
        'teacherCompensationSource': 'automatic',
      });
      expect(paidApi.normalizedDecisions.single, {
        'settlementTypeKey': 'paid_miss',
        'clientDecisions': [
          {
            'clientId': _firstGroupStudentId,
            'chargeType': 'subscription',
            'payerStudentId': _firstGroupStudentId,
            'subscriptionId': _crossPayerSubscriptionId,
            'chargeDurationMinutes': 60,
          },
        ],
        'teacherCompensationRuleKey': 'standard',
        'teacherCreditedDurationMinutes': 60,
        'teacherCompensationSource': 'automatic',
      });
    },
  );

  testWidgets(
    'switching cancellation type after manual edits asks before preserving them',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _LessonDecisionApi(operationKey: 'cancel');
      await tester.pumpWidget(
        _host(
          api,
          operation: LessonDecisionOperation.cancel,
          lesson: const {
            ..._lesson,
            'studentId': _firstGroupStudentId,
            'durationMinutes': 60,
            'financialDecision': {
              'settlementTypeKey': 'lesson',
              'clientDecisions': [
                {
                  'clientId': _firstGroupStudentId,
                  'chargeType': 'subscription',
                  'payerStudentId': _firstGroupStudentId,
                  'subscriptionId': _crossPayerSubscriptionId,
                },
              ],
            },
          },
        ),
      );
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('lesson-decision-settlement')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Частично оплачиваемый пропуск').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(
          const Key('lesson-decision-client-duration-$_firstGroupStudentId'),
        ),
        '30',
      );
      await tester.enterText(
        find.byKey(const Key('teacher-credited-duration-minutes')),
        '45',
      );
      await tester.tap(find.byKey(const Key('lesson-decision-settlement')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Оплачиваемый пропуск').last);
      await tester.pump();

      expect(
        find.text('Применить рекомендованные значения для нового типа?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Оставить мои значения'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('lesson-decision-reason')),
        'Согласованы отдельные часы',
      );
      await tester.ensureVisible(
        find.byKey(const Key('lesson-decision-submit')),
      );
      await tester.tap(find.byKey(const Key('lesson-decision-submit')));
      await tester.pumpAndSettle();

      expect(api.previews, hasLength(1));
      expect(api.previews.single['financialDecision'], {
        'settlementTypeKey': 'paid_miss',
        'clientDecisions': [
          {
            'clientId': _firstGroupStudentId,
            'chargeDurationMinutes': 30,
            'chargeType': 'subscription',
            'payerStudentId': _firstGroupStudentId,
            'subscriptionId': _crossPayerSubscriptionId,
          },
        ],
        'teacherCompensationRuleKey': 'percent',
        'teacherCompensationValueMinor': '6250',
        'teacherCreditedDurationMinutes': 45,
        'teacherCompensationSource': 'manual',
      });
      expect(api.normalizedDecisions.single, {
        'settlementTypeKey': 'paid_miss',
        'clientDecisions': [
          {
            'clientId': _firstGroupStudentId,
            'chargeDurationMinutes': 30,
            'chargeType': 'subscription',
            'payerStudentId': _firstGroupStudentId,
            'subscriptionId': _crossPayerSubscriptionId,
          },
        ],
        'teacherCompensationRuleKey': 'percent',
        'teacherCompensationValueMinor': '6250',
        'teacherCreditedDurationMinutes': 45,
        'teacherCompensationSource': 'manual',
      });
    },
  );

  test('individual lead identity survives snake and camel read shapes', () {
    for (final fixture in [
      (
        lesson: const {
          ..._lesson,
          'lead_id': _leadId,
          'lead_name': 'Лид Снэйк',
        },
        name: 'Лид Снэйк',
      ),
      (
        lesson: const {..._lesson, 'leadId': _leadId, 'leadName': 'Лид Кэмел'},
        name: 'Лид Кэмел',
      ),
      (
        lesson: const {
          ..._lesson,
          'clientType': 'lead',
          'clientId': _leadId,
          'clientName': 'Лид Generic',
        },
        name: 'Лид Generic',
      ),
    ]) {
      final controller = LessonDecisionController(
        crm: MagicCrmService(_LessonDecisionApi()),
        operation: LessonDecisionOperation.plannedSettlement,
        lesson: fixture.lesson,
        canManageTeacherCompensation: false,
      );

      expect(controller.settlementClients, hasLength(1));
      expect(controller.settlementClients.single.id, _leadId);
      expect(controller.settlementClients.single.name, fixture.name);
      expect(controller.settlementClients.single.isStudent, isFalse);
      expect(controller.initialClientDecisions, [
        {'clientId': _leadId, 'chargeType': 'none'},
      ]);
    }
  });

  testWidgets(
    'planned settlement previews the exact frozen lead with no fake funding',
    (tester) async {
      final api = _LessonDecisionApi(operationKey: 'planned-settlement');
      final lesson = <String, dynamic>{
        ..._lesson,
        'clientType': 'lead',
        'clientId': _leadId,
        'clientName': 'Лид Кэмел',
        'financialDecision': {'settlementTypeKey': 'lesson'},
      };
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          api,
          lesson: lesson,
          operation: LessonDecisionOperation.plannedSettlement,
          canManageTeacherCompensation: false,
        ),
      );
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('lesson-decision-reason')),
        'Проверка frozen lead',
      );
      await tester.tap(find.byKey(const Key('lesson-decision-submit')));
      await tester.pumpAndSettle();

      expect(api.previews.single['financialDecision'], {
        'settlementTypeKey': 'lesson',
        'clientDecisions': [
          {'clientId': _leadId, 'chargeType': 'none'},
        ],
      });
    },
  );

  for (final operation in [
    LessonDecisionOperation.plannedSettlement,
    LessonDecisionOperation.correction,
    LessonDecisionOperation.cancel,
    LessonDecisionOperation.reschedule,
  ]) {
    testWidgets(
      operation == LessonDecisionOperation.cancel
          ? 'cancel replaces a stored lead decision with the unpaid default'
          : 'stored lead decision round-trips through ${operation.apiKey}',
      (tester) async {
        final settlementKey = switch (operation) {
          LessonDecisionOperation.edit ||
          LessonDecisionOperation.plannedSettlement ||
          LessonDecisionOperation.correction => 'lesson',
          _ => 'free_lesson',
        };
        final api = _LessonDecisionApi(operationKey: operation.apiKey);
        final lesson = <String, dynamic>{
          ..._lesson,
          'client_type': 'lead',
          'lead_id': _leadId,
          'lead_name': 'Лид Снэйк',
          'financial_decision': {
            'settlementTypeKey': settlementKey,
            'clientDecisions': [
              {
                'clientId': _leadId,
                'settlementTypeKey': settlementKey,
                'chargeType': 'none',
              },
            ],
          },
        };
        tester.view.physicalSize = const Size(1400, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          _host(
            api,
            lesson: lesson,
            operation: operation,
            canManageTeacherCompensation: false,
          ),
        );
        await tester.tap(find.text('Открыть'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('lesson-decision-reason')),
          'Без изменения решения лида',
        );
        await tester.tap(find.byKey(const Key('lesson-decision-submit')));
        await tester.pumpAndSettle();

        final preview =
            api.previews.single[operation == LessonDecisionOperation.reschedule
                    ? 'successorFinancialDecision'
                    : 'financialDecision']
                as Map;
        if (operation == LessonDecisionOperation.cancel) {
          expect(preview['settlementTypeKey'], 'unpaid_miss');
          expect(preview['clientDecisions'], [
            {'clientId': _leadId, 'chargeType': 'none'},
          ]);
        } else {
          expect(preview['clientDecisions'], [
            {
              'clientId': _leadId,
              'settlementTypeKey': settlementKey,
              'chargeType': 'none',
            },
          ]);
        }
      },
    );
  }

  for (final operation in [
    LessonDecisionOperation.plannedSettlement,
    LessonDecisionOperation.correction,
  ]) {
    test(
      'resource edits use ${operation.apiKey} and the target branch catalog',
      () async {
        final api = _LessonDecisionApi(
          operationKey: operation.apiKey,
          catalogBranchId: _replacementBranchId,
        );
        final resources = {
          'teacherId': 'teacher-new',
          'branchId': _replacementBranchId,
          'roomId': 'room-new',
        };
        final controller = LessonDecisionController(
          crm: MagicCrmService(api),
          operation: operation,
          lesson: _lesson,
          resources: resources,
          canManageTeacherCompensation: true,
        );
        await controller.loadCatalog();
        await controller.preview(
          settlementTypeKey: 'free_lesson',
          compensationRuleKey: 'standard',
          reason: 'Исправление занятия',
        );
        expect(api.previews.single['resources'], resources);
        expect(api.previews.single.containsKey('successor'), isFalse);
      },
    );
  }
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('completed reschedule section explains forced reversal', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: LessonDecisionCompletedNotice(
            sourceScheduledAt: DateTime(2026, 8, 25, 13),
            successorScheduledAt: DateTime(2026, 8, 26, 13),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('lesson-decision-completed-notice')),
      findsOneWidget,
    );
    expect(find.textContaining('бесплатное'), findsOneWidget);
  });

  test('flow entry contains no form state or section implementation', () {
    final source = File(
      'lib/features/admin/presentation/widgets/lesson_decision_flow.dart',
    ).readAsStringSync();
    final formSource = File(
      'lib/features/admin/presentation/widgets/lesson_decision/'
      'lesson_decision_form.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('class _LessonDecisionFormState')));
    expect(source, isNot(contains('class _LessonDecisionPreviewCard')));
    expect(source, isNot(contains('class _PreviewCard')));
    expect(source.split('\n').length, lessThan(120));
    expect(
      formSource,
      isNot(contains("import 'lesson_decision_controller.dart';")),
    );
  });

  test('keeps one mutation identity between preview and commit', () async {
    final api = _LessonDecisionApi();
    Map<String, dynamic>? committed;
    final controller = LessonDecisionController(
      crm: MagicCrmService(api),
      canManageTeacherCompensation: true,
      operation: LessonDecisionOperation.reschedule,
      lesson: _lesson,
      successor: _successor,
      afterCommit: (result) async => committed = result,
    );

    final preview = await controller.preview(
      reason: 'Перенос',
      settlementTypeKey: 'standard',
      compensationRuleKey: 'standard',
    );
    await controller.commit(preview);

    expect(api.identities, hasLength(1));
    expect(api.commits.single['previewToken'], 'signed-preview');
    expect((committed?['source'] as Map?)?['version'], 5);
  });

  test('decision failure skips pending work and retry runs it once', () async {
    final api = _LessonDecisionApi(failFirstCommit: true);
    var pendingCalls = 0;
    final controller = LessonDecisionController(
      crm: MagicCrmService(api),
      canManageTeacherCompensation: true,
      operation: LessonDecisionOperation.reschedule,
      lesson: _lesson,
      successor: _successor,
      afterCommit: (_) async => pendingCalls++,
    );
    final preview = await controller.preview(
      reason: 'Перенос',
      settlementTypeKey: 'free_lesson',
      compensationRuleKey: 'fixed',
      compensationValueMinor: '125000',
    );

    await expectLater(
      controller.commit(preview),
      throwsA(isA<MagicApiException>()),
    );
    expect(pendingCalls, 0);
    await controller.commit(preview);

    expect(pendingCalls, 1);
    expect(api.identities, hasLength(2));
    expect(api.identities[1].idempotencyKey, api.identities[0].idempotencyKey);
  });

  testWidgets('closing the decision leaves pending work untouched', (
    tester,
  ) async {
    final api = _LessonDecisionApi();
    var pendingCalls = 0;
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(api, afterCommit: (_) async => pendingCalls++),
    );

    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    final close = find.text('Закрыть');
    await tester.ensureVisible(close);
    await tester.tap(close);
    await tester.pumpAndSettle();

    expect(api.commits, isEmpty);
    expect(pendingCalls, 0);
  });

  test(
    'operational controller omits every teacher compensation field',
    () async {
      final api = _LessonDecisionApi();
      final controller = LessonDecisionController(
        crm: MagicCrmService(api),
        canManageTeacherCompensation: false,
        operation: LessonDecisionOperation.reschedule,
        lesson: _lesson,
        successor: _successor,
      );

      await controller.preview(
        reason: 'Отмена',
        settlementTypeKey: 'free_lesson',
        compensationRuleKey: 'fixed',
        compensationValueMinor: '125000',
      );

      final decision = Map<String, dynamic>.from(
        api.previews.single['successorFinancialDecision'] as Map,
      );
      expect(decision, {'settlementTypeKey': 'free_lesson'});
    },
  );

  testWidgets('operational flow renders no compensation controls', (
    tester,
  ) async {
    final api = _LessonDecisionApi();
    await tester.pumpWidget(_host(api, canManageTeacherCompensation: false));
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('lesson-decision-compensation')), findsNothing);
    expect(
      find.byKey(const Key('lesson-decision-compensation-value')),
      findsNothing,
    );
  });

  test(
    'clears preview identity and adopts current version after stale commit',
    () async {
      final controller = LessonDecisionController(
        crm: MagicCrmService(_LessonDecisionApi()),
        canManageTeacherCompensation: true,
        operation: LessonDecisionOperation.reschedule,
        lesson: _lesson,
        successor: _successor,
      );

      final recovered = await controller.recoverStaleCommit(
        const MagicApiException(
          statusCode: 409,
          message: 'stale',
          details: {'code': 'STALE_LESSON_VERSION', 'currentVersion': 7},
        ),
      );

      expect(
        recovered?.message,
        'Занятие уже изменилось. Я открыл актуальную версию.',
      );
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
    expect(body['successorFinancialDecision'], {
      'settlementTypeKey': 'free_lesson',
      'teacherCompensationRuleKey': 'fixed',
      'teacherCompensationValueMinor': '125000',
      'teacherCompensationSource': 'manual',
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
      expect(
        find.text('Занятие уже изменилось. Я открыл актуальную версию.'),
        findsOneWidget,
      );
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

      expect(api.previews.single['successorFinancialDecision'], {
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
      expect(api.commits.single['successorFinancialDecision'], {
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
    expect(api.previews.single['successorFinancialDecision'], {
      'settlementTypeKey': 'free_lesson',
      'teacherCompensationRuleKey': 'hourly',
      'teacherCompensationValueMinor': '125000',
      'teacherCompensationSource': 'manual',
    });
  });

  testWidgets(
    "group recipient finds a payer beyond the first page and uses their subscription",
    (tester) async {
      final api = _GroupLessonDecisionApi();
      tester.view.physicalSize = const Size(1500, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showLessonDecisionFlow(
                  context,
                  crm: MagicCrmService(api),
                  canManageTeacherCompensation: true,
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
                child: const Text('Открыть оплату'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Открыть оплату'));
      await tester.pumpAndSettle();

      final payerField = find.byKey(
        const Key('lesson-decision-payer-$_secondGroupStudentId'),
      );
      expect(payerField, findsOneWidget);
      await tester.ensureVisible(payerField);
      await tester.tap(payerField);
      await tester.enterText(
        find.descendant(of: payerField, matching: find.byType(TextField)),
        'Анна',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(api.payerQueries, hasLength(1));
      expect(api.payerQueries.single['q'], 'Анна');
      await tester.tap(find.text('Анна Иванова').last);
      await tester.pumpAndSettle();

      final subscriptionField = find.byKey(
        const Key('lesson-decision-subscription-$_secondGroupStudentId'),
      );
      expect(subscriptionField, findsOneWidget);
      await tester.ensureVisible(subscriptionField);
      await tester.tap(subscriptionField);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Семейный абонемент').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('lesson-decision-reason')),
        'Абонемент Анны оплачивает занятие Бориса',
      );
      await tester.tap(find.byKey(const Key('lesson-decision-settlement')));
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
        'settlementTypeKey': 'lesson',
        'clientDecisions': [
          {
            'clientId': _secondGroupStudentId,
            'payerStudentId': _firstGroupStudentId,
            'subscriptionId': _crossPayerSubscriptionId,
          },
        ],
        'teacherCompensationRuleKey': 'standard',
        'teacherCompensationSource': 'manual',
      });
      expect(find.textContaining('Преподаватель:'), findsOneWidget);
    },
  );

  testWidgets(
    'group lesson sends common settlement and one named participant override',
    (tester) async {
      final api = _GroupLessonDecisionApi();
      tester.view.physicalSize = const Size(1500, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showLessonDecisionFlow(
                  context,
                  crm: MagicCrmService(api),
                  canManageTeacherCompensation: true,
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
      final teacherDuration = find.byKey(
        const Key('teacher-credited-duration-minutes'),
      );
      expect(teacherDuration, findsOneWidget);
      expect(
        find.byKey(
          const Key('lesson-decision-client-duration-$_firstGroupStudentId'),
        ),
        findsOneWidget,
      );
      final secondDuration = find.byKey(
        const Key('lesson-decision-client-duration-$_secondGroupStudentId'),
      );
      expect(secondDuration, findsOneWidget);
      await tester.enterText(teacherDuration, '45');
      await tester.enterText(secondDuration, '30');
      final restoreRecommendation = find.byKey(
        const Key('lesson-decision-restore-recommendation'),
      );
      expect(restoreRecommendation, findsOneWidget);
      await tester.ensureVisible(restoreRecommendation);
      await tester.tap(restoreRecommendation);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: teacherDuration,
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        isEmpty,
      );
      expect(restoreRecommendation, findsNothing);
      await tester.enterText(teacherDuration, '45');
      final firstOverride = find.byKey(
        const Key('lesson-decision-client-$_firstGroupStudentId'),
      );
      await tester.ensureVisible(firstOverride);
      await tester.tap(firstOverride);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Занятие').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          const Key('lesson-decision-client-duration-$_firstGroupStudentId'),
        ),
        findsNothing,
      );
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: teacherDuration,
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        '45',
      );
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: secondDuration,
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        '30',
      );
      final secondOverride = find.byKey(
        const Key('lesson-decision-client-$_secondGroupStudentId'),
      );
      await tester.ensureVisible(secondOverride);
      await tester.tap(secondOverride);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Частично оплачено по соглашению').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: secondDuration,
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        isEmpty,
      );
      await tester.ensureVisible(
        find.byKey(const Key('lesson-decision-submit')),
      );
      await tester.tap(find.byKey(const Key('lesson-decision-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Укажите длительность в минутах'), findsOneWidget);
      expect(api.previews, isEmpty);
      await tester.enterText(secondDuration, '25');
      await tester.tap(find.byKey(const Key('lesson-decision-submit')));
      await tester.pumpAndSettle();

      expect(api.previews.single['financialDecision'], {
        'settlementTypeKey': 'partially_paid_lesson',
        'clientDecisions': [
          {'clientId': _firstGroupStudentId, 'settlementTypeKey': 'lesson'},
          {
            'clientId': _secondGroupStudentId,
            'settlementTypeKey': 'partially_paid_lesson_alt',
            'chargeDurationMinutes': 25,
          },
        ],
        'teacherCompensationRuleKey': 'percent',
        'teacherCompensationValueMinor': '10000',
        'teacherCreditedDurationMinutes': 45,
        'teacherCompensationSource': 'manual',
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

  test('reschedule and correction expose the complete stored decision', () {
    const storedClients = [
      {
        'clientId': _firstGroupStudentId,
        'settlementTypeKey': 'partially_paid_lesson',
        'chargeDurationMinutes': 0,
        'payerStudentId': _firstGroupStudentId,
        'chargeType': 'subscription',
        'subscriptionId': _crossPayerSubscriptionId,
      },
    ];
    for (final operation in [
      LessonDecisionOperation.reschedule,
      LessonDecisionOperation.correction,
    ]) {
      final controller = LessonDecisionController(
        crm: MagicCrmService(_GroupLessonDecisionApi()),
        canManageTeacherCompensation: true,
        operation: operation,
        lesson: const {
          'id': _groupLessonId,
          'version': 4,
          'financial_decision': {
            'settlementTypeKey': 'partially_paid_lesson',
            'teacherCompensationRuleKey': 'percent',
            'teacherCompensationValueMinor': '7500',
            'teacherCreditedDurationMinutes': 41,
            'teacherCompensationSource': 'manual',
            'clientDecisions': storedClients,
          },
        },
      );

      expect(controller.initialSettlementTypeKey, 'partially_paid_lesson');
      expect(controller.initialCompensationRuleKey, 'percent');
      expect(controller.initialCompensationValueMinor, '7500');
      expect(controller.initialClientDecisions, storedClients);
      expect(
        controller.initialClientDecisions.single['chargeDurationMinutes'],
        0,
      );
    }
  });

  testWidgets(
    'correction reopens one partial subscription decision without semantic edits',
    (tester) async {
      final api = _GroupLessonDecisionApi(
        operationKey: 'settlement-correction',
      );
      await _openStoredDecision(
        tester,
        api: api,
        operation: LessonDecisionOperation.correction,
        lesson: const {
          'id': _groupLessonId,
          'version': 4,
          'branchId': _branchId,
          'studentId': _firstGroupStudentId,
          'studentName': 'Анна Иванова',
          'durationMinutes': 60,
          'scheduledAt': '2026-08-13T09:00:00.000Z',
          'financialDecision': {
            'settlementTypeKey': 'partially_paid_lesson',
            'teacherCompensationRuleKey': 'percent',
            'teacherCompensationValueMinor': '7500',
            'teacherCreditedDurationMinutes': 41,
            'teacherCompensationSource': 'manual',
            'clientDecisions': [
              {
                'clientId': _firstGroupStudentId,
                'settlementTypeKey': 'partially_paid_lesson',
                'chargeDurationMinutes': 19,
                'payerStudentId': _firstGroupStudentId,
                'chargeType': 'subscription',
                'subscriptionId': _crossPayerSubscriptionId,
              },
            ],
          },
        },
      );

      expect(
        _fieldText(
          tester,
          const Key('lesson-decision-client-duration-$_firstGroupStudentId'),
        ),
        '19',
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(
                const Key('lesson-decision-charge-type-$_firstGroupStudentId'),
              ),
            )
            .initialValue,
        'subscription',
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(
                const Key('lesson-decision-subscription-$_firstGroupStudentId'),
              ),
            )
            .initialValue,
        _crossPayerSubscriptionId,
      );

      await _previewStoredDecision(tester, 'Без изменений');
      expect(api.previews.single['financialDecision'], {
        'settlementTypeKey': 'partially_paid_lesson',
        'clientDecisions': [
          {
            'clientId': _firstGroupStudentId,
            'settlementTypeKey': 'partially_paid_lesson',
            'chargeDurationMinutes': 19,
            'chargeType': 'subscription',
            'payerStudentId': _firstGroupStudentId,
            'subscriptionId': _crossPayerSubscriptionId,
          },
        ],
        'teacherCompensationRuleKey': 'percent',
        'teacherCompensationValueMinor': '7500',
        'teacherCreditedDurationMinutes': 41,
        'teacherCompensationSource': 'manual',
      });
    },
  );

  testWidgets(
    'reschedule keeps independent group payer source settlement and minutes',
    (tester) async {
      final api = _GroupLessonDecisionApi(operationKey: 'reschedule');
      await _openStoredDecision(
        tester,
        api: api,
        operation: LessonDecisionOperation.reschedule,
        lesson: const {
          'id': _groupLessonId,
          'version': 4,
          'branchId': _branchId,
          'groupId': '60000000-0000-4000-8000-000000000001',
          'durationMinutes': 60,
          'scheduledAt': '2026-08-13T09:00:00.000Z',
          'groupParticipants': [
            {'clientId': _firstGroupStudentId, 'clientName': 'Анна Иванова'},
            {'clientId': _secondGroupStudentId, 'clientName': 'Борис Петров'},
          ],
          'financialDecision': {
            'settlementTypeKey': 'partially_paid_lesson',
            'teacherCompensationRuleKey': 'percent',
            'teacherCompensationValueMinor': '7500',
            'teacherCreditedDurationMinutes': 41,
            'teacherCompensationSource': 'manual',
            'clientDecisions': [
              {
                'clientId': _firstGroupStudentId,
                'chargeDurationMinutes': 0,
                'payerStudentId': _firstGroupStudentId,
                'chargeType': 'subscription',
                'subscriptionId': _crossPayerSubscriptionId,
              },
              {
                'clientId': _secondGroupStudentId,
                'settlementTypeKey': 'partially_paid_lesson_alt',
                'chargeDurationMinutes': 25,
                'payerStudentId': _secondGroupStudentId,
                'chargeType': 'personal_account',
                'basePriceMinor': '100000',
                'discount': {
                  'type': 'percent',
                  'percent': 12.5,
                  'reason': 'Семейная скидка',
                },
                'surcharge': {'amountMinor': '5000', 'reason': 'Материалы'},
              },
            ],
          },
        },
      );

      expect(
        _fieldText(
          tester,
          const Key('lesson-decision-client-duration-$_firstGroupStudentId'),
        ),
        '0',
      );
      expect(
        _fieldText(
          tester,
          const Key('lesson-decision-client-duration-$_secondGroupStudentId'),
        ),
        '25',
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(
                const Key('lesson-decision-charge-type-$_secondGroupStudentId'),
              ),
            )
            .initialValue,
        'personal_account',
      );
      expect(
        find.byKey(
          const Key('lesson-decision-subscription-$_secondGroupStudentId'),
        ),
        findsNothing,
      );

      await _previewStoredDecision(tester, 'Группа без изменений');
      expect(api.previews.single['successorFinancialDecision'], {
        'settlementTypeKey': 'partially_paid_lesson',
        'clientDecisions': [
          {
            'clientId': _firstGroupStudentId,
            'chargeDurationMinutes': 0,
            'chargeType': 'subscription',
            'payerStudentId': _firstGroupStudentId,
            'subscriptionId': _crossPayerSubscriptionId,
          },
          {
            'clientId': _secondGroupStudentId,
            'settlementTypeKey': 'partially_paid_lesson_alt',
            'chargeDurationMinutes': 25,
            'chargeType': 'personal_account',
            'payerStudentId': _secondGroupStudentId,
            'basePriceMinor': '100000',
            'discount': {
              'type': 'percent',
              'percent': 12.5,
              'reason': 'Семейная скидка',
            },
            'surcharge': {'amountMinor': '5000', 'reason': 'Материалы'},
          },
        ],
        'teacherCompensationRuleKey': 'percent',
        'teacherCompensationValueMinor': '7500',
        'teacherCreditedDurationMinutes': 41,
        'teacherCompensationSource': 'manual',
      });
    },
  );

  testWidgets('legacy stored subscription reopens without a funding source', (
    tester,
  ) async {
    final api = _GroupLessonDecisionApi(operationKey: 'settlement-correction');
    await _openStoredDecision(
      tester,
      api: api,
      operation: LessonDecisionOperation.correction,
      lesson: const {
        'id': _groupLessonId,
        'version': 4,
        'branchId': _branchId,
        'studentId': _firstGroupStudentId,
        'studentName': 'Анна Иванова',
        'durationMinutes': 60,
        'scheduledAt': '2026-08-13T09:00:00.000Z',
        'financialDecision': {
          'settlementTypeKey': 'partially_paid_lesson',
          'teacherCompensationRuleKey': 'percent',
          'teacherCompensationValueMinor': '7500',
          'teacherCreditedDurationMinutes': 41,
          'teacherCompensationSource': 'manual',
          'clientDecisions': [
            {
              'clientId': _firstGroupStudentId,
              'chargeDurationMinutes': 0,
              'payerStudentId': _firstGroupStudentId,
              'subscriptionId': _crossPayerSubscriptionId,
            },
          ],
        },
      },
    );

    expect(
      find.byKey(
        const Key('lesson-decision-charge-type-$_firstGroupStudentId'),
      ),
      findsNothing,
    );
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(
              const Key('lesson-decision-subscription-$_firstGroupStudentId'),
            ),
          )
          .initialValue,
      _crossPayerSubscriptionId,
    );
    expect(find.textContaining('Семейный абонемент'), findsOneWidget);
    await _previewStoredDecision(tester, 'Старый формат без изменений');
    expect(
      (api.previews.single['financialDecision'] as Map)['clientDecisions'],
      [
        {
          'clientId': _firstGroupStudentId,
          'chargeDurationMinutes': 0,
          'payerStudentId': _firstGroupStudentId,
          'subscriptionId': _crossPayerSubscriptionId,
        },
      ],
    );
  });

  for (final surfaceCase in const [
    (width: 390.0, platform: TargetPlatform.android, mobile: true),
    (width: 1440.0, platform: TargetPlatform.windows, mobile: false),
  ]) {
    testWidgets(
      'lesson editor uses the shared adaptive surface at ${surfaceCase.width.toInt()}',
      (tester) async {
        tester.view.physicalSize = Size(surfaceCase.width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: surfaceCase.platform),
            home: Scaffold(
              body: Builder(
                builder: (context) => FilledButton(
                  onPressed: () => showLessonEditorSurface(
                    context,
                    title: 'Новое занятие',
                    editor: (_) => const SizedBox(
                      key: Key('adaptive-lesson-editor-body'),
                      height: 640,
                    ),
                  ),
                  child: const Text('Открыть редактор'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Открыть редактор'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(
            ValueKey(
              surfaceCase.mobile ? 'magic-sheet-mobile' : 'magic-sheet-desktop',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('magic-sheet-handle')),
          surfaceCase.mobile ? findsOneWidget : findsNothing,
        );
        expect(find.byTooltip('Закрыть'), findsOneWidget);
        expect(
          find.byKey(const Key('magic-sheet-body-scroll')),
          findsOneWidget,
        );

        await tester.tap(find.byTooltip('Закрыть'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('adaptive-lesson-editor-body')),
          findsNothing,
        );
      },
    );
  }

  testWidgets('dirty mobile editor asks before swipe close', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showLessonEditorSurface(
                context,
                title: 'Изменить занятие',
                editor: (_) => const LessonEditorDismissGuard(
                  isDirty: true,
                  child: SizedBox(height: 640),
                ),
              ),
              child: const Text('Открыть грязную форму'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Открыть грязную форму'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('magic-sheet-handle')),
      const Offset(0, 260),
    );
    await tester.pumpAndSettle();

    expect(find.text('Отменить изменения?'), findsOneWidget);
    expect(find.byKey(const Key('magic-sheet-mobile')), findsNWidgets(2));
    await tester.tap(find.text('Остаться'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('magic-sheet-mobile')), findsOneWidget);
  });
}

Future<void> _openStoredDecision(
  WidgetTester tester, {
  required _GroupLessonDecisionApi api,
  required LessonDecisionOperation operation,
  required Map<String, dynamic> lesson,
}) async {
  tester.view.physicalSize = const Size(1500, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showLessonDecisionFlow(
              context,
              crm: MagicCrmService(api),
              operation: operation,
              lesson: lesson,
              successor: operation == LessonDecisionOperation.reschedule
                  ? _successor
                  : null,
              canManageTeacherCompensation: true,
            ),
            child: const Text('Открыть сохранённый расчёт'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Открыть сохранённый расчёт'));
  await tester.pumpAndSettle();
}

Future<void> _previewStoredDecision(WidgetTester tester, String reason) async {
  await tester.enterText(
    find.byKey(const Key('lesson-decision-reason')),
    reason,
  );
  final submit = find.byKey(const Key('lesson-decision-submit'));
  await tester.ensureVisible(submit);
  await tester.tap(submit);
  await tester.pumpAndSettle();
}

String _fieldText(WidgetTester tester, Key key) => tester
    .widget<EditableText>(
      find.descendant(of: find.byKey(key), matching: find.byType(EditableText)),
    )
    .controller
    .text;
