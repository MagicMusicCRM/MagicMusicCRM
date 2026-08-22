import 'package:flutter/foundation.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_data_source.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_models.dart';

enum ReportingSectionKey { status, lessons, tasks, finance }

@immutable
class ReportingSection<T> {
  const ReportingSection({
    this.data,
    this.loading = false,
    this.error,
    this.forbidden = false,
  });

  final T? data;
  final bool loading;
  final Object? error;
  final bool forbidden;
}

@immutable
class ReportingState {
  const ReportingState({
    required this.loading,
    required this.forbidden,
    required this.status,
    required this.lessons,
    required this.tasks,
    required this.finance,
  });

  factory ReportingState.initial() => const ReportingState(
    loading: true,
    forbidden: false,
    status: ReportingSection(),
    lessons: ReportingSection(),
    tasks: ReportingSection(),
    finance: ReportingSection(),
  );

  final bool loading;
  final bool forbidden;
  final ReportingSection<Map<String, dynamic>> status;
  final ReportingSection<Map<String, dynamic>> lessons;
  final ReportingSection<Map<String, dynamic>> tasks;
  final ReportingSection<Map<String, dynamic>> finance;
}

class ReportingController extends ChangeNotifier {
  ReportingController({
    required this.dataSource,
    required this.canReadStatus,
    required this.canReadSchoolFinance,
  });

  final ReportingDataSource dataSource;
  final bool canReadStatus;
  final bool canReadSchoolFinance;

  ReportingState _state = ReportingState.initial();
  ReportingState get state => _state;

  DashboardFilter? _activeFilter;
  int _revision = 0;
  final Map<ReportingSectionKey, int> _sectionRevisions = {
    for (final key in ReportingSectionKey.values) key: 0,
  };
  bool _disposed = false;

  Future<void> load(DashboardFilter filter) async {
    if (_disposed) return;
    final revision = ++_revision;
    _activeFilter = filter;
    final sectionRevisions = {
      for (final key in ReportingSectionKey.values)
        key: _nextSectionRevision(key),
    };

    if (!canReadStatus) {
      const forbidden = ReportingSection<Map<String, dynamic>>(forbidden: true);
      _state = const ReportingState(
        loading: false,
        forbidden: true,
        status: forbidden,
        lessons: forbidden,
        tasks: forbidden,
        finance: forbidden,
      );
      _notify();
      return;
    }

    _state = ReportingState(
      loading: false,
      forbidden: false,
      status: _loading(_state.status),
      lessons: _loading(_state.lessons),
      tasks: _loading(_state.tasks),
      finance: canReadSchoolFinance
          ? _loading(_state.finance)
          : const ReportingSection(forbidden: true),
    );
    _notify();

    await Future.wait([
      _loadSection(
        key: ReportingSectionKey.status,
        revision: revision,
        sectionRevision: sectionRevisions[ReportingSectionKey.status]!,
        loader: () => dataSource.loadClientStatus(filter),
      ),
      _loadSection(
        key: ReportingSectionKey.lessons,
        revision: revision,
        sectionRevision: sectionRevisions[ReportingSectionKey.lessons]!,
        loader: () => dataSource.loadLessonSuccess(filter),
      ),
      _loadSection(
        key: ReportingSectionKey.tasks,
        revision: revision,
        sectionRevision: sectionRevisions[ReportingSectionKey.tasks]!,
        loader: dataSource.loadOpenTaskSummary,
      ),
      if (canReadSchoolFinance)
        _loadSection(
          key: ReportingSectionKey.finance,
          revision: revision,
          sectionRevision: sectionRevisions[ReportingSectionKey.finance]!,
          loader: () => dataSource.loadSchoolFinance(filter),
        ),
    ]);
  }

  Future<void> reloadSection(
    ReportingSectionKey key,
    DashboardFilter filter,
  ) async {
    if (_disposed) return;
    if (!canReadStatus || _activeFilter != filter || _revision == 0) {
      await load(filter);
      return;
    }
    if (key == ReportingSectionKey.finance && !canReadSchoolFinance) return;

    final revision = _revision;
    final sectionRevision = _nextSectionRevision(key);
    _state = _replaceSection(_state, key, _loading(_section(_state, key)));
    _notify();
    await _loadSection(
      key: key,
      revision: revision,
      sectionRevision: sectionRevision,
      loader: _loader(key, filter),
    );
  }

  Future<void> _loadSection({
    required ReportingSectionKey key,
    required int revision,
    required int sectionRevision,
    required Future<Map<String, dynamic>> Function() loader,
  }) async {
    try {
      final data = await loader();
      if (!_isCurrent(key, revision, sectionRevision)) return;
      _state = _replaceSection(_state, key, ReportingSection(data: data));
      _notify();
    } catch (error) {
      if (!_isCurrent(key, revision, sectionRevision)) return;
      final current = _section(_state, key);
      _state = _replaceSection(
        _state,
        key,
        ReportingSection(data: current.data, error: error),
      );
      _notify();
    }
  }

  Future<Map<String, dynamic>> Function() _loader(
    ReportingSectionKey key,
    DashboardFilter filter,
  ) => switch (key) {
    ReportingSectionKey.status => () => dataSource.loadClientStatus(filter),
    ReportingSectionKey.lessons => () => dataSource.loadLessonSuccess(filter),
    ReportingSectionKey.tasks => dataSource.loadOpenTaskSummary,
    ReportingSectionKey.finance => () => dataSource.loadSchoolFinance(filter),
  };

  bool _isCurrent(ReportingSectionKey key, int revision, int sectionRevision) =>
      !_disposed &&
      revision == _revision &&
      sectionRevision == _sectionRevisions[key];

  int _nextSectionRevision(ReportingSectionKey key) =>
      _sectionRevisions.update(key, (value) => value + 1);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _revision++;
    for (final key in ReportingSectionKey.values) {
      _nextSectionRevision(key);
    }
    super.dispose();
  }
}

ReportingSection<Map<String, dynamic>> _loading(
  ReportingSection<Map<String, dynamic>> current,
) => ReportingSection(data: current.data, loading: true);

ReportingSection<Map<String, dynamic>> _section(
  ReportingState state,
  ReportingSectionKey key,
) => switch (key) {
  ReportingSectionKey.status => state.status,
  ReportingSectionKey.lessons => state.lessons,
  ReportingSectionKey.tasks => state.tasks,
  ReportingSectionKey.finance => state.finance,
};

ReportingState _replaceSection(
  ReportingState state,
  ReportingSectionKey key,
  ReportingSection<Map<String, dynamic>> section,
) => ReportingState(
  loading: state.loading,
  forbidden: state.forbidden,
  status: key == ReportingSectionKey.status ? section : state.status,
  lessons: key == ReportingSectionKey.lessons ? section : state.lessons,
  tasks: key == ReportingSectionKey.tasks ? section : state.tasks,
  finance: key == ReportingSectionKey.finance ? section : state.finance,
);
