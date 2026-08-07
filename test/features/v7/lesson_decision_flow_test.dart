import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision_flow.dart';

const _lessonId = '10000000-0000-4000-8000-000000000001';
const _branchId = '20000000-0000-4000-8000-000000000001';

const _lesson = <String, dynamic>{
  'id': _lessonId,
  'version': 4,
  'branch_id': _branchId,
  'scheduled_at': '2026-08-07T09:00:00.000Z',
};

const _successor = <String, dynamic>{
  'scheduledAt': '2026-08-08T10:00:00.000Z',
  'durationMinutes': 60,
};

class _LessonDecisionApi extends MagicApiClient {
  _LessonDecisionApi({this.conflict = false, this.failFirstCommit = false})
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final bool conflict;
  final bool failFirstCommit;
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
              'stableKey': 'free_lesson',
              'label': 'Бесплатное занятие',
              'colorToken': 'warning',
              'allowedContexts': ['reschedule'],
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
              'stableKey': 'fixed',
              'label': 'Фиксированная сумма',
              'mode': 'fixed',
              'value': '150000',
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
    expect(path, '/crm/lessons/$_lessonId/reschedule/preview');
    previews.add(Map<String, dynamic>.from(data as Map));
    return <String, dynamic>{
          'operation': 'reschedule',
          'source': const {'id': _lessonId, 'version': 4, 'state': 'scheduled'},
          'successor': _successor,
          'financialDecision': previews.last['financialDecision'],
          'violations': conflict
              ? const [
                  {
                    'code': 'ROOM_OVERLAP',
                    'resource': {'type': 'room', 'id': 'room-1'},
                  },
                ]
              : const [],
          'canConfirm': !conflict,
          'confirmRequired': true,
          if (!conflict) ...{
            'financialPreview': const {
              'clientFacts': [
                {
                  'settlementTypeKey': 'free_lesson',
                  'settlementLabel': 'Бесплатное занятие',
                  'amountMinor': '0',
                  'units': '0.00',
                },
              ],
              'teacherFact': {
                'compensationRuleKey': 'fixed',
                'compensationRuleLabel': 'Фиксированная сумма',
                'amountMinor': '125000',
              },
            },
            'warnings': const ['SUCCESSOR_MAY_CHARGE_AGAIN'],
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
    expect(path, '/crm/lessons/$_lessonId/reschedule');
    identities.add(identity);
    commits.add(Map<String, dynamic>.from(data as Map));
    if (failFirstCommit && commits.length == 1) {
      throw const MagicApiException(statusCode: 409, message: 'Preview stale');
    }
    return <String, dynamic>{'transitionId': 'transition-1'} as T;
  }
}

Widget _host(_LessonDecisionApi api) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => FilledButton(
        onPressed: () => showLessonDecisionFlow(
          context,
          api: api,
          operation: LessonDecisionOperation.reschedule,
          lesson: _lesson,
          successor: _successor,
        ),
        child: const Text('Открыть'),
      ),
    ),
  ),
);

Future<void> _openAndFill(WidgetTester tester, _LessonDecisionApi api) async {
  tester.view.physicalSize = const Size(1400, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(api));
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
    expect(find.textContaining('Аудитория уже занята'), findsOneWidget);
    expect(find.text('Повторить расчёт'), findsOneWidget);
    expect(api.commits, isEmpty);
  });
}
