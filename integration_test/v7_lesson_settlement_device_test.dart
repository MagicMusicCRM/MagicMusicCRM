import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision_flow.dart';

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
                'stableKey': 'free_lesson',
                'label': 'Бесплатное занятие',
                'colorToken': 'warning',
                'allowedContexts': ['settle'],
                'active': true,
                'order': 0,
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
      previews.add(Map<String, dynamic>.from(data as Map));
      return <String, dynamic>{
            'canConfirm': true,
            'financialPreview': {
              'clientFacts': const [
                {
                  'settlementLabel': 'Бесплатное занятие',
                  'amountMinor': '0',
                  'units': '0.00',
                },
              ],
              'teacherFact': const {
                'compensationRuleLabel': 'Не оплачивать',
                'amountMinor': '0',
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
                  api: api,
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
      await tester.ensureVisible(find.byKey(const Key('lesson-decision-submit')));
      await tester.tap(find.byKey(const Key('lesson-decision-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lesson-decision-preview')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('lesson-decision-submit')));
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
}
