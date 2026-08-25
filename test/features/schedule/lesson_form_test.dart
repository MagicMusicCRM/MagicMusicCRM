import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision_flow.dart';
import 'package:magic_music_crm/core/models/lesson_schedule_analysis.dart';

const _teacherId = '22222222-2222-2222-2222-222222222222';
const _replacementTeacherId = '22222222-2222-4222-8222-222222222223';
const _inactiveTeacherId = '22222222-2222-4222-8222-222222222224';
const _foreignTeacherId = '22222222-2222-4222-8222-222222222225';
const _studentId = '33333333-3333-3333-3333-333333333333';
const _leadId = '77777777-7777-7777-7777-777777777777';
const _branchId = '11111111-1111-1111-1111-111111111111';
const _roomId = '55555555-5555-5555-5555-555555555555';
const _replacementRoomId = '55555555-5555-4555-8555-555555555556';
const _foreignRoomId = '55555555-5555-4555-8555-555555555557';
const _foreignBranchId = '11111111-1111-4111-8111-111111111112';
const _conflictId = '44444444-4444-4444-4444-444444444444';
const _groupId = '88888888-8888-4888-8888-888888888888';

const _manualCompensationCatalog = <String, dynamic>{
  'settlementTypes': [
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
  ],
  'teacherCompensationRules': [
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
    {
      'stableKey': 'percent',
      'label': 'Процент ставки',
      'mode': 'percent',
      'value': '1000',
      'active': true,
      'order': 2,
    },
    {
      'stableKey': 'fixed',
      'label': 'Фиксированная сумма',
      'mode': 'fixed',
      'value': '90000',
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
};

Map<String, dynamic> _freePreview() => {'valid': true, 'violations': const []};

Map<String, dynamic> _editableLesson({bool group = false}) => {
  'id': '66666666-6666-6666-6666-666666666666',
  'version': 7,
  if (group) ...{
    'group_id': _groupId,
    'group_name': 'Ансамбль Север',
    'group_participants': const [
      {'clientId': _studentId, 'clientName': 'Иван Прилежный'},
    ],
  } else ...{
    'student_id': _studentId,
    'student_name': 'Иван Прилежный',
  },
  'teacher_id': _teacherId,
  'branch_id': _branchId,
  'room_id': _roomId,
  'scheduled_at': '2026-07-18T07:00:00.000Z',
  'duration_minutes': 60,
  'is_trial': true,
  'snapshot_trial': true,
  'completion_type': 'custom.success',
  'client_charge_type': group ? 'personal_account' : 'none',
  'client_charge_value': group ? 800 : 0,
  'teacher_compensation_type': 'none',
  'teacher_compensation_value': 0,
  'settlement_type_key': 'free_lesson',
  'teacher_compensation_rule_key': 'none',
};

Map<String, dynamic> _busyPreview() => {
  'valid': false,
  'violations': [
    {
      'code': 'TEACHER_UNAVAILABLE',
      'resource': {'type': 'teacher', 'id': _teacherId},
      'conflictingLessonIds': const [],
      'ruleIds': ['teacher-rule-1'],
    },
    {
      'code': 'CLIENT_OVERLAP',
      'resource': {'type': 'client', 'id': _studentId},
      'conflictingLessonIds': [_conflictId],
      'ruleIds': const [],
    },
    {
      'code': 'ROOM_OVERLAP',
      'resource': {'type': 'room', 'id': _roomId},
      'conflictingLessonIds': [_conflictId],
      'ruleIds': const [],
    },
  ],
};

class _FakeApiClient extends MagicApiClient {
  _FakeApiClient({
    this.preview,
    this.previewError,
    this.createError,
    this.subscriptions = const [],
    this.decisionCatalog,
    this.decisionViolations = const [],
    this.teacherCurrentRate,
  }) : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  Map<String, dynamic>? preview;
  Object? previewError;
  MagicApiException? createError;
  final List<Map<String, dynamic>> subscriptions;
  final Map<String, dynamic>? decisionCatalog;
  final List<Map<String, dynamic>> decisionViolations;
  final num? teacherCurrentRate;
  Completer<void>? createGate;
  final constraintPreviews = <Map<String, dynamic>>[];
  final lessonPosts = <Map<String, dynamic>>[];
  final decisionPreviews = <Map<String, dynamic>>[];
  final decisionCommits = <Map<String, dynamic>>[];
  final decisionCommitMethods = <String>[];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    switch (path) {
      case '/crm/teachers':
        return <String, dynamic>{
              'items': [
                {
                  'id': _teacherId,
                  'firstName': 'Пётр',
                  'lastName': 'Педагогов',
                  'status': 'active',
                  if (teacherCurrentRate != null)
                    'currentRate': teacherCurrentRate,
                  'assignedBranches': const [
                    {'id': _branchId, 'name': 'Главный филиал'},
                  ],
                },
                {
                  'id': _replacementTeacherId,
                  'firstName': 'Мария',
                  'lastName': 'Сменова',
                  'status': 'active',
                  'assignedBranches': const [
                    {'id': _branchId, 'name': 'Главный филиал'},
                  ],
                },
                {
                  'id': _inactiveTeacherId,
                  'firstName': 'Ирина',
                  'lastName': 'Неактивная',
                  'status': 'inactive',
                  'assignedBranches': const [
                    {'id': _branchId, 'name': 'Главный филиал'},
                  ],
                },
                {
                  'id': _foreignTeacherId,
                  'firstName': 'Олег',
                  'lastName': 'Другой',
                  'status': 'active',
                  'assignedBranches': const [
                    {'id': _foreignBranchId, 'name': 'Другой филиал'},
                  ],
                },
              ],
            }
            as T;
      case '/crm/branches':
        return <String, dynamic>{
              'items': [
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
              'items': [
                {'id': _roomId, 'name': 'Зал 1', 'branchId': _branchId},
                {
                  'id': _replacementRoomId,
                  'name': 'Зал 2',
                  'branchId': _branchId,
                },
                {
                  'id': _foreignRoomId,
                  'name': 'Чужой зал',
                  'branchId': _foreignBranchId,
                },
              ],
            }
            as T;
      case '/crm/clients/search':
        return <String, dynamic>{
              'items': [
                {
                  'ref': {'type': 'student', 'id': _studentId},
                  'label': 'Иван Прилежный',
                  'lifecycleState': 'active',
                  'tombstone': false,
                  'version': 1,
                  'links': const [],
                },
                {
                  'ref': {'type': 'lead', 'id': _leadId},
                  'label': 'Анна Лидова',
                  'lifecycleState': 'active',
                  'tombstone': false,
                  'version': 1,
                  'links': const [],
                },
              ],
            }
            as T;
      case '/crm/clients/resolve':
        final type = queryParameters?['type']?.toString();
        final id = queryParameters?['id']?.toString();
        return <String, dynamic>{
              'ref': {'type': type, 'id': id},
              'label': type == 'lead' ? 'Анна Лидова' : 'Иван Прилежный',
              'branchId': _branchId,
              'lifecycleState': 'active',
              'tombstone': false,
              'version': 1,
              'links': const [],
            }
            as T;
      case '/crm/subscriptions':
        return <String, dynamic>{'items': subscriptions} as T;
      case '/crm/students/$_studentId/commerce':
        return <String, dynamic>{
              'projection': 'admin_scoped',
              'student': {
                'studentId': _studentId,
                'accounts': const [],
                'subscriptions': [
                  for (final item in subscriptions)
                    {
                      'id': item['id'],
                      'status': item['status'],
                      'startsAt': '2026-08-01T00:00:00.000Z',
                      'expiresAt': null,
                      'units': {
                        'total': item['lessonsTotal'],
                        'used': item['lessonsUsed'],
                        'reserved': 0,
                        'paid': item['lessonsTotal'],
                        'available':
                            (item['lessonsTotal'] as num) -
                            (item['lessonsUsed'] as num),
                        'remaining':
                            (item['lessonsTotal'] as num) -
                            (item['lessonsUsed'] as num),
                      },
                      'financial': const {
                        'actualPaidMinor': '3000000',
                        'obligationMinor': '3000000',
                        'debtMinor': '0',
                        'overpaymentMinor': '0',
                        'nextPaymentAt': null,
                      },
                      'terms': {
                        'displayName': item['packageName'],
                        'validityDays': null,
                        'basePriceMinor': '3000000',
                        'finalPriceMinor': '3000000',
                        'currencyCode': 'RUB',
                        'discount': const {'type': 'none'},
                        'surcharge': const {'type': 'none'},
                      },
                      'installments': const [],
                    },
                ],
                'movements': const [],
                'technicalHistory': const [],
                'lessonBalance': {
                  'activeSubscriptionCount': subscriptions.length,
                  'total': 12,
                  'used': 1,
                  'reserved': 0,
                  'paid': 12,
                  'available': 11,
                  'debts': const [],
                  'nextPaymentAt': null,
                  'expiresAt': null,
                },
              },
            }
            as T;
      case '/crm/configuration/lesson-decisions':
        return (decisionCatalog ??
                <String, dynamic>{
                  'settlementTypes': const [
                    {
                      'stableKey': 'standard_lesson',
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
                      'allowedContexts': ['cancel', 'reschedule', 'settle'],
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
                })
            as T;
      default:
        return <String, dynamic>{'items': const []} as T;
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
      constraintPreviews.add(Map<String, dynamic>.from(data as Map));
      if (previewError case final error?) throw error;
      return (preview ?? _freePreview()) as T;
    }
    if (path == '/crm/lessons') {
      lessonPosts.add(Map<String, dynamic>.from(data as Map));
      await createGate?.future;
      if (createError case final error?) throw error;
      return <String, dynamic>{'id': 'lesson-1', 'version': 1} as T;
    }
    if (path.endsWith('/reschedule/preview') ||
        path.endsWith('/planned-settlement/preview') ||
        path.endsWith('/settlement-correction/preview')) {
      decisionPreviews.add(Map<String, dynamic>.from(data as Map));
      return <String, dynamic>{
            'operation': 'reschedule',
            'source': {
              'id': '66666666-6666-6666-6666-666666666666',
              'version': 7,
              'state': 'scheduled',
            },
            'successor': const {},
            'financialDecision': const {},
            'violations': decisionViolations,
            'canConfirm': decisionViolations.isEmpty,
            'confirmRequired': true,
            if (decisionViolations.isEmpty)
              'financialPreview': {
                'clientFacts': const [
                  {
                    'settlementTypeKey': 'free_lesson',
                    'settlementLabel': 'Бесплатное занятие',
                    'amountMinor': '0',
                    'units': '0.00',
                  },
                ],
                'teacherFact': const {
                  'compensationRuleKey': 'none',
                  'compensationRuleLabel': 'Не оплачивать',
                  'amountMinor': '0',
                },
              },
            if (decisionViolations.isEmpty)
              'previewToken': 'signed-lesson-preview',
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
    if (path.endsWith('/reschedule') ||
        path.endsWith('/settlement-correction')) {
      decisionCommits.add(Map<String, dynamic>.from(data as Map));
      decisionCommitMethods.add('POST $path');
      return <String, dynamic>{'transitionId': 'transition-1'} as T;
    }
    throw UnimplementedError('POST IDEMPOTENT $path');
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
      decisionCommits.add(Map<String, dynamic>.from(data as Map));
      decisionCommitMethods.add('$method $path');
      expect(mutationIdentity, isNotNull);
      return <String, dynamic>{'lessonId': 'lesson-1', 'version': 8} as T;
    }
    throw UnimplementedError('$method $path');
  }
}

Widget _host(
  _FakeApiClient client, {
  Map<String, dynamic>? lesson,
  String? leadId,
  String? leadName,
  String? initialBranchId,
  bool initialIsTrial = false,
  ValueNotifier<bool?>? dialogResult,
}) {
  return ProviderScope(
    overrides: [magicApiClientProvider.overrideWithValue(client)],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () async {
                final result = await CreateLessonDialog.show(
                  context,
                  lesson: lesson,
                  leadId: leadId,
                  leadName: leadName,
                  initialBranchId: initialBranchId,
                  initialIsTrial: initialIsTrial,
                );
                dialogResult?.value = result;
              },
              child: const Text('открыть диалог'),
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _decisionHost(_FakeApiClient client, LessonDecisionOperation operation) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => FilledButton(
          onPressed: () => showLessonDecisionFlow(
            context,
            api: client,
            operation: operation,
            lesson: const {
              'id': '66666666-6666-6666-6666-666666666666',
              'version': 7,
              'branch_id': _branchId,
              'scheduled_at': '2026-08-10T07:00:00.000Z',
            },
          ),
          child: const Text('открыть расчёт'),
        ),
      ),
    ),
  );
}

Future<void> _pumpDialog(
  WidgetTester tester,
  _FakeApiClient client, {
  Map<String, dynamic>? lesson,
  String? leadId,
  String? leadName,
  String? initialBranchId,
  bool initialIsTrial = false,
  ValueNotifier<bool?>? dialogResult,
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _host(
      client,
      lesson: lesson,
      leadId: leadId,
      leadName: leadName,
      initialBranchId: initialBranchId,
      initialIsTrial: initialIsTrial,
      dialogResult: dialogResult,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('открыть диалог'));
  await tester.pumpAndSettle();
  final formContext = tester.element(find.textContaining('занятие').first);
  expect(ModalRoute.of(formContext)?.settings.name, 'lesson-editor');
  expect(find.byType(BackButton), findsOneWidget);
  expect(
    find.ancestor(
      of: find.byType(AlertDialog),
      matching: find.byType(SafeArea),
    ),
    findsOneWidget,
  );
}

Future<void> _selectRequiredResources(
  WidgetTester tester, {
  required String clientName,
}) async {
  await _chooseSearchable(
    tester,
    const ValueKey('lesson-client-field'),
    clientName,
  );
  await _chooseSearchable(
    tester,
    const ValueKey('lesson-teacher-field'),
    'Пётр Педагогов',
  );
  await _chooseSearchable(tester, const ValueKey('lesson-room-field'), 'Зал 1');

  await tester.ensureVisible(
    find.byKey(const ValueKey('lesson-settlement-type-field')),
  );
  await tester.tap(find.byKey(const ValueKey('lesson-settlement-type-field')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Бесплатное занятие').last);
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey('lesson-compensation-rule-field')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Не оплачивать').last);
  await tester.pumpAndSettle();
}

Future<void> _chooseSearchable(
  WidgetTester tester,
  Key field,
  String option,
) async {
  await tester.ensureVisible(find.byKey(field));
  await tester.tap(find.byKey(field));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(Scrollbar).last,
      matching: find.text(option),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapCreate(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Создать'));
  await tester.tap(find.text('Создать'));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _moveEditableLessonToNextDay(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('lesson-date-field')));
  await tester.tap(find.byKey(const ValueKey('lesson-date-field')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('19'));
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  expect(find.text('19.07.2026'), findsOneWidget);
}

Future<void> _fillRescheduleDecision(
  WidgetTester tester, {
  required String reason,
}) async {
  await tester.ensureVisible(find.text('Перейти к расчёту'));
  await tester.tap(find.text('Перейти к расчёту'));
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.enterText(
    find.byKey(const Key('lesson-decision-reason')),
    reason,
  );
  await tester.tap(find.byKey(const Key('lesson-decision-settlement')));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text('Бесплатное занятие').last);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.ensureVisible(
    find.byKey(const Key('lesson-decision-compensation')),
  );
  await tester.tap(find.byKey(const Key('lesson-decision-compensation')));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text('Не оплачивать').last);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.ensureVisible(find.byKey(const Key('lesson-decision-submit')));
  await tester.tap(find.byKey(const Key('lesson-decision-submit')));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  test('every schedule constraint has a clear Russian title', () {
    const titles = {
      'INVALID_INTERVAL': 'Некорректное время занятия',
      'OUTSIDE_BRANCH_HOURS': 'Филиал закрыт в это время',
      'TEACHER_UNAVAILABLE': 'Преподаватель недоступен',
      'TEACHER_BRANCH_MISMATCH': 'Преподаватель не назначен в филиал',
      'ROOM_BRANCH_MISMATCH': 'Аудитория относится к другому филиалу',
      'TEACHER_OVERLAP': 'У преподавателя уже есть занятие',
      'CLIENT_OVERLAP': 'У клиента уже есть занятие',
      'ROOM_OVERLAP': 'Аудитория уже занята',
    };

    for (final entry in titles.entries) {
      final violation = LessonConstraintViolation.fromJson({
        'code': entry.key,
        'resource': const {'type': 'room', 'id': _foreignRoomId},
      });
      expect(violation.title, entry.value, reason: entry.key);
    }
  });

  test('Schedule Analyzer parses ranked replacement variants', () {
    final analysis = LessonScheduleAnalysis.fromJson({
      'valid': false,
      'violations': _busyPreview()['violations'],
      'suggestions': [
        {
          'kind': 'SAME_TIME_ROOM',
          'rank': 1,
          'score': 1000,
          'changes': {'roomId': _replacementRoomId, 'roomName': 'Зал 2'},
        },
      ],
    });

    expect(analysis.valid, isFalse);
    expect(analysis.violations, hasLength(3));
    expect(
      analysis.suggestions.single.title,
      'Свободная аудитория в то же время',
    );
    expect(analysis.suggestions.single.roomId, _replacementRoomId);
  });

  testWidgets('new lesson always opens at the required client field', (
    tester,
  ) async {
    await _pumpDialog(tester, _FakeApiClient());

    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView).first,
    );
    expect(scroll.controller?.keepScrollOffset, isFalse);
    expect(find.byKey(const ValueKey('lesson-client-field')), findsOneWidget);
  });

  testWidgets('new lesson uses the effective branch duration', (tester) async {
    final client = _FakeApiClient(
      decisionCatalog: const {
        'defaultLessonDurationMinutes': 75,
        'settlementTypes': [
          {
            'stableKey': 'free_lesson',
            'label': 'Бесплатное занятие',
            'colorToken': 'warning',
            'allowedContexts': ['settle'],
            'active': true,
            'order': 0,
            'hourShareBasisPoints': 0,
            'fixedPenaltyMinor': '0',
          },
        ],
        'teacherCompensationRules': [
          {
            'stableKey': 'none',
            'label': 'Не оплачивать',
            'mode': 'none',
            'value': '0',
            'active': true,
            'order': 0,
          },
        ],
      },
    );
    await _pumpDialog(tester, client);

    expect(
      tester
          .state<FormFieldState<int>>(
            find.byKey(const ValueKey('lesson-duration-field')),
          )
          .value,
      75,
    );
    expect(find.text('75 мин'), findsOneWidget);
  });

  testWidgets(
    'Lead preset previews and commits a trial with required resources and snapshot',
    (tester) async {
      final client = _FakeApiClient(teacherCurrentRate: 1250);
      final dialogResult = ValueNotifier<bool?>(null);
      addTearDown(dialogResult.dispose);
      await _pumpDialog(
        tester,
        client,
        leadId: _leadId,
        leadName: 'Анна Лидова',
        initialBranchId: _branchId,
        initialIsTrial: true,
        dialogResult: dialogResult,
      );

      expect(find.text('Пробное занятие'), findsWidgets);
      final clientField = tester.widget<SearchablePickerField>(
        find.byKey(const ValueKey('lesson-client-field')),
      );
      expect(clientField.selectedId, 'lead:$_leadId');
      expect(clientField.enabled, isFalse);
      expect(
        find.byKey(const ValueKey('lesson-branch-field:$_branchId')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('lesson-trial-toggle')),
            )
            .value,
        isTrue,
      );

      await _chooseSearchable(
        tester,
        const ValueKey('lesson-teacher-field'),
        'Пётр Педагогов',
      );
      await _chooseSearchable(
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
      await tester.pumpAndSettle();
      await tester.tap(find.text('Бесплатное занятие').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('lesson-compensation-rule-field')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Стандартная ставка').last);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('lesson-snapshot-preview')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('lesson-snapshot-trial')),
          matching: find.text('Пробное'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('lesson-snapshot-client-charge')),
          matching: find.textContaining('Бесплатное занятие · 0 ₽'),
        ),
        findsOneWidget,
      );
      final teacherPreview = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(
                const ValueKey('lesson-snapshot-teacher-compensation'),
              ),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data ?? '')
          .join(' ')
          .replaceAll('\u00a0', ' ');
      expect(teacherPreview, contains('Стандартная ставка'));
      expect(teacherPreview, contains('1 250 ₽/ч'));

      await _tapCreate(tester);
      await tester.pumpAndSettle();

      expect(client.constraintPreviews, hasLength(1));
      expect(client.constraintPreviews.single, {
        'clientRef': {'type': 'lead', 'id': _leadId},
        'teacherId': _teacherId,
        'branchId': _branchId,
        'roomId': _roomId,
        'scheduledAt': isA<String>(),
        'durationMinutes': 60,
      });
      expect(client.lessonPosts, hasLength(1));
      expect(client.lessonPosts.single, containsPair('isTrial', true));
      expect(client.lessonPosts.single['clientRef'], {
        'type': 'lead',
        'id': _leadId,
      });
      expect(client.lessonPosts.single, containsPair('teacherId', _teacherId));
      expect(client.lessonPosts.single, containsPair('branchId', _branchId));
      expect(client.lessonPosts.single, containsPair('roomId', _roomId));
      expect(
        client.lessonPosts.single,
        containsPair('teacherCompensationType', 'hourly'),
      );
      expect(
        client.lessonPosts.single,
        containsPair('teacherCompensationValue', 1250),
      );
      expect(client.lessonPosts.single['financialDecision'], {
        'settlementTypeKey': 'free_lesson',
        'teacherCompensationRuleKey': 'standard',
      });
      expect(dialogResult.value, isTrue);
      expect(find.text('Пробное занятие'), findsNothing);
      expect(find.text('Занятие создано'), findsOneWidget);
    },
  );

  testWidgets('единый Client selector отправляет Lead и trial независимо', (
    tester,
  ) async {
    final client = _FakeApiClient();
    await _pumpDialog(tester, client);
    await _selectRequiredResources(tester, clientName: 'Анна Лидова');

    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('lesson-trial-toggle')),
          )
          .value,
      isFalse,
    );
    await _tapCreate(tester);
    await tester.pumpAndSettle();

    expect(client.lessonPosts, hasLength(1));
    final body = client.lessonPosts.single;
    expect(body['clientRef'], {'type': 'lead', 'id': _leadId});
    expect(body['isTrial'], isFalse);
    expect(body['completionType'], 'standard.success');
    expect(body['clientChargeType'], 'none');
    expect(body['clientChargeValue'], 0);
    expect(body['teacherCompensationType'], 'none');
    expect(body['teacherCompensationValue'], 0);
    expect(body['financialDecision'], {
      'settlementTypeKey': 'free_lesson',
      'teacherCompensationRuleKey': 'none',
    });
    expect(body['roomId'], _roomId);
    expect(body, isNot(contains('studentId')));
    expect(body, isNot(contains('leadId')));
    expect(body, isNot(contains('status')));
    expect(body, isNot(contains('force')));
  });

  testWidgets(
    'create вводит процент, фиксированную и почасовую оплату в основном окне',
    (tester) async {
      final client = _FakeApiClient(
        decisionCatalog: _manualCompensationCatalog,
        teacherCurrentRate: 1400,
      );
      await _pumpDialog(tester, client);
      await _selectRequiredResources(tester, clientName: 'Анна Лидова');

      Future<void> selectRule(String label) async {
        await tester.ensureVisible(
          find.byKey(const ValueKey('lesson-compensation-rule-field')),
        );
        await tester.tap(
          find.byKey(const ValueKey('lesson-compensation-rule-field')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }

      await selectRule('Процент ставки');
      expect(find.text('Процент от стандартной ставки, % *'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('lesson-compensation-value-field')),
        '12,5',
      );

      await selectRule('Фиксированная сумма');
      expect(find.text('Фиксированная сумма за занятие, ₽ *'), findsOneWidget);

      await selectRule('Почасовая сумма');
      expect(find.text('Почасовая ставка, ₽ *'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('lesson-compensation-value-field')),
        '1 250,50',
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('lesson-compensation-override-reason-field')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('lesson-compensation-override-reason-field')),
        'Индивидуальная ставка согласована директором',
      );

      await _tapCreate(tester);
      await tester.pumpAndSettle();

      expect(client.lessonPosts, hasLength(1));
      expect(client.lessonPosts.single['financialDecision'], {
        'settlementTypeKey': 'free_lesson',
        'teacherCompensationRuleKey': 'hourly',
        'teacherCompensationValueMinor': '125050',
      });
      expect(
        client.lessonPosts.single['plannedSettlementReason'],
        'Индивидуальная ставка согласована директором',
      );
    },
  );

  testWidgets('trial marker does not disable paid subscription funding', (
    tester,
  ) async {
    final client = _FakeApiClient(
      subscriptions: const [
        {
          'id': 'subscription-1',
          'studentId': _studentId,
          'lessonsTotal': 12,
          'lessonsUsed': 1,
          'status': 'active',
          'packageName': '12 занятий',
          'packagePrice': 30000,
        },
      ],
    );
    await _pumpDialog(tester, client);
    await _chooseSearchable(
      tester,
      const ValueKey('lesson-client-field'),
      'Иван Прилежный',
    );
    await _chooseSearchable(
      tester,
      const ValueKey('lesson-teacher-field'),
      'Пётр Педагогов',
    );
    await _chooseSearchable(
      tester,
      const ValueKey('lesson-room-field'),
      'Зал 1',
    );
    await tester.tap(find.byKey(const ValueKey('lesson-trial-toggle')));
    await tester.pumpAndSettle();

    await _tapCreate(tester);
    await tester.pumpAndSettle();

    final body = client.lessonPosts.single;
    expect(body['isTrial'], isTrue);
    expect(body['clientChargeType'], 'subscription');
    expect(body['clientChargeValue'], 1);
    expect(body['subscriptionId'], 'subscription-1');
    expect(body['financialDecision'], {
      'settlementTypeKey': 'standard_lesson',
      'teacherCompensationRuleKey': 'none',
    });
  });

  testWidgets('trial marker can coexist with an explicit free settlement', (
    tester,
  ) async {
    final client = _FakeApiClient();
    await _pumpDialog(tester, client);
    await _selectRequiredResources(tester, clientName: 'Иван Прилежный');
    await tester.tap(find.byKey(const ValueKey('lesson-trial-toggle')));
    await tester.pumpAndSettle();

    await _tapCreate(tester);
    await tester.pumpAndSettle();

    final body = client.lessonPosts.single;
    expect(body['isTrial'], isTrue);
    expect(body['clientChargeType'], 'none');
    expect(body['clientChargeValue'], 0);
    expect(body, isNot(contains('subscriptionId')));
    expect(body['financialDecision'], {
      'settlementTypeKey': 'free_lesson',
      'teacherCompensationRuleKey': 'none',
    });
  });

  testWidgets(
    'student defaults to a concrete active subscription in the create payload',
    (tester) async {
      final client = _FakeApiClient(
        subscriptions: const [
          {
            'id': 'subscription-1',
            'studentId': _studentId,
            'lessonsTotal': 12,
            'lessonsUsed': 1,
            'status': 'active',
            'packageName': '12 занятий',
            'packagePrice': 30000,
          },
        ],
      );
      await _pumpDialog(tester, client);
      await _chooseSearchable(
        tester,
        const ValueKey('lesson-client-field'),
        'Иван Прилежный',
      );
      await _chooseSearchable(
        tester,
        const ValueKey('lesson-teacher-field'),
        'Пётр Педагогов',
      );
      await _chooseSearchable(
        tester,
        const ValueKey('lesson-room-field'),
        'Зал 1',
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('lesson-charge-type-field')),
      );
      expect(find.text('С абонемента'), findsOneWidget);
      expect(find.text('Списание клиента *'), findsNothing);
      expect(find.text('Стоимость / списание *'), findsNothing);
      expect(find.text('Оплата преподавателя *'), findsNothing);
      expect(find.text('Сумма / ставка *'), findsNothing);

      await _tapCreate(tester);
      await tester.pumpAndSettle();

      final body = client.lessonPosts.single;
      expect(body['clientChargeType'], 'subscription');
      expect(body['clientChargeValue'], 1);
      expect(body['subscriptionId'], 'subscription-1');
      expect(body['financialDecision'], {
        'settlementTypeKey': 'standard_lesson',
        'teacherCompensationRuleKey': 'none',
      });
    },
  );

  testWidgets(
    'Без списания доступно для бесплатного типа и очищает абонемент',
    (tester) async {
      final client = _FakeApiClient(
        subscriptions: const [
          {
            'id': 'subscription-1',
            'studentId': _studentId,
            'lessonsTotal': 12,
            'lessonsUsed': 1,
            'status': 'active',
            'packageName': '12 занятий',
            'packagePrice': 30000,
          },
        ],
      );
      await _pumpDialog(tester, client);
      await _chooseSearchable(
        tester,
        const ValueKey('lesson-client-field'),
        'Иван Прилежный',
      );
      await _chooseSearchable(
        tester,
        const ValueKey('lesson-teacher-field'),
        'Пётр Педагогов',
      );
      await _chooseSearchable(
        tester,
        const ValueKey('lesson-room-field'),
        'Зал 1',
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('lesson-charge-type-field')),
      );
      await tester.tap(find.byKey(const ValueKey('lesson-charge-type-field')));
      await tester.pumpAndSettle();
      expect(find.text('Без списания'), findsNothing);
      await tester.tap(find.text('С абонемента').last);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('lesson-settlement-type-field')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Бесплатное занятие').last);
      await tester.pumpAndSettle();
      expect(find.text('Без списания'), findsOneWidget);

      await _tapCreate(tester);
      await tester.pumpAndSettle();

      final body = client.lessonPosts.single;
      expect(body['clientChargeType'], 'none');
      expect(body['clientChargeValue'], 0);
      expect(body, isNot(contains('subscriptionId')));
      expect(body['financialDecision'], {
        'settlementTypeKey': 'free_lesson',
        'teacherCompensationRuleKey': 'none',
      });
    },
  );

  testWidgets(
    'settlement pay rule and funding source are independent required choices',
    (tester) async {
      final client = _FakeApiClient(
        subscriptions: const [
          {
            'id': 'subscription-1',
            'studentId': _studentId,
            'lessonsTotal': 12,
            'lessonsUsed': 1,
            'status': 'active',
            'packageName': '12 занятий',
            'packagePrice': 30000,
          },
        ],
      );
      await _pumpDialog(tester, client);
      await _chooseSearchable(
        tester,
        const ValueKey('lesson-client-field'),
        'Иван Прилежный',
      );
      await _chooseSearchable(
        tester,
        const ValueKey('lesson-teacher-field'),
        'Пётр Педагогов',
      );
      await _chooseSearchable(
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
      await tester.pumpAndSettle();
      await tester.tap(find.text('Занятие').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('lesson-compensation-rule-field')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Стандартная ставка').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lesson-charge-type-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('С личного счёта').last);
      await tester.pumpAndSettle();

      await _tapCreate(tester);
      await tester.pumpAndSettle();

      final body = client.lessonPosts.single;
      expect(body['financialDecision'], {
        'settlementTypeKey': 'standard_lesson',
        'teacherCompensationRuleKey': 'standard',
      });
      expect(body['clientChargeType'], 'personal_account');
      expect(body, isNot(contains('subscriptionId')));
    },
  );

  testWidgets('empty decision catalog blocks lesson creation', (tester) async {
    final client = _FakeApiClient(
      decisionCatalog: const {
        'settlementTypes': <Map<String, dynamic>>[],
        'teacherCompensationRules': <Map<String, dynamic>>[],
      },
    );
    await _pumpDialog(tester, client);
    await _chooseSearchable(
      tester,
      const ValueKey('lesson-client-field'),
      'Иван Прилежный',
    );
    await _chooseSearchable(
      tester,
      const ValueKey('lesson-teacher-field'),
      'Пётр Педагогов',
    );
    await _chooseSearchable(
      tester,
      const ValueKey('lesson-room-field'),
      'Зал 1',
    );
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('lesson-settlement-type-field')),
          )
          .initialValue,
      isNull,
    );
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('lesson-compensation-rule-field')),
          )
          .initialValue,
      isNull,
    );

    await _tapCreate(tester);

    expect(client.lessonPosts, isEmpty);
    expect(find.text('Новое занятие'), findsOneWidget);
  });

  testWidgets('preview-конфликт блокирует create без force affordance', (
    tester,
  ) async {
    final client = _FakeApiClient(preview: _busyPreview());
    await _pumpDialog(tester, client);
    await _selectRequiredResources(tester, clientName: 'Иван Прилежный');
    await _tapCreate(tester);

    expect(find.text('Занятие не сохранено'), findsOneWidget);
    expect(find.text('Преподаватель недоступен'), findsOneWidget);
    expect(find.text('У клиента уже есть занятие'), findsOneWidget);
    expect(find.text('Аудитория уже занята'), findsOneWidget);
    expect(find.text('Всё равно назначить'), findsNothing);
    expect(client.lessonPosts, isEmpty);
  });

  testWidgets('ошибка preview не блокирует authoritative create', (
    tester,
  ) async {
    final client = _FakeApiClient(
      previewError: Exception('schedule preview unavailable'),
    );
    final dialogResult = ValueNotifier<bool?>(null);
    addTearDown(dialogResult.dispose);
    await _pumpDialog(tester, client, dialogResult: dialogResult);
    await _selectRequiredResources(tester, clientName: 'Иван Прилежный');

    await _tapCreate(tester);
    await tester.pumpAndSettle();

    expect(client.constraintPreviews, hasLength(1));
    expect(client.lessonPosts, hasLength(1));
    expect(dialogResult.value, isTrue);
    expect(find.text('Новое занятие'), findsNothing);
  });

  testWidgets(
    'inline Schedule Analyzer applies and rechecks a ranked variant',
    (tester) async {
      final preview = _busyPreview()
        ..['suggestions'] = [
          {
            'kind': 'SAME_TIME_ROOM',
            'rank': 1,
            'score': 1000,
            'changes': {'roomId': _replacementRoomId, 'roomName': 'Зал 2'},
          },
        ];
      final client = _FakeApiClient(preview: preview);
      await _pumpDialog(tester, client);
      await _selectRequiredResources(tester, clientName: 'Иван Прилежный');

      final run = find.byKey(const ValueKey('lesson-run-schedule-analyzer'));
      await tester.ensureVisible(run);
      await tester.tap(run);
      await tester.pumpAndSettle();

      expect(find.text('Найдены конфликты'), findsOneWidget);
      final suggestion = find.byKey(const ValueKey('lesson-suggestion-1'));
      await tester.ensureVisible(suggestion);
      await tester.tap(suggestion);
      await tester.pumpAndSettle();

      expect(client.constraintPreviews, hasLength(2));
      expect(client.constraintPreviews.last['roomId'], _replacementRoomId);
    },
  );

  testWidgets('double click creates exactly one lesson mutation', (
    tester,
  ) async {
    final client = _FakeApiClient();
    client.createGate = Completer<void>();
    await _pumpDialog(tester, client);
    await _selectRequiredResources(tester, clientName: 'Анна Лидова');

    await tester.ensureVisible(find.text('Создать'));
    await tester.tap(find.text('Создать'));
    await tester.tap(find.text('Создать'));
    expect(client.lessonPosts, hasLength(1));
    client.createGate!.complete();
    await tester.pumpAndSettle();

    expect(client.lessonPosts, hasLength(1));
  });

  testWidgets(
    'authoritative race 422 показывает conflict и сохраняет весь черновик',
    (tester) async {
      final error = MagicApiException(
        statusCode: 422,
        message: 'Lesson draft violates schedule constraints.',
        details: {
          'code': 'LESSON_CONSTRAINT_VIOLATIONS',
          'violations': [
            {
              'code': 'ROOM_OVERLAP',
              'resource': {'type': 'room', 'id': _roomId},
              'conflictingLessonIds': [_conflictId],
              'ruleIds': const [],
            },
            {
              'code': 'OUTSIDE_BRANCH_HOURS',
              'resource': {'type': 'branch', 'id': _branchId},
              'conflictingLessonIds': const [],
              'ruleIds': ['branch-hours-1'],
            },
          ],
        },
      );
      final client = _FakeApiClient(createError: error);
      await _pumpDialog(tester, client);
      await _selectRequiredResources(tester, clientName: 'Иван Прилежный');
      await tester.ensureVisible(
        find.byKey(const ValueKey('lesson-duration-field')),
      );
      await tester.tap(find.byKey(const ValueKey('lesson-duration-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('90 мин').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lesson-trial-toggle')));
      await tester.pumpAndSettle();
      final dateBefore = tester
          .widget<Text>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('lesson-date-field')),
                  matching: find.byType(Text),
                )
                .first,
          )
          .data;
      final timeBefore = tester
          .widget<Text>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('lesson-time-field')),
                  matching: find.byType(Text),
                )
                .first,
          )
          .data;
      await _tapCreate(tester);

      expect(client.lessonPosts, hasLength(1));
      expect(find.text('Занятие не сохранено'), findsOneWidget);
      expect(find.text('Аудитория уже занята'), findsOneWidget);
      expect(find.text('Филиал закрыт в это время'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('conflict-lesson-$_conflictId')),
        findsOneWidget,
      );
      expect(find.text('Всё равно назначить'), findsNothing);

      await tester.tap(find.text('Исправить'));
      await tester.pumpAndSettle();
      expect(find.text('Новое занятие'), findsOneWidget);
      expect(
        tester
            .widget<SearchablePickerField>(
              find.byKey(const ValueKey('lesson-client-field')),
            )
            .selectedId,
        'student:$_studentId',
      );
      expect(
        tester
            .widget<SearchablePickerField>(
              find.byKey(const ValueKey('lesson-teacher-field')),
            )
            .selectedId,
        _teacherId,
      );
      expect(
        tester
            .widget<SearchablePickerField>(
              find.byKey(const ValueKey('lesson-room-field')),
            )
            .selectedId,
        _roomId,
      );
      expect(
        find.byKey(const ValueKey('lesson-branch-field:$_branchId')),
        findsOneWidget,
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
      expect(
        tester
            .widget<Text>(
              find
                  .descendant(
                    of: find.byKey(const ValueKey('lesson-date-field')),
                    matching: find.byType(Text),
                  )
                  .first,
            )
            .data,
        dateBefore,
      );
      expect(
        tester
            .widget<Text>(
              find
                  .descendant(
                    of: find.byKey(const ValueKey('lesson-time-field')),
                    matching: find.byType(Text),
                  )
                  .first,
            )
            .data,
        timeBefore,
      );
      expect(client.lessonPosts.single, containsPair('durationMinutes', 90));
      expect(client.lessonPosts.single, containsPair('isTrial', true));

      await _tapCreate(tester);
      expect(client.lessonPosts, hasLength(2));
      expect(find.text('Занятие не сохранено'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('conflict-lesson-$_conflictId')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Занятие не сохранено'), findsNothing);
      expect(find.text('Новое занятие'), findsNothing);
    },
  );

  testWidgets('edit проходит общий decision preview и не меняет snapshot', (
    tester,
  ) async {
    final client = _FakeApiClient();
    final lesson = _editableLesson();
    final dialogResult = ValueNotifier<bool?>(null);
    addTearDown(dialogResult.dispose);
    await _pumpDialog(
      tester,
      client,
      lesson: lesson,
      dialogResult: dialogResult,
    );
    await _moveEditableLessonToNextDay(tester);

    await tester.ensureVisible(find.text('Перейти к расчёту'));
    await tester.tap(find.text('Перейти к расчёту'));
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Перенос занятия'), findsOneWidget);
    expect(find.byKey(const Key('lesson-decision-reason')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('lesson-decision-reason')),
      'Клиент попросил другое время',
    );
    await tester.tap(find.byKey(const Key('lesson-decision-settlement')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Бесплатное занятие').last);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(
      find.byKey(const Key('lesson-decision-compensation')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('lesson-decision-compensation')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Не оплачивать').last);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(find.byKey(const Key('lesson-decision-submit')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('lesson-decision-submit')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(client.decisionPreviews, hasLength(1));
    expect(find.byKey(const Key('lesson-decision-preview')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('lesson-decision-submit')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('lesson-decision-submit')));
    await tester.pumpAndSettle();

    expect(client.decisionCommits, hasLength(1));
    final body = client.decisionCommits.single;
    expect(body['expectedVersion'], 7);
    expect(body['reasonText'], 'Клиент попросил другое время');
    expect(body['financialDecision'], {
      'settlementTypeKey': 'free_lesson',
      'teacherCompensationRuleKey': 'none',
    });
    expect(body['successor']['teacherId'], _teacherId);
    expect(body['successor']['roomId'], _roomId);
    expect(body['successor']['scheduledAt'], '2026-07-19T07:00:00.000Z');
    expect(body['successor'], isNot(contains('clientRef')));
    expect(body['successor'], isNot(contains('isTrial')));
    expect(body['successor'], isNot(contains('completionType')));
    expect(body['successor'], isNot(contains('force')));
    expect(body['previewToken'], 'signed-lesson-preview');
    expect(body['confirm'], isTrue);
    expect(dialogResult.value, isTrue);
    expect(find.text('Перенести или изменить занятие'), findsNothing);
    expect(find.text('Изменения занятия применены'), findsOneWidget);
  });

  testWidgets(
    'edit позволяет изменить только оплату преподавателю из основного окна',
    (tester) async {
      final client = _FakeApiClient(
        decisionCatalog: _manualCompensationCatalog,
      );
      await _pumpDialog(tester, client, lesson: _editableLesson());

      await tester.ensureVisible(
        find.byKey(const ValueKey('lesson-compensation-rule-field')),
      );
      await tester.tap(
        find.byKey(const ValueKey('lesson-compensation-rule-field')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Фиксированная сумма').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('lesson-compensation-value-field')),
        '1500',
      );

      await tester.ensureVisible(find.text('Перейти к расчёту'));
      await tester.tap(find.text('Перейти к расчёту'));
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('Изменение расчёта'), findsOneWidget);
      expect(
        tester
            .state<FormFieldState<String>>(
              find.byKey(const Key('lesson-decision-compensation')),
            )
            .value,
        'fixed',
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('lesson-decision-compensation-value')),
            )
            .controller
            ?.text,
        '1500',
      );
      await tester.enterText(
        find.byKey(const Key('lesson-decision-reason')),
        'Исправлена ставка занятия',
      );
      await tester.ensureVisible(
        find.byKey(const Key('lesson-decision-submit')),
      );
      await tester.tap(find.byKey(const Key('lesson-decision-submit')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(
        find.byKey(const Key('lesson-decision-submit')),
      );
      await tester.tap(find.byKey(const Key('lesson-decision-submit')));
      await tester.pumpAndSettle();

      expect(client.decisionCommits, hasLength(1));
      expect(client.decisionCommitMethods, [
        'PUT /crm/lessons/66666666-6666-6666-6666-666666666666/planned-settlement',
      ]);
      expect(client.decisionCommits.single['financialDecision'], {
        'settlementTypeKey': 'free_lesson',
        'teacherCompensationRuleKey': 'fixed',
        'teacherCompensationValueMinor': '150000',
      });
      expect(client.decisionCommits.single, isNot(contains('successor')));
    },
  );

  testWidgets(
    'подмена показывает только ресурсы филиала и атомарно сохраняет выбор',
    (tester) async {
      final client = _FakeApiClient();
      await _pumpDialog(tester, client, lesson: _editableLesson());

      final teacherField = tester.widget<SearchablePickerField>(
        find.byKey(const ValueKey('lesson-teacher-field')),
      );
      expect(
        teacherField.items.map((item) => item.label),
        containsAll(['Пётр Педагогов', 'Мария Сменова']),
      );
      expect(
        teacherField.items.map((item) => item.label),
        isNot(contains('Ирина Неактивная')),
      );
      expect(
        teacherField.items.map((item) => item.label),
        isNot(contains('Олег Другой')),
      );
      final roomField = tester.widget<SearchablePickerField>(
        find.byKey(const ValueKey('lesson-room-field')),
      );
      expect(roomField.items.map((item) => item.label), ['Зал 1', 'Зал 2']);
      expect(
        find.byKey(const ValueKey('lesson-replacement-availability-hint')),
        findsOneWidget,
      );

      await _chooseSearchable(
        tester,
        const ValueKey('lesson-teacher-field'),
        'Мария Сменова',
      );
      await _chooseSearchable(
        tester,
        const ValueKey('lesson-room-field'),
        'Зал 2',
      );
      await _fillRescheduleDecision(
        tester,
        reason: 'Назначена согласованная подмена',
      );

      expect(client.decisionPreviews, hasLength(1));
      expect(find.byKey(const Key('lesson-decision-preview')), findsOneWidget);
      await tester.tap(find.byKey(const Key('lesson-decision-submit')));
      await tester.pumpAndSettle();

      final body = client.decisionCommits.single;
      expect(body['successor']['teacherId'], _replacementTeacherId);
      expect(body['successor']['roomId'], _replacementRoomId);
      expect(body['successor'], isNot(contains('clientRef')));
      expect(body['previewToken'], 'signed-lesson-preview');
      expect(body['confirm'], isTrue);
    },
  );

  testWidgets('занятая подмена блокируется с понятной причиной', (
    tester,
  ) async {
    final client = _FakeApiClient(
      decisionViolations: const [
        {
          'code': 'TEACHER_OVERLAP',
          'resource': {'type': 'teacher', 'id': _replacementTeacherId},
        },
        {
          'code': 'ROOM_OVERLAP',
          'resource': {'type': 'room', 'id': _replacementRoomId},
        },
      ],
    );
    await _pumpDialog(tester, client, lesson: _editableLesson());
    await _chooseSearchable(
      tester,
      const ValueKey('lesson-teacher-field'),
      'Мария Сменова',
    );
    await _chooseSearchable(
      tester,
      const ValueKey('lesson-room-field'),
      'Зал 2',
    );
    await _fillRescheduleDecision(tester, reason: 'Проверка занятой подмены');

    expect(find.text('Изменение заблокировано'), findsOneWidget);
    expect(
      find.textContaining('У преподавателя уже есть занятие в это время'),
      findsOneWidget,
    );
    expect(find.textContaining('Аудитория уже занята'), findsOneWidget);
    expect(find.text('Повторить расчёт'), findsOneWidget);
    expect(client.decisionCommits, isEmpty);
  });

  testWidgets('edit без изменений не создаёт фиктивный перенос', (
    tester,
  ) async {
    final client = _FakeApiClient();
    await _pumpDialog(tester, client, lesson: _editableLesson());

    await tester.ensureVisible(find.text('Перейти к расчёту'));
    await tester.tap(find.text('Перейти к расчёту'));
    await tester.pumpAndSettle();

    expect(
      find.text('Измените параметры расписания или оплату преподавателю'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('lesson-decision-reason')), findsNothing);
    expect(client.decisionPreviews, isEmpty);
    expect(client.decisionCommits, isEmpty);
  });

  testWidgets('edit без версии остаётся открытым и не запускает расчёт', (
    tester,
  ) async {
    final client = _FakeApiClient();
    final lesson = _editableLesson()..remove('version');
    await _pumpDialog(tester, client, lesson: lesson);
    await _moveEditableLessonToNextDay(tester);

    await tester.ensureVisible(find.text('Перейти к расчёту'));
    await tester.tap(find.text('Перейти к расчёту'));
    await tester.pumpAndSettle();

    expect(
      find.text('Обновите расписание: версия занятия не получена'),
      findsOneWidget,
    );
    expect(find.text('Перенести или изменить занятие'), findsOneWidget);
    expect(client.decisionPreviews, isEmpty);
    expect(client.decisionCommits, isEmpty);
  });

  testWidgets('group lesson открывает перенос без фиктивного клиента', (
    tester,
  ) async {
    final client = _FakeApiClient();
    await _pumpDialog(tester, client, lesson: _editableLesson(group: true));

    expect(find.byKey(const ValueKey('lesson-group-field')), findsOneWidget);
    expect(find.text('Ансамбль Север'), findsOneWidget);
    expect(find.byKey(const ValueKey('lesson-client-field')), findsNothing);
    await _moveEditableLessonToNextDay(tester);
    await tester.ensureVisible(find.text('Перейти к расчёту'));
    await tester.tap(find.text('Перейти к расчёту'));
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Перенос занятия'), findsOneWidget);
    expect(find.byKey(const Key('lesson-decision-reason')), findsOneWidget);
  });

  for (final operation in const [
    LessonDecisionOperation.plannedSettlement,
    LessonDecisionOperation.correction,
  ]) {
    testWidgets('${operation.name} uses signed preview and one atomic commit', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final client = _FakeApiClient();
      await tester.pumpWidget(_decisionHost(client, operation));
      await tester.tap(find.text('открыть расчёт'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('lesson-decision-reason')),
        'Расчёт изменён после проверки сотрудником',
      );
      await tester.tap(find.byKey(const Key('lesson-decision-settlement')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Бесплатное занятие').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('lesson-decision-compensation')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Не оплачивать').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('lesson-decision-submit')));
      await tester.pumpAndSettle();

      expect(client.decisionPreviews, hasLength(1));
      expect(client.decisionPreviews.single, isNot(contains('reasonCode')));
      expect(find.byKey(const Key('lesson-decision-preview')), findsOneWidget);
      await tester.tap(find.byKey(const Key('lesson-decision-submit')));
      await tester.pumpAndSettle();

      expect(client.decisionCommits, hasLength(1));
      expect(client.decisionCommits.single, {
        'expectedVersion': 7,
        'reasonText': 'Расчёт изменён после проверки сотрудником',
        'financialDecision': {
          'settlementTypeKey': 'free_lesson',
          'teacherCompensationRuleKey': 'none',
        },
        'previewToken': 'signed-lesson-preview',
        'confirm': true,
      });
      expect(
        client.decisionCommitMethods.single,
        startsWith(
          operation == LessonDecisionOperation.plannedSettlement
              ? 'PUT '
              : 'POST ',
        ),
      );
    });
  }
}
