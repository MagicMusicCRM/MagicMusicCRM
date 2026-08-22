import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_controller.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_drilldown_view.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_summary_view.dart';

void main() {
  testWidgets('summary exposes initial loading and forbidden states', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _summaryView(
          tester,
          state: ReportingState.initial(),
          canReadSchoolFinance: false,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('reporting-loading')), findsOneWidget);

    await tester.pumpWidget(
      _app(
        _summaryView(
          tester,
          state: _state(forbidden: true),
          canReadSchoolFinance: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('reporting-forbidden')), findsOneWidget);
  });

  testWidgets('retained section error retries the exact failed section', (
    tester,
  ) async {
    final retries = <ReportingSectionKey>[];
    final state = _state(
      lessons: ReportingSection(
        data: _lessonData,
        error: StateError('lesson unavailable'),
      ),
      status: const ReportingSection(data: _statusData),
      tasks: const ReportingSection(data: _taskData),
    );

    await tester.pumpWidget(
      _app(
        _summaryView(
          tester,
          state: state,
          canReadSchoolFinance: false,
          onRetry: retries.add,
        ),
      ),
    );

    expect(find.text('Новые'), findsOneWidget);
    expect(find.text('Не удалось загрузить раздел'), findsOneWidget);
    final lessonRetry = find.descendant(
      of: find.byKey(const ValueKey('dashboard-lessons-section')),
      matching: find.text('Повторить'),
    );
    await tester.tap(lessonRetry);

    expect(retries, [ReportingSectionKey.lessons]);
  });

  testWidgets('summary renders populated lesson status and task actions', (
    tester,
  ) async {
    Map<String, dynamic>? drilldown;
    int? capturedExpectedCount;
    EntityLink? opened;

    await tester.pumpWidget(
      _app(
        _summaryView(
          tester,
          state: _readyState(
            finance: const ReportingSection(data: _financeData),
          ),
          canReadSchoolFinance: false,
          onOpenDrilldown: (link, {int? expectedCount}) {
            drilldown = link;
            capturedExpectedCount = expectedCount;
          },
          onOpenEntity: (link) => opened = link,
        ),
      ),
    );

    expect(find.text('Успешно завершённые занятия'), findsOneWidget);
    expect(find.text('8 из 10'), findsOneWidget);
    expect(find.text('80.0%'), findsOneWidget);
    expect(find.text('Новые'), findsOneWidget);
    expect(find.text('Открыто: 3 · Просрочено: 1'), findsOneWidget);

    await tester.tap(find.text('Новые'));
    expect(drilldown?['entityType'], 'client_status_list');
    expect(capturedExpectedCount, 2);

    await tester.tap(find.text('Открыто: 3 · Просрочено: 1'));
    expect(opened?.rawEntityType, 'task');
    expect(opened?.entityId, '__section__');
    expect(opened?.optionalFocus?.focus, 'section');
    expect(opened?.optionalFocus?.filter, const {'state': 'open'});
  });

  testWidgets('summary renders explicit empty lesson status and task values', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _summaryView(
          tester,
          state: _state(
            lessons: const ReportingSection(data: <String, dynamic>{}),
            status: const ReportingSection(
              data: <String, dynamic>{'items': <dynamic>[]},
            ),
            tasks: const ReportingSection(data: <String, dynamic>{}),
          ),
          canReadSchoolFinance: false,
        ),
      ),
    );

    expect(find.text('0 из 0'), findsOneWidget);
    expect(find.text('0.0%'), findsOneWidget);
    expect(find.text('За выбранный период клиентов нет'), findsOneWidget);
    expect(find.text('Открыто: 0 · Просрочено: 0'), findsOneWidget);
  });

  testWidgets('finance stays hidden when denied or section is forbidden', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _summaryView(
          tester,
          state: _readyState(
            finance: const ReportingSection(data: _financeData),
          ),
          canReadSchoolFinance: false,
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('dashboard-finance-section')),
      findsNothing,
    );

    await tester.pumpWidget(
      _app(
        _summaryView(
          tester,
          state: _readyState(finance: const ReportingSection(forbidden: true)),
          canReadSchoolFinance: true,
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('dashboard-finance-section')),
      findsNothing,
    );

    await tester.pumpWidget(
      _app(
        _summaryView(
          tester,
          state: _readyState(
            finance: const ReportingSection(data: <String, dynamic>{}),
          ),
          canReadSchoolFinance: true,
        ),
      ),
    );
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Финансы школы'), 250);
    expect(
      find.text('За выбранный период финансовых данных нет'),
      findsOneWidget,
    );
  });

  testWidgets('finance rows select immutable payload and detail goes back', (
    tester,
  ) async {
    Map<String, dynamic>? selected;
    var backed = false;
    await tester.pumpWidget(
      _app(
        _summaryView(
          tester,
          state: _readyState(
            finance: const ReportingSection(data: _financeData),
          ),
          canReadSchoolFinance: true,
          onSelectFinance: (row) => selected = row,
        ),
      ),
    );

    await tester.scrollUntilVisible(find.text('2026-07-01'), 250);
    await tester.tap(find.text('2026-07-01'));
    expect(selected?['revenueMinor'], '800000');
    expect(selected?['link'], const {
      'entityType': 'school_finance_month',
      'entityId': '2026-07-01',
    });

    await tester.pumpWidget(
      _app(
        ReportingFinanceDetailView(
          row: _financeData['rows']![0] as Map<String, dynamic>,
          onBack: () => backed = true,
        ),
      ),
    );
    await tester.tap(find.text('К отчёту'));

    expect(
      find.byKey(const ValueKey('reporting-finance-detail')),
      findsOneWidget,
    );
    expect(find.text('Фактическая выручка'), findsOneWidget);
    expect(find.text('8 000,00 ₽'), findsOneWidget);
    expect(backed, isTrue);
  });

  testWidgets('export actions preserve report key format and disabled state', (
    tester,
  ) async {
    final exports = <(String, String)>[];
    await tester.pumpWidget(
      _app(
        _summaryView(
          tester,
          state: _readyState(
            finance: const ReportingSection(data: _financeData),
          ),
          canReadSchoolFinance: true,
          onExport: (reportKey, format) => exports.add((reportKey, format)),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'XLSX'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'CSV'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Финансы XLSX'));
    expect(exports, [
      ('client_status', 'xlsx'),
      ('client_status', 'csv'),
      ('school_finance', 'xlsx'),
    ]);

    exports.clear();
    await tester.pumpWidget(
      _app(
        _summaryView(
          tester,
          state: _readyState(),
          canReadSchoolFinance: true,
          exporting: true,
          exportStatus: 'Подготавливаем файл…',
        ),
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'XLSX'))
          .onPressed,
      isNull,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('report-export-progress')),
      250,
    );
    expect(find.text('Подготавливаем файл…'), findsOneWidget);
    expect(exports, isEmpty);
  });

  testWidgets('drilldown renders loading error retry and empty states', (
    tester,
  ) async {
    var retried = false;
    await tester.pumpWidget(
      _app(
        ReportingDrilldownView(
          loading: true,
          error: null,
          data: null,
          lessonDrilldown: false,
          onRetry: () => retried = true,
          onBack: () {},
          onOpenEntity: (_) {},
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(
      _app(
        ReportingDrilldownView(
          loading: false,
          error: StateError('offline'),
          data: null,
          lessonDrilldown: false,
          onRetry: () => retried = true,
          onBack: () {},
          onOpenEntity: (_) {},
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('reporting-error')), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    expect(retried, isTrue);

    await tester.pumpWidget(
      _app(
        ReportingDrilldownView(
          loading: false,
          error: null,
          data: const {'total': 0, 'items': <dynamic>[]},
          lessonDrilldown: false,
          onRetry: () {},
          onBack: () {},
          onOpenEntity: (_) {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Клиенты: 0'), findsOneWidget);
    expect(find.text('Список пуст'), findsOneWidget);
  });

  testWidgets('drilldown forwards exact canonical entity link', (tester) async {
    EntityLink? opened;
    var backed = false;
    await tester.pumpWidget(
      _app(
        ReportingDrilldownView(
          loading: false,
          error: null,
          data: const {
            'total': 1,
            'items': [
              {
                'displayName': 'Алина Тестова',
                'statusLabel': 'Новый',
                'entityLink': {
                  'version': 1,
                  'entityType': 'student',
                  'entityId': 'student-1',
                  'optionalFocus': {
                    'focus': 'profile',
                    'filter': {'tab': 'overview'},
                  },
                },
              },
            ],
          },
          lessonDrilldown: false,
          onRetry: () {},
          onBack: () => backed = true,
          onOpenEntity: (link) => opened = link,
        ),
      ),
    );

    await tester.tap(find.text('Алина Тестова'));
    expect(opened?.version, 1);
    expect(opened?.rawEntityType, 'student');
    expect(opened?.entityType, EntityLinkType.client);
    expect(opened?.entityId, 'student-1');
    expect(opened?.optionalFocus?.focus, 'profile');
    expect(opened?.optionalFocus?.filter, const {'tab': 'overview'});
    expect(opened?.presentation?.primary, 'Алина Тестова');

    await tester.tap(find.text('К отчёту'));
    expect(backed, isTrue);
  });

  testWidgets('summary keeps narrow and desktop layouts overflow-free', (
    tester,
  ) async {
    for (final size in const [Size(390, 844), Size(1200, 800)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        _app(
          _summaryView(
            tester,
            state: _readyState(
              finance: const ReportingSection(data: _financeData),
            ),
            canReadSchoolFinance: true,
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '$size');
      expect(find.byKey(const ValueKey('reporting-content')), findsOneWidget);
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });
}

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

ReportingSummaryView _summaryView(
  WidgetTester tester, {
  required ReportingState state,
  required bool canReadSchoolFinance,
  bool exporting = false,
  String? exportStatus,
  Object? exportError,
  ValueChanged<ReportingSectionKey>? onRetry,
  ReportingOpenDrilldown? onOpenDrilldown,
  ValueChanged<EntityLink>? onOpenEntity,
  ValueChanged<Map<String, dynamic>>? onSelectFinance,
  ReportingExportCallback? onExport,
}) {
  final controller = ScrollController();
  addTearDown(controller.dispose);
  return ReportingSummaryView(
    state: state,
    canReadSchoolFinance: canReadSchoolFinance,
    scrollController: controller,
    exporting: exporting,
    exportStatus: exportStatus,
    exportError: exportError,
    onRefresh: _noopRefresh,
    onRetry: onRetry ?? (_) {},
    onOpenDrilldown: onOpenDrilldown ?? (_, {expectedCount}) {},
    onOpenEntity: onOpenEntity ?? (_) {},
    onSelectFinance: onSelectFinance ?? (_) {},
    onExport: onExport ?? (_, _) {},
  );
}

Future<void> _noopRefresh() async {}

ReportingState _readyState({ReportingSection<Map<String, dynamic>>? finance}) =>
    _state(
      lessons: const ReportingSection(data: _lessonData),
      status: const ReportingSection(data: _statusData),
      tasks: const ReportingSection(data: _taskData),
      finance: finance,
    );

ReportingState _state({
  bool forbidden = false,
  ReportingSection<Map<String, dynamic>>? lessons,
  ReportingSection<Map<String, dynamic>>? status,
  ReportingSection<Map<String, dynamic>>? tasks,
  ReportingSection<Map<String, dynamic>>? finance,
}) => ReportingState(
  loading: false,
  forbidden: forbidden,
  lessons: lessons ?? const ReportingSection(),
  status: status ?? const ReportingSection(),
  tasks: tasks ?? const ReportingSection(),
  finance: finance ?? const ReportingSection(forbidden: true),
);

const _lessonData = <String, dynamic>{
  'totalLessons': 10,
  'successfulLessons': 8,
  'successRate': 0.8,
  'drilldown': {
    'entityType': 'lesson_list',
    'entityId': 'successfully_completed',
  },
};

const _statusData = <String, dynamic>{
  'items': [
    {
      'label': 'Новые',
      'clientType': 'lead',
      'count': 2,
      'drilldown': {'entityType': 'client_status_list', 'entityId': 'lead:new'},
    },
  ],
};

const _taskData = <String, dynamic>{
  'counters': {'open': 3, 'overdue': 1},
};

const _financeData = <String, dynamic>{
  'rows': [
    {
      'monthStart': '2026-07-01',
      'revenueMinor': '800000',
      'expensesMinor': '160000',
      'successfulLessons': 8,
      'link': {'entityType': 'school_finance_month', 'entityId': '2026-07-01'},
    },
  ],
};
