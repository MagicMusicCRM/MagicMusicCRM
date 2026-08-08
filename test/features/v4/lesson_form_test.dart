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
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision_flow.dart';

const _teacherId = '22222222-2222-2222-2222-222222222222';
const _studentId = '33333333-3333-3333-3333-333333333333';
const _leadId = '77777777-7777-7777-7777-777777777777';
const _branchId = '11111111-1111-1111-1111-111111111111';
const _roomId = '55555555-5555-5555-5555-555555555555';
const _conflictId = '44444444-4444-4444-4444-444444444444';

Map<String, dynamic> _freePreview() => {'valid': true, 'violations': const []};

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
    this.createError,
    this.subscriptions = const [],
  }) : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  Map<String, dynamic>? preview;
  MagicApiException? createError;
  final List<Map<String, dynamic>> subscriptions;
  Completer<void>? createGate;
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
                  'assignedBranches': const [
                    {'id': _branchId, 'name': 'Главный филиал'},
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
        return <String, dynamic>{
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
              ],
            }
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
            'violations': const [],
            'canConfirm': true,
            'confirmRequired': true,
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

Widget _host(_FakeApiClient client, {Map<String, dynamic>? lesson}) {
  return ProviderScope(
    overrides: [magicApiClientProvider.overrideWithValue(client)],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => CreateLessonDialog.show(context, lesson: lesson),
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
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(client, lesson: lesson));
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
  await tester.tap(find.byKey(const ValueKey('lesson-client-field')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(clientName).last);
  await tester.pumpAndSettle();

  await tester.ensureVisible(
    find.byKey(const ValueKey('lesson-teacher-field')),
  );
  await tester.tap(find.byKey(const ValueKey('lesson-teacher-field')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Пётр Педагогов').last);
  await tester.pumpAndSettle();

  await tester.ensureVisible(find.byKey(const ValueKey('lesson-room-field')));
  await tester.tap(find.byKey(const ValueKey('lesson-room-field')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Зал 1').last);
  await tester.pumpAndSettle();

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

Future<void> _tapCreate(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Создать'));
  await tester.tap(find.text('Создать'));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

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
    'student defaults to subscription and raw money fields stay absent',
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
      await tester.tap(find.byKey(const ValueKey('lesson-client-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Иван Прилежный').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('lesson-charge-type-field')),
      );
      expect(find.text('С абонемента'), findsOneWidget);
      expect(find.text('Списание клиента *'), findsNothing);
      expect(find.text('Стоимость / списание *'), findsNothing);
      expect(find.text('Оплата преподавателя *'), findsNothing);
      expect(find.text('Сумма / ставка *'), findsNothing);
    },
  );

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
    'authoritative 422 показывает structured violations и lesson link',
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
    final lesson = <String, dynamic>{
      'id': '66666666-6666-6666-6666-666666666666',
      'version': 7,
      'student_id': _studentId,
      'student_name': 'Иван Прилежный',
      'teacher_id': _teacherId,
      'branch_id': _branchId,
      'room_id': _roomId,
      'scheduled_at': '2026-07-18T07:00:00.000Z',
      'duration_minutes': 60,
      'is_trial': true,
      'snapshot_trial': true,
      'completion_type': 'custom.success',
      'client_charge_type': 'none',
      'client_charge_value': 0,
      'teacher_compensation_type': 'none',
      'teacher_compensation_value': 0,
    };
    await _pumpDialog(tester, client, lesson: lesson);

    await tester.ensureVisible(find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
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
    expect(body['successor'], isNot(contains('clientRef')));
    expect(body['successor'], isNot(contains('isTrial')));
    expect(body['successor'], isNot(contains('completionType')));
    expect(body['successor'], isNot(contains('force')));
    expect(body['previewToken'], 'signed-lesson-preview');
    expect(body['confirm'], isTrue);
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
