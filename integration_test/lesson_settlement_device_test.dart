import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision_flow.dart';

import 'evidence_screenshot.dart';

const _branchId = '11111111-1111-4111-8111-111111111111';
const _teacherId = '22222222-2222-4222-8222-222222222222';
const _studentId = '33333333-3333-4333-8333-333333333333';
const _secondStudentId = '66666666-6666-4666-8666-666666666666';
const _roomId = '44444444-4444-4444-8444-444444444444';

class _LessonCreateApi extends MagicApiClient {
  _LessonCreateApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final lessonPosts = <Map<String, dynamic>>[];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    switch (path) {
      case '/crm/clients/resolve':
        return <String, dynamic>{
              'ref': {'type': 'student', 'id': _studentId},
              'label': 'Иван Прилежный',
              'branchId': _branchId,
              'lifecycleState': 'active',
              'tombstone': false,
            }
            as T;
      case '/crm/teachers':
        return <String, dynamic>{
              'items': [
                {
                  'id': _teacherId,
                  'firstName': 'Пётр',
                  'lastName': 'Педагогов',
                  'status': 'active',
                  'assignedBranches': const [
                    {'id': _branchId, 'name': 'Главный филиал'},
                  ],
                },
              ],
            }
            as T;
      case '/crm/branches':
        return <String, dynamic>{
              'items': const [
                {
                  'id': _branchId,
                  'name': 'Главный филиал',
                  'utcOffsetMinutes': 180,
                },
              ],
            }
            as T;
      case '/crm/rooms':
        return <String, dynamic>{
              'items': const [
                {'id': _roomId, 'name': 'Зал 1', 'branchId': _branchId},
              ],
            }
            as T;
      case '/crm/clients/search':
        return <String, dynamic>{
              'items': const [
                {
                  'ref': {'type': 'student', 'id': _studentId},
                  'label': 'Иван Прилежный',
                  'lifecycleState': 'active',
                  'tombstone': false,
                  'version': 1,
                  'links': <Map<String, dynamic>>[],
                },
              ],
            }
            as T;
      case '/crm/subscriptions':
        return <String, dynamic>{
              'items': const [
                {
                  'id': '55555555-5555-4555-8555-555555555555',
                  'studentId': _studentId,
                  'lessonsTotal': 12,
                  'lessonsUsed': 1,
                  'status': 'active',
                  'packageName': '12 занятий',
                  'packagePrice': 30000,
                },
              ],
            }
            as T;
      case '/crm/students/$_studentId/commerce':
        return <String, dynamic>{
              'projection': 'admin_scoped',
              'student': const {
                'studentId': _studentId,
                'accounts': <Map<String, dynamic>>[],
                'subscriptions': [
                  {
                    'id': '55555555-5555-4555-8555-555555555555',
                    'status': 'active',
                    'startsAt': '2026-08-01T00:00:00.000Z',
                    'expiresAt': null,
                    'units': {
                      'total': 12,
                      'used': 1,
                      'reserved': 0,
                      'paid': 12,
                      'available': 11,
                      'remaining': 11,
                    },
                    'financial': {
                      'actualPaidMinor': '3000000',
                      'obligationMinor': '3000000',
                      'debtMinor': '0',
                      'overpaymentMinor': '0',
                      'nextPaymentAt': null,
                    },
                    'terms': {
                      'displayName': '12 занятий',
                      'validityDays': null,
                      'basePriceMinor': '3000000',
                      'finalPriceMinor': '3000000',
                      'currencyCode': 'RUB',
                      'discount': {'type': 'none'},
                      'surcharge': {'type': 'none'},
                    },
                    'installments': <Map<String, dynamic>>[],
                  },
                ],
                'movements': <Map<String, dynamic>>[],
                'technicalHistory': <Map<String, dynamic>>[],
                'lessonBalance': {
                  'activeSubscriptionCount': 1,
                  'total': 12,
                  'used': 1,
                  'reserved': 0,
                  'paid': 12,
                  'available': 11,
                  'debts': <Map<String, dynamic>>[],
                  'nextPaymentAt': null,
                  'expiresAt': null,
                },
              },
            }
            as T;
      case '/crm/configuration/lesson-decisions':
        return <String, dynamic>{
              'settlementTypes': const [
                {
                  'stableKey': 'lesson',
                  'label': 'Занятие',
                  'colorToken': 'success',
                  'allowedContexts': ['settle'],
                  'active': true,
                  'order': 0,
                  'hourShareBasisPoints': 10000,
                  'fixedPenaltyMinor': '0',
                },
                {
                  'stableKey': 'free_lesson',
                  'label': 'Бесплатное занятие',
                  'colorToken': 'warning',
                  'allowedContexts': ['settle'],
                  'active': true,
                  'order': 1,
                  'hourShareBasisPoints': 0,
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
                  'label': 'Стандартная ставка',
                  'mode': 'standard',
                  'value': '0',
                  'active': true,
                  'order': 1,
                },
              ],
            }
            as T;
      default:
        throw UnimplementedError('GET $path');
    }
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/lessons/constraints/preview') {
      return <String, dynamic>{'valid': true, 'violations': const []} as T;
    }
    if (path == '/crm/lessons') {
      lessonPosts.add(Map<String, dynamic>.from(data as Map));
      return <String, dynamic>{'id': 'lesson-device-created', 'version': 1}
          as T;
    }
    throw UnimplementedError('POST $path');
  }
}

class _SettlementApi extends MagicApiClient {
  _SettlementApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final previews = <Map<String, dynamic>>[];
  final commits = <Map<String, dynamic>>[];
  final methods = <String>[];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/configuration/lesson-decisions') {
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
              {
                'stableKey': 'free_lesson',
                'label': 'Бесплатное занятие',
                'colorToken': 'warning',
                'allowedContexts': ['settle'],
                'active': true,
                'order': 2,
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
                'value': '85000',
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
    throw UnimplementedError('GET $path');
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path.endsWith('/preview')) {
      final body = Map<String, dynamic>.from(data as Map);
      previews.add(body);
      final decision = Map<String, dynamic>.from(
        body['financialDecision'] as Map,
      );
      final clientDecisions = decision['clientDecisions'];
      final isGroupDecision =
          clientDecisions is List && clientDecisions.isNotEmpty;
      final ruleKey = decision['teacherCompensationRuleKey']?.toString();
      final ruleLabel = switch (ruleKey) {
        'standard' => 'Полная стандартная ставка',
        'percent' => 'Процент ставки',
        'fixed' => 'Фиксированная сумма',
        'hourly' => 'Почасовая сумма',
        _ => 'Не оплачивать',
      };
      final amountMinor = switch (ruleKey) {
        'hourly' ||
        'fixed' => decision['teacherCompensationValueMinor']?.toString() ?? '0',
        'percent' => '43750',
        'standard' => '70000',
        _ => '0',
      };
      return <String, dynamic>{
            'canConfirm': true,
            'financialPreview': {
              'clientFacts': isGroupDecision
                  ? const [
                      {
                        'clientId': _studentId,
                        'settlementLabel': 'Занятие',
                        'amountMinor': '80000',
                        'units': '1.00',
                      },
                      {
                        'clientId': _secondStudentId,
                        'settlementLabel': 'Частично оплачено',
                        'amountMinor': '40000',
                        'units': '0.50',
                      },
                    ]
                  : const [
                      {
                        'settlementLabel': 'Бесплатное занятие',
                        'amountMinor': '0',
                        'units': '0.00',
                      },
                    ],
              'teacherFact': {
                'compensationRuleLabel': ruleLabel,
                'amountMinor': amountMinor,
              },
            },
            'previewToken': 'device-signed-preview',
          }
          as T;
    }
    throw UnimplementedError('POST $path');
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
    methods.add('POST $path');
    return <String, dynamic>{'lessonId': 'lesson-1', 'version': 8} as T;
  }

  @override
  Future<T> request<T>(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
    ResponseType? responseType,
    MagicMutationIdentity? mutationIdentity,
  }) async {
    if (method == 'PUT' && path.endsWith('/planned-settlement')) {
      commits.add(Map<String, dynamic>.from(data as Map));
      methods.add('$method $path');
      return <String, dynamic>{'lessonId': 'lesson-1', 'version': 8} as T;
    }
    throw UnimplementedError('$method $path');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('lesson create keeps settlement pay and funding independent', (
    tester,
  ) async {
    await initializeDateFormatting('ru');
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _LessonCreateApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          magicApiClientProvider.overrideWithValue(api),
          capabilitySnapshotProvider.overrideWith(
            (ref) async => const CapabilitySnapshot(
              accountId: 'director-device',
              role: 'director',
              accessVersion: 1,
              capabilities: {'commerce.teacher_payroll.write'},
              scopes: {},
            ),
          ),
        ],
        child: RepaintBoundary(
          key: evidenceRootKey,
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: FilledButton(
                    onPressed: () => CreateLessonDialog.show(
                      context,
                      clientType: 'student',
                      clientId: _studentId,
                      clientName: 'Иван Прилежный',
                      initialBranchId: _branchId,
                      initialRoomId: _roomId,
                    ),
                    child: const Text('Создать занятие'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Создать занятие'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SearchablePickerField>(
            find.byKey(const ValueKey('lesson-teacher-field')),
          )
          .items
          .map((item) => item.label),
      contains('Пётр Педагогов'),
    );
    await _chooseLessonReference(
      tester,
      const ValueKey('lesson-teacher-field'),
      'Пётр Педагогов',
    );
    expect(find.text('Иван Прилежный'), findsWidgets);
    expect(find.text('Пётр Педагогов'), findsWidgets);
    expect(find.text('Зал 1'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('lesson-trial-toggle')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('lesson-trial-toggle')),
          )
          .value,
      isTrue,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('lesson-settlement-type-field')),
    );
    await tester.tap(
      find.byKey(const ValueKey('lesson-settlement-type-field')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Занятие').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('lesson-compensation-rule-field')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Стандартная ставка').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('lesson-client-charge-type-$_studentId')),
    );
    await tester.tap(
      find.byKey(const ValueKey('lesson-client-charge-type-$_studentId')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('С личного счёта').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('lesson-client-charge-type-$_studentId')),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('lesson-client-price-$_studentId')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('lesson-client-price-$_studentId')),
      '1500',
    );
    await tester.pumpAndSettle();

    expect(find.text('Тип списания *'), findsOneWidget);
    expect(find.text('Правило оплаты преподавателю *'), findsOneWidget);
    expect(find.text('Источник средств *'), findsOneWidget);
    await captureEvidence(tester, 'lesson-create-required-financial-choices');
    await captureEvidence(tester, 'lesson-trial-paid-personal-account');

    await tester.ensureVisible(find.text('Создать'));
    await tester.tap(find.text('Создать'));
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(api.lessonPosts, hasLength(1));
    final financial = api.lessonPosts.single['financialDecision'] as Map;
    expect(financial['settlementTypeKey'], 'lesson');
    expect(financial['teacherCompensationRuleKey'], 'standard');
    expect(
      (financial['clientDecisions'] as List).single,
      allOf(
        containsPair('clientId', _studentId),
        containsPair('payerStudentId', _studentId),
        containsPair('chargeType', 'personal_account'),
        containsPair('basePriceMinor', '150000'),
      ),
    );
    expect(api.lessonPosts.single['clientChargeType'], 'personal_account');
    expect(api.lessonPosts.single['isTrial'], isTrue);
    expect(api.lessonPosts.single, isNot(contains('subscriptionId')));
    expect(find.text('Занятие создано'), findsOneWidget);
    await captureEvidence(tester, 'lesson-create-financial-committed');
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
    debugPrint('V7_LESSON_CREATE_FINANCIAL_DEVICE_PASS');
  });

  testWidgets('subscription default and free no-charge stay explicit', (
    tester,
  ) async {
    await initializeDateFormatting('ru');
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _LessonCreateApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          magicApiClientProvider.overrideWithValue(api),
          capabilitySnapshotProvider.overrideWith(
            (ref) async => const CapabilitySnapshot(
              accountId: 'director-device',
              role: 'director',
              accessVersion: 1,
              capabilities: {'commerce.teacher_payroll.write'},
              scopes: {},
            ),
          ),
        ],
        child: RepaintBoundary(
          key: evidenceRootKey,
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: FilledButton(
                    onPressed: () => CreateLessonDialog.show(
                      context,
                      clientType: 'student',
                      clientId: _studentId,
                      clientName: 'Иван Прилежный',
                      initialBranchId: _branchId,
                      initialRoomId: _roomId,
                    ),
                    child: const Text('Создать занятие'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Создать занятие'));
    await tester.pumpAndSettle();
    await _chooseLessonReference(
      tester,
      const ValueKey('lesson-teacher-field'),
      'Пётр Педагогов',
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('lesson-client-charge-type-$_studentId')),
    );
    expect(find.text('С абонемента'), findsOneWidget);
    await captureEvidence(tester, 'lesson-funding-subscription-default');
    await tester.tap(
      find.byKey(const ValueKey('lesson-client-charge-type-$_studentId')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Без списания'), findsNothing);
    await tester.tap(find.text('С абонемента').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('lesson-settlement-type-field')),
    );
    await tester.tap(
      find.byKey(const ValueKey('lesson-settlement-type-field')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Бесплатное занятие').last);
    await tester.pumpAndSettle();
    // Funding is now an explicit per-payer choice, independent of the common
    // settlement type. A free type makes the no-charge option available.
    await tester.ensureVisible(
      find.byKey(const ValueKey('lesson-client-charge-type-$_studentId')),
    );
    await tester.tap(
      find.byKey(const ValueKey('lesson-client-charge-type-$_studentId')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Без списания').last);
    await tester.pumpAndSettle();
    expect(find.text('Без списания'), findsOneWidget);
    await captureEvidence(tester, 'lesson-funding-free-no-charge');

    await tester.ensureVisible(find.text('Создать'));
    await tester.tap(find.text('Создать'));
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(api.lessonPosts, hasLength(1));
    expect(api.lessonPosts.single['clientChargeType'], 'none');
    expect(api.lessonPosts.single['clientChargeValue'], 0);
    expect(api.lessonPosts.single, isNot(contains('subscriptionId')));
    final financial = api.lessonPosts.single['financialDecision'] as Map;
    expect(financial['settlementTypeKey'], 'free_lesson');
    expect(financial['teacherCompensationRuleKey'], 'standard');
    expect(
      (financial['clientDecisions'] as List).single,
      containsPair('chargeType', 'none'),
    );
    expect(tester.takeException(), isNull);
    debugPrint('V7_LESSON_FUNDING_DEVICE_PASS');
  });

  testWidgets('planned edit and terminal correction keep one signed flow', (
    tester,
  ) async {
    await initializeDateFormatting('ru');
    for (final operation in const [
      LessonDecisionOperation.plannedSettlement,
      LessonDecisionOperation.correction,
    ]) {
      final api = _SettlementApi();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showLessonDecisionFlow(
                  context,
                  crm: MagicCrmService(api),
                  canManageTeacherCompensation: true,
                  operation: operation,
                  lesson: const {
                    'id': 'lesson-1',
                    'version': 7,
                    'branch_id': 'branch-1',
                    'scheduled_at': '2026-08-10T07:00:00.000Z',
                  },
                ),
                child: const Text('Открыть расчёт'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Открыть расчёт'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('lesson-decision-reason')),
        'Проверено сотрудником на устройстве',
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
      await tester.ensureVisible(
        find.byKey(const Key('lesson-decision-submit')),
      );
      await tester.tap(find.byKey(const Key('lesson-decision-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lesson-decision-preview')), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('lesson-decision-submit')),
      );
      await tester.tap(find.byKey(const Key('lesson-decision-submit')));
      await tester.pumpAndSettle();

      expect(api.previews.single, isNot(contains('reasonCode')));
      expect(api.commits.single, containsPair('confirm', true));
      expect(
        api.methods.single,
        startsWith(
          operation == LessonDecisionOperation.plannedSettlement
              ? 'PUT '
              : 'POST ',
        ),
      );
      expect(tester.takeException(), isNull);
    }
    debugPrint('V7_LESSON_SETTLEMENT_DEVICE_PASS');
  });

  testWidgets('five teacher pay rules and reasoned override stay usable', (
    tester,
  ) async {
    await initializeDateFormatting('ru');
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _SettlementApi();
    await tester.pumpWidget(
      RepaintBoundary(
        key: evidenceRootKey,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showLessonDecisionFlow(
                    context,
                    crm: MagicCrmService(api),
                    canManageTeacherCompensation: true,
                    operation: LessonDecisionOperation.plannedSettlement,
                    lesson: const {
                      'id': 'lesson-five-pay-rules',
                      'version': 7,
                      'branch_id': _branchId,
                      'scheduled_at': '2026-08-12T07:00:00.000Z',
                    },
                  ),
                  child: const Text('Открыть оплату'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть оплату'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('lesson-decision-reason')), '');
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
    for (final label in const [
      'Не оплачивать',
      'Полная стандартная ставка',
      'Процент ставки',
      'Фиксированная сумма',
      'Почасовая сумма',
    ]) {
      expect(find.text(label), findsWidgets);
    }
    await captureEvidence(tester, 'teacher-pay-five-rule-catalog');
    await tester.tap(find.text('Почасовая сумма').last);
    await tester.pumpAndSettle();
    final valueField = find.byKey(
      const Key('lesson-decision-compensation-value'),
    );
    await tester.ensureVisible(valueField);
    await tester.enterText(valueField, '1250');
    await tester.ensureVisible(find.byKey(const Key('lesson-decision-submit')));
    await tester.tap(find.byKey(const Key('lesson-decision-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Укажите причину'), findsOneWidget);
    expect(api.previews, isEmpty);
    await captureEvidence(tester, 'teacher-pay-override-reason-required');

    await tester.enterText(
      find.byKey(const Key('lesson-decision-reason')),
      'Почасовой override согласован директором',
    );
    await tester.tap(find.byKey(const Key('lesson-decision-submit')));
    await tester.pumpAndSettle();
    expect(api.previews, hasLength(1));
    expect(api.previews.single['financialDecision'], {
      'settlementTypeKey': 'free_lesson',
      'teacherCompensationRuleKey': 'hourly',
      'teacherCompensationValueMinor': '125000',
    });
    expect(
      api.previews.single['reasonText'],
      'Почасовой override согласован директором',
    );
    expect(find.textContaining('Почасовая сумма'), findsWidgets);
    expect(find.textContaining('250,00 ₽'), findsOneWidget);
    await captureEvidence(tester, 'teacher-pay-hourly-override-preview');
    expect(tester.takeException(), isNull);
    debugPrint('V7_TEACHER_PAY_RULES_DEVICE_PASS');
  });

  testWidgets(
    'group common decision and named participant override stay usable',
    (tester) async {
      await initializeDateFormatting('ru');
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _SettlementApi();
      await tester.pumpWidget(
        RepaintBoundary(
          key: evidenceRootKey,
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: FilledButton(
                    onPressed: () => showLessonDecisionFlow(
                      context,
                      crm: MagicCrmService(api),
                      canManageTeacherCompensation: true,
                      operation: LessonDecisionOperation.plannedSettlement,
                      lesson: const {
                        'id': 'lesson-group-decision',
                        'version': 7,
                        'branch_id': _branchId,
                        'group_id': 'group-device',
                        'scheduled_at': '2026-08-13T10:00:00.000Z',
                        'group_participants': [
                          {
                            'clientId': _studentId,
                            'clientName': 'Анна Иванова',
                          },
                          {
                            'clientId': _secondStudentId,
                            'clientName': 'Борис Петров',
                          },
                        ],
                      },
                    ),
                    child: const Text('Открыть групповой расчёт'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Открыть групповой расчёт'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('lesson-decision-reason')),
        'Анне начисляется полное занятие',
      );
      await tester.tap(find.byKey(const Key('lesson-decision-settlement')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Частично оплачено').last);
      await tester.pumpAndSettle();
      final firstOverride = find.byKey(
        const Key('lesson-decision-client-$_studentId'),
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
      await captureEvidence(tester, 'group-settlement-common-client-override');
      await tester.ensureVisible(
        find.byKey(const Key('lesson-decision-submit')),
      );
      await tester.tap(find.byKey(const Key('lesson-decision-submit')));
      await tester.pumpAndSettle();

      expect(api.previews.single['financialDecision'], {
        'settlementTypeKey': 'partially_paid_lesson',
        'clientDecisions': [
          {'clientId': _studentId, 'settlementTypeKey': 'lesson'},
        ],
        'teacherCompensationRuleKey': 'standard',
      });
      expect(find.textContaining('Анна Иванова: Занятие'), findsOneWidget);
      expect(
        find.textContaining('Борис Петров: Частично оплачено'),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const Key('lesson-decision-preview')),
      );
      await captureEvidence(tester, 'group-settlement-named-facts-preview');

      await tester.ensureVisible(
        find.byKey(const Key('lesson-decision-submit')),
      );
      await tester.tap(find.byKey(const Key('lesson-decision-submit')));
      await tester.pumpAndSettle();
      expect(api.commits, hasLength(1));
      expect(api.commits.single['financialDecision'], {
        'settlementTypeKey': 'partially_paid_lesson',
        'clientDecisions': [
          {'clientId': _studentId, 'settlementTypeKey': 'lesson'},
        ],
        'teacherCompensationRuleKey': 'standard',
      });
      expect(tester.takeException(), isNull);
      debugPrint('V7_GROUP_SETTLEMENT_OVERRIDE_DEVICE_PASS');
    },
  );
}

Future<void> _chooseLessonReference(
  WidgetTester tester,
  Key field,
  String label,
) async {
  final picker = find.byKey(field);
  final widget = tester.widget<SearchablePickerField>(picker);
  final option = widget.items.singleWhere((item) => item.label == label);
  widget.onSelected(option);
  await tester.pumpAndSettle();
  expect(tester.widget<SearchablePickerField>(picker).selectedId, _teacherId);
}
