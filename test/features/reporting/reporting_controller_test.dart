import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_controller.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_data_source.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_models.dart';

void main() {
  final firstFilter = DashboardFilter(
    from: _firstFrom,
    to: _firstTo,
    branchId: 'branch-a',
  );
  final secondFilter = DashboardFilter(
    from: _secondFrom,
    to: _secondTo,
    branchId: 'branch-b',
  );

  test('forbidden status access starts zero section requests', () async {
    final source = _ControlledReportingDataSource();
    final controller = ReportingController(
      dataSource: source,
      canReadStatus: false,
      canReadSchoolFinance: true,
    );
    addTearDown(controller.dispose);

    await controller.load(firstFilter);

    expect(source.totalSummaryCalls, 0);
    expect(controller.state.forbidden, isTrue);
    expect(controller.state.finance.forbidden, isTrue);
  });

  test('denied finance starts exactly the three permitted requests', () async {
    final source = _ControlledReportingDataSource();
    final controller = ReportingController(
      dataSource: source,
      canReadStatus: true,
      canReadSchoolFinance: false,
    );
    addTearDown(controller.dispose);

    final loading = controller.load(firstFilter);

    expect(source.statusCalls, hasLength(1));
    expect(source.lessonCalls, hasLength(1));
    expect(source.taskCalls, hasLength(1));
    expect(source.financeCalls, isEmpty);
    expect(controller.state.finance.forbidden, isTrue);
    source.statusCalls.single.succeed({'status': 'ready'});
    source.lessonCalls.single.succeed({'lessons': 'ready'});
    source.taskCalls.single.succeed({'tasks': 'ready'});
    await loading;
  });

  test('one failed section does not erase successful sibling data', () async {
    final source = _ControlledReportingDataSource();
    final controller = ReportingController(
      dataSource: source,
      canReadStatus: true,
      canReadSchoolFinance: true,
    );
    addTearDown(controller.dispose);

    final loading = controller.load(firstFilter);
    source.statusCalls.single.succeed({'count': 3});
    source.lessonCalls.single.fail(StateError('offline'));
    source.taskCalls.single.succeed({'open': 4});
    source.financeCalls.single.succeed({'revenue': 5});
    await loading;

    expect(controller.state.status.data, {'count': 3});
    expect(controller.state.lessons.error, isA<StateError>());
    expect(controller.state.tasks.data, {'open': 4});
    expect(controller.state.finance.data, {'revenue': 5});
  });

  test('refresh and failure retain the last successful section data', () async {
    final source = _ControlledReportingDataSource();
    final controller = ReportingController(
      dataSource: source,
      canReadStatus: true,
      canReadSchoolFinance: false,
    );
    addTearDown(controller.dispose);

    final firstLoad = controller.load(firstFilter);
    source.statusCalls[0].succeed({'count': 3});
    source.lessonCalls[0].succeed({'lessons': 8});
    source.taskCalls[0].succeed({'open': 4});
    await firstLoad;

    final refresh = controller.load(firstFilter);
    expect(controller.state.status.loading, isTrue);
    expect(controller.state.status.data, {'count': 3});
    source.statusCalls[1].fail(StateError('refresh failed'));
    source.lessonCalls[1].succeed({'lessons': 9});
    source.taskCalls[1].succeed({'open': 5});
    await refresh;

    expect(controller.state.status.loading, isFalse);
    expect(controller.state.status.data, {'count': 3});
    expect(controller.state.status.error, isA<StateError>());
  });

  test('latest filter wins over stale success and stale failure', () async {
    final source = _ControlledReportingDataSource();
    final controller = ReportingController(
      dataSource: source,
      canReadStatus: true,
      canReadSchoolFinance: true,
    );
    addTearDown(controller.dispose);

    final oldLoad = controller.load(firstFilter);
    final newLoad = controller.load(secondFilter);

    source.statusCalls[1].succeed({'filter': 'new-status'});
    source.lessonCalls[1].succeed({'filter': 'new-lessons'});
    source.taskCalls[1].succeed({'filter': 'new-tasks'});
    source.financeCalls[1].succeed({'filter': 'new-finance'});
    await newLoad;

    source.statusCalls[0].succeed({'filter': 'stale-status'});
    source.lessonCalls[0].fail(StateError('stale lesson failure'));
    source.taskCalls[0].succeed({'filter': 'stale-tasks'});
    source.financeCalls[0].fail(StateError('stale finance failure'));
    await oldLoad;

    expect(controller.state.status.data, {'filter': 'new-status'});
    expect(controller.state.status.error, isNull);
    expect(controller.state.lessons.data, {'filter': 'new-lessons'});
    expect(controller.state.lessons.error, isNull);
    expect(controller.state.tasks.data, {'filter': 'new-tasks'});
    expect(controller.state.finance.data, {'filter': 'new-finance'});
    expect(controller.state.finance.error, isNull);
    expect(source.statusCalls[0].filter, firstFilter);
    expect(source.statusCalls[1].filter, secondFilter);
    expect(source.financeCalls[0].filter, firstFilter);
    expect(source.financeCalls[1].filter, secondFilter);
  });

  test(
    'section retry clears only that section error and loading state',
    () async {
      final source = _ControlledReportingDataSource();
      final controller = ReportingController(
        dataSource: source,
        canReadStatus: true,
        canReadSchoolFinance: false,
      );
      addTearDown(controller.dispose);

      final firstLoad = controller.load(firstFilter);
      source.statusCalls[0].fail(StateError('status failed'));
      source.lessonCalls[0].fail(StateError('lessons failed'));
      source.taskCalls[0].succeed({'open': 4});
      await firstLoad;
      final lessonError = controller.state.lessons.error;

      final retry = controller.reloadSection(
        ReportingSectionKey.status,
        firstFilter,
      );

      expect(controller.state.status.loading, isTrue);
      expect(controller.state.status.error, isNull);
      expect(controller.state.lessons.loading, isFalse);
      expect(controller.state.lessons.error, same(lessonError));
      expect(source.statusCalls, hasLength(2));
      expect(source.lessonCalls, hasLength(1));
      source.statusCalls[1].succeed({'count': 6});
      await retry;

      expect(controller.state.status.data, {'count': 6});
      expect(controller.state.status.loading, isFalse);
      expect(controller.state.lessons.error, same(lessonError));
    },
  );

  test(
    'later same-section retry wins after the older retry completes',
    () async {
      final source = _ControlledReportingDataSource();
      final controller = ReportingController(
        dataSource: source,
        canReadStatus: true,
        canReadSchoolFinance: false,
      );
      addTearDown(controller.dispose);
      final initial = controller.load(firstFilter);
      source.statusCalls[0].succeed({'count': 1});
      source.lessonCalls[0].succeed({'lessons': 1});
      source.taskCalls[0].succeed({'open': 1});
      await initial;

      final olderRetry = controller.reloadSection(
        ReportingSectionKey.status,
        firstFilter,
      );
      final newerRetry = controller.reloadSection(
        ReportingSectionKey.status,
        firstFilter,
      );
      source.statusCalls[2].succeed({'count': 3});
      await newerRetry;
      source.statusCalls[1].succeed({'count': 2});
      await olderRetry;

      expect(controller.state.status.data, {'count': 3});
      expect(controller.state.status.error, isNull);
    },
  );

  test('concurrent retries for distinct sections remain independent', () async {
    final source = _ControlledReportingDataSource();
    final controller = ReportingController(
      dataSource: source,
      canReadStatus: true,
      canReadSchoolFinance: false,
    );
    addTearDown(controller.dispose);
    final initial = controller.load(firstFilter);
    source.statusCalls[0].succeed({'count': 1});
    source.lessonCalls[0].succeed({'lessons': 1});
    source.taskCalls[0].succeed({'open': 1});
    await initial;

    final statusRetry = controller.reloadSection(
      ReportingSectionKey.status,
      firstFilter,
    );
    final lessonRetry = controller.reloadSection(
      ReportingSectionKey.lessons,
      firstFilter,
    );
    source.lessonCalls[1].succeed({'lessons': 4});
    await lessonRetry;
    expect(controller.state.status.loading, isTrue);
    expect(controller.state.lessons.data, {'lessons': 4});
    source.statusCalls[1].succeed({'count': 3});
    await statusRetry;

    expect(controller.state.status.data, {'count': 3});
    expect(controller.state.lessons.data, {'lessons': 4});
    expect(controller.state.tasks.data, {'open': 1});
  });

  test('whole reload supersedes an in-flight section retry', () async {
    final source = _ControlledReportingDataSource();
    final controller = ReportingController(
      dataSource: source,
      canReadStatus: true,
      canReadSchoolFinance: false,
    );
    addTearDown(controller.dispose);
    final initial = controller.load(firstFilter);
    source.statusCalls[0].succeed({'filter': 'initial'});
    source.lessonCalls[0].succeed({'lessons': 1});
    source.taskCalls[0].succeed({'open': 1});
    await initial;

    final retry = controller.reloadSection(
      ReportingSectionKey.status,
      firstFilter,
    );
    final reload = controller.load(secondFilter);
    source.statusCalls[2].succeed({'filter': 'reload'});
    source.lessonCalls[1].succeed({'lessons': 2});
    source.taskCalls[1].succeed({'open': 2});
    await reload;
    source.statusCalls[1].fail(StateError('stale retry failure'));
    await retry;

    expect(controller.state.status.data, {'filter': 'reload'});
    expect(controller.state.status.error, isNull);
  });

  test(
    'filter-mismatched section retry falls back to a whole reload',
    () async {
      final source = _ControlledReportingDataSource();
      final controller = ReportingController(
        dataSource: source,
        canReadStatus: true,
        canReadSchoolFinance: true,
      );
      addTearDown(controller.dispose);
      final initial = controller.load(firstFilter);
      source.statusCalls[0].succeed({'filter': 'initial'});
      source.lessonCalls[0].succeed({'lessons': 1});
      source.taskCalls[0].succeed({'open': 1});
      source.financeCalls[0].succeed({'finance': 1});
      await initial;

      final mismatchedRetry = controller.reloadSection(
        ReportingSectionKey.status,
        secondFilter,
      );

      expect(source.statusCalls, hasLength(2));
      expect(source.lessonCalls, hasLength(2));
      expect(source.taskCalls, hasLength(2));
      expect(source.financeCalls, hasLength(2));
      expect(source.statusCalls[1].filter, secondFilter);
      expect(source.lessonCalls[1].filter, secondFilter);
      expect(source.taskCalls[1].filter, isNull);
      expect(source.financeCalls[1].filter, secondFilter);
      source.statusCalls[1].succeed({'filter': 'replacement'});
      source.lessonCalls[1].succeed({'lessons': 2});
      source.taskCalls[1].succeed({'open': 2});
      source.financeCalls[1].succeed({'finance': 2});
      await mismatchedRetry;

      expect(controller.state.status.data, {'filter': 'replacement'});
      expect(controller.state.lessons.data, {'lessons': 2});
      expect(controller.state.tasks.data, {'open': 2});
      expect(controller.state.finance.data, {'finance': 2});
    },
  );

  test(
    'dispose ignores late completions without notifying listeners',
    () async {
      final source = _ControlledReportingDataSource();
      final controller = ReportingController(
        dataSource: source,
        canReadStatus: true,
        canReadSchoolFinance: false,
      );
      var notifications = 0;
      controller.addListener(() => notifications++);

      final loading = controller.load(firstFilter);
      expect(notifications, 1);
      controller.dispose();
      source.statusCalls.single.succeed({'count': 3});
      source.lessonCalls.single.fail(StateError('late failure'));
      source.taskCalls.single.succeed({'open': 4});

      await loading;
      expect(notifications, 1);
    },
  );

  test('open-task summary remains independent from dashboard filter', () async {
    final source = _ControlledReportingDataSource();
    final controller = ReportingController(
      dataSource: source,
      canReadStatus: true,
      canReadSchoolFinance: false,
    );
    addTearDown(controller.dispose);

    final loading = controller.load(secondFilter);

    expect(source.statusCalls.single.filter, secondFilter);
    expect(source.lessonCalls.single.filter, secondFilter);
    expect(source.taskCalls.single.filter, isNull);
    source.statusCalls.single.succeed({'status': 'ready'});
    source.lessonCalls.single.succeed({'lessons': 'ready'});
    source.taskCalls.single.succeed({'tasks': 'ready'});
    await loading;
  });
}

final _firstFrom = DateTime(2026, 8, 1);
final _firstTo = DateTime(2026, 8, 8);
final _secondFrom = DateTime(2026, 8, 9);
final _secondTo = DateTime(2026, 8, 16);

class _SectionCall {
  _SectionCall(this.filter);

  final DashboardFilter? filter;
  final Completer<Map<String, dynamic>> _result = Completer();

  Future<Map<String, dynamic>> get future => _result.future;

  void succeed(Map<String, dynamic> value) => _result.complete(value);

  void fail(Object error) => _result.completeError(error);
}

class _ControlledReportingDataSource implements ReportingDataSource {
  final statusCalls = <_SectionCall>[];
  final lessonCalls = <_SectionCall>[];
  final taskCalls = <_SectionCall>[];
  final financeCalls = <_SectionCall>[];

  int get totalSummaryCalls =>
      statusCalls.length +
      lessonCalls.length +
      taskCalls.length +
      financeCalls.length;

  @override
  Future<Map<String, dynamic>> loadClientStatus(DashboardFilter filter) {
    final call = _SectionCall(filter);
    statusCalls.add(call);
    return call.future;
  }

  @override
  Future<Map<String, dynamic>> loadLessonSuccess(DashboardFilter filter) {
    final call = _SectionCall(filter);
    lessonCalls.add(call);
    return call.future;
  }

  @override
  Future<Map<String, dynamic>> loadOpenTaskSummary() {
    final call = _SectionCall(null);
    taskCalls.add(call);
    return call.future;
  }

  @override
  Future<Map<String, dynamic>> loadSchoolFinance(DashboardFilter filter) {
    final call = _SectionCall(filter);
    financeCalls.add(call);
    return call.future;
  }

  @override
  Future<Map<String, dynamic>> loadDrilldown(
    EntityLink link,
    DashboardFilter filter,
  ) => throw UnimplementedError();

  @override
  Future<V4ReportExportResult> requestExport({
    required String reportKey,
    required String format,
    required Map<String, dynamic> filter,
  }) => throw UnimplementedError();

  @override
  Future<V4ReportExportJob> getExportJob(String jobId) =>
      throw UnimplementedError();

  @override
  Future<List<int>> downloadExport(String jobId) => throw UnimplementedError();
}
