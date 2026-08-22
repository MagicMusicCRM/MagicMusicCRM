import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/report_export_files.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_data_source.dart';

enum ReportExportProgressStage {
  requesting,
  queued,
  polling,
  downloading,
  opening,
}

@immutable
class ReportExportProgress {
  const ReportExportProgress({
    required this.stage,
    this.rowCount,
    this.job,
    this.filename,
  });

  final ReportExportProgressStage stage;
  final int? rowCount;
  final V4ReportExportJob? job;
  final String? filename;
}

@immutable
class ReportExportOutcome {
  const ReportExportOutcome({
    required this.path,
    required this.filename,
    required this.opened,
  });

  final String path;
  final String filename;
  final bool opened;
}

class ReportExportCancelledException implements Exception {
  const ReportExportCancelledException();
}

class ReportExportCoordinator {
  ReportExportCoordinator({
    required this.dataSource,
    required this.opener,
    this.pollInterval = const Duration(milliseconds: 500),
    Future<void> Function(Duration)? delay,
    bool Function()? isCancelled,
  }) : delay = delay ?? Future<void>.delayed,
       isCancelled = isCancelled ?? _neverCancelled;

  static const int maxPollingAttempts = 120;

  final ReportingDataSource dataSource;
  final ReportFileOpener opener;
  final Duration pollInterval;
  final Future<void> Function(Duration) delay;
  final bool Function() isCancelled;

  Future<ReportExportOutcome> export({
    required String reportKey,
    required String format,
    required Map<String, dynamic> filter,
    void Function(ReportExportProgress progress)? onProgress,
  }) async {
    onProgress?.call(
      const ReportExportProgress(stage: ReportExportProgressStage.requesting),
    );
    final requested = await dataSource.requestExport(
      reportKey: reportKey,
      format: format,
      filter: filter,
    );
    if (!requested.isAsync) {
      return _open(requested.bytes!, requested.filename!, format, onProgress);
    }

    final jobId = requested.jobId!;
    onProgress?.call(
      ReportExportProgress(
        stage: ReportExportProgressStage.queued,
        rowCount: requested.rowCount,
      ),
    );
    for (
      var attempt = 0;
      attempt < maxPollingAttempts && !isCancelled();
      attempt++
    ) {
      await delay(pollInterval);
      final job = await dataSource.getExportJob(jobId);
      if (isCancelled()) throw const ReportExportCancelledException();
      onProgress?.call(
        ReportExportProgress(
          stage: ReportExportProgressStage.polling,
          rowCount: job.rowCount,
          job: job,
        ),
      );
      if (job.status == 'failed' || job.status == 'expired') {
        throw StateError(job.errorCode ?? 'Экспорт недоступен');
      }
      if (job.downloadReady) {
        final filename = job.filename ?? 'report.$format';
        onProgress?.call(
          ReportExportProgress(
            stage: ReportExportProgressStage.downloading,
            rowCount: job.rowCount,
            job: job,
            filename: filename,
          ),
        );
        final bytes = await dataSource.downloadExport(jobId);
        return _open(bytes, filename, format, onProgress);
      }
    }
    if (isCancelled()) throw const ReportExportCancelledException();
    throw TimeoutException('Экспорт занимает слишком много времени.');
  }

  Future<ReportExportOutcome> _open(
    List<int> bytes,
    String filename,
    String format,
    void Function(ReportExportProgress progress)? onProgress,
  ) async {
    validateReportExportBytes(bytes, format);
    onProgress?.call(
      ReportExportProgress(
        stage: ReportExportProgressStage.opening,
        filename: filename,
      ),
    );
    final result = await opener(bytes, filename);
    return ReportExportOutcome(
      path: result.path,
      filename: filename,
      opened: result.opened,
    );
  }
}

bool _neverCancelled() => false;
