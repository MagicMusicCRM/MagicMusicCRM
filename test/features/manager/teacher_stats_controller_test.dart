import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/magic_settings_service.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/report_export_files.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/teacher_stats_controller.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/teacher_stats_models.dart';

class _RecordedRequest {
  const _RecordedRequest(this.path, this.parameters);

  final String path;
  final Map<String, dynamic> parameters;
}

class _RecordedPatch {
  const _RecordedPatch(this.path, this.body);

  final String path;
  final Map<String, dynamic> body;
}

class _FakeApiClient extends MagicApiClient {
  _FakeApiClient({this.exportCsv = '\ufeffteacher,hours\nИван,1'})
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final String exportCsv;
  final List<_RecordedRequest> gets = [];
  final List<_RecordedPatch> patches = [];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    gets.add(_RecordedRequest(path, {...?queryParameters}));
    if (path == '/crm/reports/teacher-stats/export') {
      return exportCsv as T;
    }
    if (path == '/crm/reports/teacher-stats') {
      return <String, dynamic>{
            'items': <dynamic>[],
            'totals': <String, dynamic>{},
          }
          as T;
    }
    if (path == '/settings/crm-custom-fields') {
      return <String, dynamic>{'fields': <dynamic>[]} as T;
    }
    return <String, dynamic>{'items': <dynamic>[]} as T;
  }

  @override
  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    patches.add(_RecordedPatch(path, {...data as Map<String, dynamic>}));
    return <String, dynamic>{'id': 'group-a'} as T;
  }
}

TeacherStatsController _controller(
  _FakeApiClient api, {
  DateTimeRange? filterRange,
  String? branchId,
  ReportFileOpener? opener,
}) {
  return TeacherStatsController(
    crm: MagicCrmService(api),
    settings: MagicSettingsService(api),
    reportFileOpener:
        opener ??
        (bytes, filename) async =>
            ReportFileOpenResult(path: 'C:/reports/$filename', opened: false),
    filterRange: filterRange,
    branchId: branchId,
    canCorrectSettledPayroll: false,
    clock: () => DateTime.utc(2026, 8, 27, 12),
  );
}

_RecordedRequest _lastGet(_FakeApiClient api, String path) {
  return api.gets.lastWhere((request) => request.path == path);
}

void main() {
  test('external range and branch produce the exact report query', () async {
    final api = _FakeApiClient();
    final controller = _controller(
      api,
      filterRange: DateTimeRange(
        start: DateTime.utc(2026, 3, 2),
        end: DateTime.utc(2026, 3, 8),
      ),
      branchId: 'branch-external',
    );

    await controller.initialize();

    expect(
      _lastGet(api, '/crm/reports/teacher-stats').parameters,
      <String, dynamic>{
        'from': '2026-03-02T00:00:00.000Z',
        'to': '2026-03-09T00:00:00.000Z',
        'branchId': 'branch-external',
      },
    );
    expect(
      api.gets.where((request) => request.path == '/crm/branches'),
      isEmpty,
    );
  });

  test('all report filters are forwarded to export', () async {
    final api = _FakeApiClient();
    late List<int> openedBytes;
    late String openedFilename;
    final controller = _controller(
      api,
      opener: (bytes, filename) async {
        openedBytes = bytes;
        openedFilename = filename;
        return const ReportFileOpenResult(
          path: 'C:/reports/teacher-stats.csv',
          opened: true,
        );
      },
    );
    await controller.setQuery(
      TeacherStatsQuery(
        from: DateTime.utc(2026, 3, 2),
        to: DateTime.utc(2026, 4, 1),
        branchId: 'branch-a',
        teacherId: 'teacher-a',
        unitType: 'individual_trial',
        status: 'active',
        discipline: 'Гитара',
        category: 'Старший',
      ),
    );

    final result = await controller.export();

    expect(
      _lastGet(api, '/crm/reports/teacher-stats/export').parameters,
      <String, dynamic>{
        'from': '2026-03-02T00:00:00.000Z',
        'to': '2026-04-01T00:00:00.000Z',
        'branchId': 'branch-a',
        'teacherId': 'teacher-a',
        'unitType': 'individual_trial',
        'status': 'active',
        'discipline': 'Гитара',
        'category': 'Старший',
      },
    );
    expect(openedBytes.take(3), <int>[0xef, 0xbb, 0xbf]);
    expect(openedFilename, 'teacher-stats-2026-03-02.csv');
    expect(result.opened, isTrue);
  });

  test('group rate uses the group update contract', () async {
    final api = _FakeApiClient();
    final controller = _controller(api);

    await controller.updateGroupRate('group-a', 0);

    expect(api.patches, hasLength(1));
    expect(api.patches.single.path, '/crm/groups/group-a');
    expect(api.patches.single.body, <String, dynamic>{'teacherRate': 0});
  });

  test('report reload clears selected units', () async {
    final api = _FakeApiClient();
    final controller = _controller(api);
    await controller.initialize();
    controller.toggleUnit('unit-a', const ['lesson-1', 'lesson-2']);
    expect(controller.state.selectedUnits, isNotEmpty);

    await controller.setQuery(
      TeacherStatsQuery(
        from: DateTime.utc(2026, 5),
        to: DateTime.utc(2026, 6),
        teacherId: 'teacher-b',
      ),
    );

    expect(controller.state.selectedUnits, isEmpty);
  });
}
