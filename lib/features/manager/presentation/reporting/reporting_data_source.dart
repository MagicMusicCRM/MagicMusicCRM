import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_models.dart';

export 'package:magic_music_crm/core/services/magic_crm_service.dart'
    show V4ReportExportJob, V4ReportExportResult;

abstract interface class ReportingDataSource {
  Future<Map<String, dynamic>> loadClientStatus(DashboardFilter filter);

  Future<Map<String, dynamic>> loadLessonSuccess(DashboardFilter filter);

  Future<Map<String, dynamic>> loadOpenTaskSummary();

  Future<Map<String, dynamic>> loadSchoolFinance(DashboardFilter filter);

  Future<Map<String, dynamic>> loadDrilldown(
    EntityLink link,
    DashboardFilter filter,
  );

  Future<V4ReportExportResult> requestExport({
    required String reportKey,
    required String format,
    required Map<String, dynamic> filter,
  });

  Future<V4ReportExportJob> getExportJob(String jobId);

  Future<List<int>> downloadExport(String jobId);
}

final reportingDataSourceProvider = Provider<ReportingDataSource>(
  (ref) => MagicCrmReportingDataSource(ref),
);

class MagicCrmReportingDataSource implements ReportingDataSource {
  MagicCrmReportingDataSource(Ref ref) : _ref = ref;

  final Ref _ref;

  MagicCrmService get _crm => _ref.read(magicCrmServiceProvider);

  @override
  Future<Map<String, dynamic>> loadClientStatus(DashboardFilter filter) {
    final apiFilter = filter.apiFilter;
    return _crm.getV4ClientStatusSummary(
      branchId: apiFilter['branchId']?.toString(),
      from: apiFilter['from']?.toString(),
      to: apiFilter['to']?.toString(),
    );
  }

  @override
  Future<Map<String, dynamic>> loadLessonSuccess(DashboardFilter filter) {
    final apiFilter = filter.apiFilter;
    return _crm.getV4LessonSuccess(
      branchId: apiFilter['branchId']?.toString(),
      from: apiFilter['from']?.toString(),
      to: apiFilter['to']?.toString(),
    );
  }

  @override
  Future<Map<String, dynamic>> loadOpenTaskSummary() {
    return _crm.listSharedTasks(state: 'open', limit: 1);
  }

  @override
  Future<Map<String, dynamic>> loadSchoolFinance(DashboardFilter filter) {
    final apiFilter = filter.apiFilter;
    return _crm.getV4SchoolFinance(
      branchId: apiFilter['branchId']?.toString(),
      from: apiFilter['from']?.toString(),
      to: apiFilter['to']?.toString(),
    );
  }

  @override
  Future<Map<String, dynamic>> loadDrilldown(
    EntityLink link,
    DashboardFilter filter,
  ) {
    final apiFilter = {...filter.apiFilter, ...?link.optionalFocus?.filter};
    return link.rawEntityType == 'lesson_list'
        ? _crm.getV4LessonSuccessList(filter: apiFilter)
        : _crm.getV4ClientStatusList(filter: apiFilter);
  }

  @override
  Future<V4ReportExportResult> requestExport({
    required String reportKey,
    required String format,
    required Map<String, dynamic> filter,
  }) {
    return _crm.requestV4ReportExport(
      reportKey: reportKey,
      format: format,
      filter: filter,
    );
  }

  @override
  Future<V4ReportExportJob> getExportJob(String jobId) {
    return _crm.getV4ReportExportJob(jobId);
  }

  @override
  Future<List<int>> downloadExport(String jobId) {
    return _crm.downloadV4ReportExport(jobId);
  }
}
