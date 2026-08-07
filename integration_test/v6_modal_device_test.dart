import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/searchable_select.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision_flow.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_details_sheet.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('representative lesson surfaces follow the adaptive policy', (
    tester,
  ) async {
    await initializeDateFormatting('ru');
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark, home: const _ModalDeviceHome()),
    );

    await tester.tap(find.text('Быстрый просмотр'));
    await tester.pumpAndSettle();
    expect(find.text('Анна Смирнова'), findsNWidgets(2));
    expect(find.text('Перенести или изменить'), findsOneWidget);
    if (const bool.fromEnvironment('V6_VISUAL_CHECK')) {
      debugPrint('V6_MODAL_SCREENSHOT_READY');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 30)),
      );
    }

    await tester.tap(find.text('Перенести или изменить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выбрать клиента'));
    await tester.pumpAndSettle();
    expect(find.text('Поиск по ФИО'), findsOneWidget);
    await tester.tap(find.text('Анна Смирнова').last);
    await tester.pumpAndSettle();
    expect(find.text('Выбрано: Анна Смирнова'), findsOneWidget);
    await tester.tap(find.text('LessonDecision v7'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('lesson-decision-reason')),
      'Клиент попросил перенести',
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
    expect(find.textContaining('Клиент:'), findsOneWidget);
    expect(find.textContaining('Преподаватель:'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('lesson-decision-submit')));
    await tester.tap(find.byKey(const Key('lesson-decision-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Решение: применено'), findsOneWidget);
    debugPrint('V6_MODAL_DEVICE_PASS');
  });
}

class _ModalDeviceHome extends StatefulWidget {
  const _ModalDeviceHome();

  @override
  State<_ModalDeviceHome> createState() => _ModalDeviceHomeState();
}

class _ModalDeviceHomeState extends State<_ModalDeviceHome> {
  String? _selected;
  bool _decisionApplied = false;
  final _decisionApi = _DecisionDeviceApi();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('V6 surface QA')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          FilledButton(
            onPressed: () => showLessonDetailsSheet(
              context,
              teacherName: 'Пётр Педагогов',
              studentName: 'Анна Смирнова',
              roomName: 'Зал 1',
              timeRange: '14:00–15:00',
              currentStatus: 'scheduled',
              conflicts: const [],
              lessonId: 'lesson-1',
              onEdit: () {},
              onCancel: () async {},
            ),
            child: const Text('Быстрый просмотр'),
          ),
          FilledButton(
            onPressed: () => SearchableSelect.show(
              context: context,
              title: 'Выберите клиента',
              hintText: 'Поиск по ФИО',
              items: [
                SearchableSelectItem(id: 'student-1', label: 'Анна Смирнова'),
              ],
              isNullable: false,
              onSelected: (item) => setState(() => _selected = item?.label),
            ),
            child: const Text('Выбрать клиента'),
          ),
          Text('Выбрано: ${_selected ?? '—'}'),
          FilledButton(
            onPressed: () async {
              final result = await showLessonDecisionFlow(
                context,
                api: _decisionApi,
                operation: LessonDecisionOperation.reschedule,
                lesson: const {
                  'id': '10000000-0000-4000-8000-000000000001',
                  'version': 4,
                  'branch_id': '20000000-0000-4000-8000-000000000001',
                  'scheduled_at': '2026-08-07T09:00:00.000Z',
                },
                successor: const {
                  'scheduledAt': '2026-08-08T10:00:00.000Z',
                  'durationMinutes': 60,
                },
              );
              if (mounted && result == true) {
                setState(() => _decisionApplied = true);
              }
            },
            child: const Text('LessonDecision v7'),
          ),
          Text('Решение: ${_decisionApplied ? 'применено' : 'не применено'}'),
        ],
      ),
    );
  }
}

class _DecisionDeviceApi extends MagicApiClient {
  _DecisionDeviceApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    return <String, dynamic>{
          'settlementTypes': const [
            {
              'stableKey': 'free_lesson',
              'label': 'Бесплатное занятие',
              'colorToken': 'warning',
              'allowedContexts': ['reschedule'],
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

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    return <String, dynamic>{
          'source': const {'state': 'scheduled'},
          'successor': const {'state': 'scheduled'},
          'canConfirm': true,
          'previewToken': 'device-preview',
          'violations': const [],
          'financialPreview': const {
            'clientFacts': [
              {
                'settlementLabel': 'Бесплатное занятие',
                'units': '0.00',
                'amountMinor': '0',
              },
            ],
            'teacherFact': {
              'compensationRuleLabel': 'Не оплачивать',
              'amountMinor': '0',
            },
          },
          'warnings': const [],
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
    return <String, dynamic>{'transitionId': 'device-transition'} as T;
  }
}
