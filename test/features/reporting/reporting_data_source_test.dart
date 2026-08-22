import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_data_source.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_models.dart';

final _sourceProvider = Provider<ReportingDataSource>(
  (ref) => MagicCrmReportingDataSource(ref),
);

void main() {
  test('dashboard filter preserves analytics and workspace mappings', () {
    final filter = DashboardFilter(
      from: DateTime.utc(2026, 8, 1),
      to: DateTime.utc(2026, 8, 22),
      branchId: 'branch-1',
    );

    expect(filter.apiFilter, {
      'from': '2026-08-01T00:00:00.000Z',
      'to': '2026-08-23T00:00:00.000Z',
      'branchId': 'branch-1',
    });
    expect(filter.toContextViewState().filters, {
      'dashboardFrom': '2026-08-01T00:00:00.000Z',
      'dashboardTo': '2026-08-22T00:00:00.000Z',
      'branchId': 'branch-1',
    });
    expect(
      DashboardFilter.fromContext(
        ContextViewState(
          filters: {
            'dashboardFrom': '2026-08-01T00:00:00.000Z',
            'dashboardTo': '2026-08-22T00:00:00.000Z',
            'branchId': 'workspace-branch',
          },
        ),
        const {'branchId': 'direct-branch'},
      ),
      DashboardFilter(
        from: DateTime(2026, 8, 1),
        to: DateTime(2026, 8, 22),
        branchId: 'direct-branch',
      ),
    );
    expect(
      filter.copyWithRange(
        DateTimeRange(
          start: DateTime(2026, 7, 2, 13),
          end: DateTime(2026, 7, 9, 21),
        ),
      ),
      DashboardFilter(
        from: DateTime(2026, 7, 2),
        to: DateTime(2026, 7, 9),
        branchId: 'branch-1',
      ),
    );
    expect(filter.copyWithBranch(null).branchId, isNull);
  });

  test('adapter forwards every live summary and drilldown filter', () async {
    final api = _RecordingReportingApi();
    final container = ProviderContainer(
      overrides: [magicApiClientProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    final source = container.read(_sourceProvider);
    final filter = DashboardFilter(
      from: DateTime.utc(2026, 8, 1),
      to: DateTime.utc(2026, 8, 22),
      branchId: 'branch-1',
    );

    await source.loadClientStatus(filter);
    await source.loadLessonSuccess(filter);
    await source.loadOpenTaskSummary();
    await source.loadSchoolFinance(filter);
    await source.loadDrilldown(
      EntityLink(
        entityType: EntityLinkType.report,
        entityId: 'lead:new',
        rawEntityType: 'client_status_list',
        optionalFocus: EntityLinkFocus(
          filter: {'version': 1, 'clientType': 'lead', 'status': 'new'},
        ),
      ),
      filter,
    );
    await source.loadDrilldown(
      EntityLink(
        entityType: EntityLinkType.lesson,
        entityId: 'successfully_completed',
        rawEntityType: 'lesson_list',
        optionalFocus: EntityLinkFocus(
          filter: {'version': 1, 'status': 'successfully_completed'},
        ),
      ),
      filter,
    );

    const analyticsFilter = {
      'branchId': 'branch-1',
      'from': '2026-08-01T00:00:00.000Z',
      'to': '2026-08-23T00:00:00.000Z',
    };
    expect(
      api.getQuery('/analytics/v4/client-status/summary'),
      analyticsFilter,
    );
    expect(api.getQuery('/analytics/v4/lesson-success'), analyticsFilter);
    expect(api.getQuery('/analytics/v4/school-finance'), analyticsFilter);
    expect(api.getQuery('/crm/shared-tasks'), {'limit': 1, 'state': 'open'});
    expect(api.getQuery('/analytics/v4/client-status/clients'), {
      ...analyticsFilter,
      'clientType': 'lead',
      'status': 'new',
      'limit': 50,
      'offset': 0,
    });
    expect(api.getQuery('/analytics/v4/lesson-success/lessons'), {
      ...analyticsFilter,
      'limit': 50,
      'offset': 0,
    });
  });

  test('adapter delegates export request job read and download', () async {
    final api = _RecordingReportingApi();
    final container = ProviderContainer(
      overrides: [magicApiClientProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    final source = container.read(_sourceProvider);

    final requested = await source.requestExport(
      reportKey: 'client_status',
      format: 'xlsx',
      filter: const {
        'branchId': 'branch-1',
        'from': '2026-08-01T00:00:00.000Z',
        'to': '2026-08-23T00:00:00.000Z',
        'clientType': 'lead',
        'status': 'new',
        'q': 'Алина',
        'version': 1,
      },
    );
    final job = await source.getExportJob(requested.jobId!);
    final bytes = await source.downloadExport(requested.jobId!);

    expect(api.postData('/analytics/v4/exports'), {
      'reportKey': 'client_status',
      'format': 'xlsx',
      'clientType': 'lead',
      'status': 'new',
      'branchId': 'branch-1',
      'from': '2026-08-01T00:00:00.000Z',
      'to': '2026-08-23T00:00:00.000Z',
      'q': 'Алина',
    });
    expect(api.getQuery('/analytics/v4/exports/job-1'), isEmpty);
    expect(api.downloadPaths, ['/analytics/v4/exports/job-1/download']);
    expect(job.status, 'ready');
    expect(bytes, [0x50, 0x4b, 0x03, 0x04]);
  });
}

class _RecordedRequest {
  const _RecordedRequest({
    required this.method,
    required this.path,
    this.data,
    this.queryParameters,
  });

  final String method;
  final String path;
  final Object? data;
  final Map<String, dynamic>? queryParameters;
}

class _RecordingReportingApi extends MagicApiClient {
  _RecordingReportingApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final requests = <_RecordedRequest>[];
  final downloadPaths = <String>[];

  Map<String, dynamic> getQuery(String path) => Map<String, dynamic>.from(
    requests.lastWhere((request) => request.path == path).queryParameters ??
        const {},
  );

  Map<String, dynamic> postData(String path) => Map<String, dynamic>.from(
    requests.lastWhere((request) => request.path == path).data! as Map,
  );

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
    requests.add(
      _RecordedRequest(
        method: method,
        path: path,
        data: data,
        queryParameters: queryParameters,
      ),
    );
    if (path == '/analytics/v4/exports/job-1') {
      return <String, dynamic>{
            'id': 'job-1',
            'status': 'ready',
            'rowCount': 42,
            'downloadReady': true,
            'filename': 'client-status.xlsx',
          }
          as T;
    }
    return <String, dynamic>{} as T;
  }

  @override
  Future<List<int>> postBytes(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    requests.add(
      _RecordedRequest(
        method: 'POST',
        path: path,
        data: data,
        queryParameters: queryParameters,
      ),
    );
    return utf8.encode(
      jsonEncode({
        'mode': 'async',
        'jobId': 'job-1',
        'status': 'queued',
        'rowCount': 42,
      }),
    );
  }

  @override
  Future<List<int>> downloadBytes(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    downloadPaths.add(path);
    return [0x50, 0x4b, 0x03, 0x04];
  }
}
