import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/report_export_coordinator.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/report_export_files.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_data_source.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_models.dart';

import '../../support/minimal_xlsx_fixture.dart';

void main() {
  group('ReportExportCoordinator', () {
    test('sync result validates and opens the server filename once', () async {
      final source = _FakeReportingDataSource(
        requested: V4ReportExportResult.sync(
          bytes: _validCsvBytes,
          filename: 'client-status-2026-08-22.csv',
        ),
      );
      final opener = _RecordingOpener(
        result: const ReportFileOpenResult(
          path: 'C:/Reports/client-status-2026-08-22.csv',
          opened: true,
        ),
      );
      final coordinator = ReportExportCoordinator(
        dataSource: source,
        opener: opener.call,
      );

      final outcome = await _export(
        coordinator,
        filter: const {'status': 'new'},
      );

      expect(source.requestCalls, 1);
      expect(source.requestedReportKey, 'client-status');
      expect(source.requestedFormat, 'csv');
      expect(source.requestedFilter, const {'status': 'new'});
      expect(source.jobReads, 0);
      expect(source.downloads, 0);
      expect(opener.calls, 1);
      expect(opener.lastBytes, _validCsvBytes);
      expect(opener.lastFilename, 'client-status-2026-08-22.csv');
      expect(outcome.path, 'C:/Reports/client-status-2026-08-22.csv');
      expect(outcome.filename, 'client-status-2026-08-22.csv');
      expect(outcome.opened, isTrue);
    });

    test(
      'async result polls exact jobs then downloads and opens once',
      () async {
        final source = _FakeReportingDataSource(
          requested: const V4ReportExportResult.async(
            jobId: 'job-1',
            status: 'queued',
            rowCount: 10001,
          ),
          jobs: const [
            V4ReportExportJob(
              id: 'job-1',
              status: 'queued',
              rowCount: 10001,
              downloadReady: false,
            ),
            V4ReportExportJob(
              id: 'job-1',
              status: 'processing',
              rowCount: 10001,
              downloadReady: false,
            ),
            V4ReportExportJob(
              id: 'job-1',
              status: 'ready',
              rowCount: 10001,
              downloadReady: true,
              filename: 'school-finance.xlsx',
            ),
          ],
          downloadedBytes: _validXlsxBytes,
        );
        final opener = _RecordingOpener(
          result: const ReportFileOpenResult(
            path: 'C:/Reports/school-finance.xlsx',
            opened: true,
          ),
        );
        final delays = <Duration>[];
        final progress = <ReportExportProgress>[];
        final coordinator = ReportExportCoordinator(
          dataSource: source,
          opener: opener.call,
          pollInterval: const Duration(milliseconds: 17),
          delay: (duration) async => delays.add(duration),
        );

        final outcome = await _export(
          coordinator,
          reportKey: 'school_finance',
          format: 'xlsx',
          filter: const {'branchId': 'branch-1'},
          onProgress: progress.add,
        );

        expect(source.jobReads, 3);
        expect(source.requestedJobIds, ['job-1', 'job-1', 'job-1']);
        expect(delays, List.filled(3, const Duration(milliseconds: 17)));
        expect(source.downloads, 1);
        expect(source.downloadedJobIds, ['job-1']);
        expect(opener.calls, 1);
        expect(opener.lastBytes, _validXlsxBytes);
        expect(opener.lastFilename, 'school-finance.xlsx');
        expect(outcome.opened, isTrue);
        expect(progress.map((item) => item.stage), [
          ReportExportProgressStage.requesting,
          ReportExportProgressStage.queued,
          ReportExportProgressStage.polling,
          ReportExportProgressStage.polling,
          ReportExportProgressStage.polling,
          ReportExportProgressStage.downloading,
          ReportExportProgressStage.opening,
        ]);
        expect(progress[1].rowCount, 10001);
        expect(progress[2].job?.status, 'queued');
        expect(progress[3].job?.status, 'processing');
        expect(progress[4].job?.status, 'ready');
      },
    );

    test('failed async job preserves the server error code', () async {
      final coordinator = ReportExportCoordinator(
        dataSource: _FakeReportingDataSource(
          requested: const V4ReportExportResult.async(
            jobId: 'job-failed',
            status: 'queued',
            rowCount: 3,
          ),
          jobs: const [
            V4ReportExportJob(
              id: 'job-failed',
              status: 'failed',
              rowCount: 3,
              downloadReady: false,
              errorCode: 'REPORT_EXPORT_FAILED',
            ),
          ],
        ),
        opener: _unexpectedOpen,
        delay: (_) async {},
      );

      await expectLater(
        _export(coordinator),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'REPORT_EXPORT_FAILED',
          ),
        ),
      );
    });

    test('expired async job preserves the Russian fallback', () async {
      final coordinator = ReportExportCoordinator(
        dataSource: _FakeReportingDataSource(
          requested: const V4ReportExportResult.async(
            jobId: 'job-expired',
            status: 'queued',
            rowCount: 3,
          ),
          jobs: const [
            V4ReportExportJob(
              id: 'job-expired',
              status: 'expired',
              rowCount: 3,
              downloadReady: false,
            ),
          ],
        ),
        opener: _unexpectedOpen,
        delay: (_) async {},
      );

      await expectLater(
        _export(coordinator),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Экспорт недоступен',
          ),
        ),
      );
    });

    test(
      'async job without filename uses the report format fallback',
      () async {
        final source = _FakeReportingDataSource(
          requested: const V4ReportExportResult.async(
            jobId: 'job-no-name',
            status: 'queued',
            rowCount: 1,
          ),
          jobs: const [
            V4ReportExportJob(
              id: 'job-no-name',
              status: 'ready',
              rowCount: 1,
              downloadReady: true,
            ),
          ],
          downloadedBytes: _validCsvBytes,
        );
        final opener = _RecordingOpener(
          result: const ReportFileOpenResult(
            path: 'C:/Reports/report.csv',
            opened: true,
          ),
        );
        final coordinator = ReportExportCoordinator(
          dataSource: source,
          opener: opener.call,
          delay: (_) async {},
        );

        final outcome = await _export(coordinator);

        expect(outcome.filename, 'report.csv');
        expect(opener.lastFilename, 'report.csv');
      },
    );

    for (final corrupt in <(String, List<int>)>[
      ('csv', utf8.encode('name\nАлина')),
      ('xlsx', utf8.encode('{"not":"xlsx"}')),
    ]) {
      test('corrupt ${corrupt.$1} bytes never reach the opener', () async {
        final source = _FakeReportingDataSource(
          requested: V4ReportExportResult.sync(
            bytes: corrupt.$2,
            filename: 'report.${corrupt.$1}',
          ),
        );
        final opener = _RecordingOpener(
          result: ReportFileOpenResult(
            path: 'report.${corrupt.$1}',
            opened: true,
          ),
        );
        final coordinator = ReportExportCoordinator(
          dataSource: source,
          opener: opener.call,
        );

        await expectLater(
          _export(coordinator, format: corrupt.$1),
          throwsFormatException,
        );
        expect(opener.calls, 0);
      });
    }

    test('timeout performs exactly 120 injected waits and polls', () async {
      final source = _FakeReportingDataSource(
        requested: const V4ReportExportResult.async(
          jobId: 'job-slow',
          status: 'queued',
          rowCount: 20,
        ),
        jobs: const [
          V4ReportExportJob(
            id: 'job-slow',
            status: 'processing',
            rowCount: 20,
            downloadReady: false,
          ),
        ],
        repeatLastJob: true,
      );
      var delayCalls = 0;
      final coordinator = ReportExportCoordinator(
        dataSource: source,
        opener: _unexpectedOpen,
        delay: (_) async => delayCalls++,
      );

      await expectLater(
        _export(coordinator),
        throwsA(
          isA<TimeoutException>().having(
            (error) => error.message,
            'message',
            'Экспорт занимает слишком много времени.',
          ),
        ),
      );
      expect(delayCalls, 120);
      expect(source.jobReads, 120);
      expect(source.downloads, 0);
    });

    test('cancellation during injected delay starts no job read', () async {
      final delayStarted = Completer<void>();
      final releaseDelay = Completer<void>();
      final source = _FakeReportingDataSource(
        requested: const V4ReportExportResult.async(
          jobId: 'job-cancelled',
          status: 'queued',
          rowCount: 20,
        ),
        jobs: const [
          V4ReportExportJob(
            id: 'job-cancelled',
            status: 'ready',
            rowCount: 20,
            downloadReady: true,
            filename: 'client-status.csv',
          ),
        ],
        downloadedBytes: _validCsvBytes,
      );
      var cancelled = false;
      final coordinator = ReportExportCoordinator(
        dataSource: source,
        opener: _unexpectedOpen,
        delay: (_) {
          delayStarted.complete();
          return releaseDelay.future;
        },
        isCancelled: () => cancelled,
      );

      final export = _export(coordinator);
      await delayStarted.future;
      cancelled = true;
      releaseDelay.complete();

      await expectLater(export, throwsA(isA<ReportExportCancelledException>()));
      expect(source.jobReads, 0);
      expect(source.downloads, 0);
    });

    test('already cancelled export starts no request or opener', () async {
      final source = _FakeReportingDataSource(
        requested: V4ReportExportResult.sync(
          bytes: _validCsvBytes,
          filename: 'client-status.csv',
        ),
      );
      final opener = _RecordingOpener(
        result: const ReportFileOpenResult(
          path: 'C:/Reports/client-status.csv',
          opened: true,
        ),
      );
      final coordinator = ReportExportCoordinator(
        dataSource: source,
        opener: opener.call,
        isCancelled: () => true,
      );

      await expectLater(
        _export(coordinator),
        throwsA(isA<ReportExportCancelledException>()),
      );
      expect(source.requestCalls, 0);
      expect(opener.calls, 0);
    });

    test('cancellation while sync request is pending skips opener', () async {
      final requestCompleter = Completer<V4ReportExportResult>();
      final source = _FakeReportingDataSource(
        requested: V4ReportExportResult.sync(
          bytes: _validCsvBytes,
          filename: 'unused.csv',
        ),
        requestCompleter: requestCompleter,
      );
      final opener = _RecordingOpener(
        result: const ReportFileOpenResult(
          path: 'C:/Reports/client-status.csv',
          opened: true,
        ),
      );
      var cancelled = false;
      final coordinator = ReportExportCoordinator(
        dataSource: source,
        opener: opener.call,
        isCancelled: () => cancelled,
      );

      final export = _export(coordinator);
      expect(source.requestCalls, 1);
      cancelled = true;
      requestCompleter.complete(
        V4ReportExportResult.sync(
          bytes: _validCsvBytes,
          filename: 'client-status.csv',
        ),
      );

      await expectLater(export, throwsA(isA<ReportExportCancelledException>()));
      expect(opener.calls, 0);
    });

    test('cancellation while download is pending skips opener', () async {
      final downloadCompleter = Completer<List<int>>();
      final downloadStarted = Completer<void>();
      final source = _FakeReportingDataSource(
        requested: const V4ReportExportResult.async(
          jobId: 'job-download',
          status: 'queued',
          rowCount: 20,
        ),
        jobs: const [
          V4ReportExportJob(
            id: 'job-download',
            status: 'ready',
            rowCount: 20,
            downloadReady: true,
            filename: 'client-status.csv',
          ),
        ],
        downloadedBytes: _validCsvBytes,
        downloadCompleter: downloadCompleter,
        downloadStarted: downloadStarted,
      );
      final opener = _RecordingOpener(
        result: const ReportFileOpenResult(
          path: 'C:/Reports/client-status.csv',
          opened: true,
        ),
      );
      var cancelled = false;
      final coordinator = ReportExportCoordinator(
        dataSource: source,
        opener: opener.call,
        delay: (_) async {},
        isCancelled: () => cancelled,
      );

      final export = _export(coordinator);
      await downloadStarted.future;
      cancelled = true;
      downloadCompleter.complete(_validCsvBytes);

      await expectLater(export, throwsA(isA<ReportExportCancelledException>()));
      expect(source.downloads, 1);
      expect(opener.calls, 0);
    });

    test('file opener failure remains an export failure', () async {
      final coordinator = ReportExportCoordinator(
        dataSource: _FakeReportingDataSource(
          requested: V4ReportExportResult.sync(
            bytes: _validCsvBytes,
            filename: 'client-status.csv',
          ),
        ),
        opener: (_, _) => throw StateError('open failed'),
      );

      await expectLater(
        _export(coordinator),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'open failed',
          ),
        ),
      );
    });

    test('saved but unopened file preserves its path and outcome', () async {
      final coordinator = ReportExportCoordinator(
        dataSource: _FakeReportingDataSource(
          requested: V4ReportExportResult.sync(
            bytes: _validCsvBytes,
            filename: 'client-status.csv',
          ),
        ),
        opener: (_, _) async => const ReportFileOpenResult(
          path: 'C:/Reports/client-status.csv',
          opened: false,
        ),
      );

      final outcome = await _export(coordinator);

      expect(outcome.filename, 'client-status.csv');
      expect(outcome.path, 'C:/Reports/client-status.csv');
      expect(outcome.opened, isFalse);
    });
  });
}

final List<int> _validCsvBytes = [
  0xef,
  0xbb,
  0xbf,
  ...utf8.encode('name\nАлина'),
];
final List<int> _validXlsxBytes = minimalXlsxBytes();

Future<ReportExportOutcome> _export(
  ReportExportCoordinator coordinator, {
  String reportKey = 'client-status',
  String format = 'csv',
  Map<String, dynamic> filter = const {},
  void Function(ReportExportProgress progress)? onProgress,
}) {
  return coordinator.export(
    reportKey: reportKey,
    format: format,
    filter: filter,
    onProgress: onProgress,
  );
}

Future<ReportFileOpenResult> _unexpectedOpen(List<int> bytes, String filename) {
  throw StateError('opener must not be called');
}

class _RecordingOpener {
  _RecordingOpener({required this.result});

  final ReportFileOpenResult result;
  int calls = 0;
  List<int>? lastBytes;
  String? lastFilename;

  Future<ReportFileOpenResult> call(List<int> bytes, String filename) async {
    calls++;
    lastBytes = List<int>.from(bytes);
    lastFilename = filename;
    return result;
  }
}

class _FakeReportingDataSource implements ReportingDataSource {
  _FakeReportingDataSource({
    required this.requested,
    this.jobs = const [],
    this.downloadedBytes = const [],
    this.repeatLastJob = false,
    this.requestCompleter,
    this.downloadCompleter,
    this.downloadStarted,
  });

  final V4ReportExportResult requested;
  final List<V4ReportExportJob> jobs;
  final List<int> downloadedBytes;
  final bool repeatLastJob;
  final Completer<V4ReportExportResult>? requestCompleter;
  final Completer<List<int>>? downloadCompleter;
  final Completer<void>? downloadStarted;
  int requestCalls = 0;
  int jobReads = 0;
  int downloads = 0;
  String? requestedReportKey;
  String? requestedFormat;
  Map<String, dynamic>? requestedFilter;
  final requestedJobIds = <String>[];
  final downloadedJobIds = <String>[];

  @override
  Future<V4ReportExportResult> requestExport({
    required String reportKey,
    required String format,
    required Map<String, dynamic> filter,
  }) async {
    requestCalls++;
    requestedReportKey = reportKey;
    requestedFormat = format;
    requestedFilter = Map<String, dynamic>.from(filter);
    if (requestCompleter != null) return requestCompleter!.future;
    return requested;
  }

  @override
  Future<V4ReportExportJob> getExportJob(String jobId) async {
    requestedJobIds.add(jobId);
    final index = jobReads++;
    if (index < jobs.length) return jobs[index];
    if (repeatLastJob && jobs.isNotEmpty) return jobs.last;
    throw StateError('Unexpected job read $index');
  }

  @override
  Future<List<int>> downloadExport(String jobId) async {
    downloads++;
    downloadedJobIds.add(jobId);
    downloadStarted?.complete();
    if (downloadCompleter != null) return downloadCompleter!.future;
    return List<int>.from(downloadedBytes);
  }

  @override
  Future<Map<String, dynamic>> loadClientStatus(DashboardFilter filter) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> loadDrilldown(
    EntityLink link,
    DashboardFilter filter,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> loadLessonSuccess(DashboardFilter filter) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> loadOpenTaskSummary() {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> loadSchoolFinance(DashboardFilter filter) {
    throw UnimplementedError();
  }
}
