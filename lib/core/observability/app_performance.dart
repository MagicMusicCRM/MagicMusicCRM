import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:uuid/uuid.dart';

enum AppOperation { api, studentCard, schedule, payment, lesson }

class PerformanceOperation {
  PerformanceOperation(this.name) : id = const Uuid().v4();
  final AppOperation name;
  final String id;
}

/// Bounded diagnostic buffer; no payloads, resource IDs or arbitrary URLs.
/// Diagnostic output is opt-in and never participates in business state.
class AppPerformance {
  static final Object _zoneKey = Object();
  static final _records = Queue<Map<String, Object?>>();
  static const capacity = 200;
  static const _printLogs = bool.fromEnvironment('PERFORMANCE_LOGS');

  static PerformanceOperation? get current =>
      Zone.current[_zoneKey] as PerformanceOperation?;
  static List<Map<String, Object?>> get snapshot => List.unmodifiable(_records);

  static Future<T> measure<T>(
    AppOperation name,
    Future<T> Function() work,
  ) async {
    if (current != null) return work();
    final operation = PerformanceOperation(name);
    final timer = Stopwatch()..start();
    var outcome = 'error';
    try {
      final result = await runZoned(work, zoneValues: {_zoneKey: operation});
      outcome = 'completed';
      return result;
    } finally {
      record({
        'kind': 'operation',
        'operation': name.name,
        'operationId': operation.id,
        'durationMs': timer.elapsedMicroseconds / 1000,
        'outcome': outcome,
      });
    }
  }

  static Future<void> measureScreen(
    AppOperation name,
    Future<void> Function() work, {
    required bool Function() isVisible,
  }) => measure(name, () async {
    final timer = Stopwatch()..start();
    await work();
    record({
      'kind': 'screenData',
      'operation': name.name,
      'operationId': current?.id,
      'durationMs': timer.elapsedMicroseconds / 1000,
    });
    if (isVisible()) {
      await WidgetsBinding.instance.endOfFrame;
      record({
        'kind': 'screenFrame',
        'operation': name.name,
        'operationId': current?.id,
        'durationMs': timer.elapsedMicroseconds / 1000,
      });
    }
  });

  static void record(Map<String, Object?> fields) {
    // Keep diagnostic failures outside the request's success/failure semantics.
    try {
      final entry = Map<String, Object?>.unmodifiable(fields);
      if (_records.length == capacity) _records.removeFirst();
      _records.add(entry);
      if (_printLogs) debugPrint(jsonEncode(entry));
      unawaited(
        Sentry.addBreadcrumb(
          Breadcrumb(category: 'performance', data: entry),
        ).catchError((Object _) {}),
      );
    } catch (_) {
      // Telemetry is best-effort.
    }
  }

  /// Low-cardinality categories derived from known API routes, never path values.
  static AppOperation operationFor(String method, String path) {
    final route = Uri.tryParse(path)?.path ?? '';
    if (RegExp(r'^/?crm/students/[^/]+/(card|commerce)$').hasMatch(route)) {
      return AppOperation.studentCard;
    }
    if (RegExp(r'^/?crm/schedule(?:[-/]|$)').hasMatch(route)) {
      return AppOperation.schedule;
    }
    if (method != 'GET' &&
        RegExp(
          r'^/?crm/students/[^/]+/payment-records(?:/|$)',
        ).hasMatch(route)) {
      return AppOperation.payment;
    }
    if (method != 'GET' && RegExp(r'^/?crm/lessons(?:/|$)').hasMatch(route)) {
      return AppOperation.lesson;
    }
    return AppOperation.api;
  }
}
