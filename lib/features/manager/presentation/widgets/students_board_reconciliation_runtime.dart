import 'dart:async';

import 'students_board_models.dart';

typedef StudentsBoardStateReader = StudentsBoardState Function();
typedef StudentsBoardStateEmitter = void Function(StudentsBoardState state);

/// Owns debounce timers, generation leases, and eventual readback state.
class StudentsBoardReconciliationRuntime {
  StudentsBoardReconciliationRuntime({
    required StudentsBoardStateReader readState,
    required StudentsBoardStateEmitter emit,
    required this.realtimeDebounce,
  }) : _readState = readState,
       _emit = emit;

  final StudentsBoardStateReader _readState;
  final StudentsBoardStateEmitter _emit;
  final Duration realtimeDebounce;

  Timer? _timer;
  Future<void> Function()? _fallbackReadback;
  int? _fallbackContextGeneration;
  String? _fallbackStudentId;
  int _contextGeneration = 0;
  int _reconciliationGeneration = 0;
  final Map<String, int> _confirmedStudentGenerations = {};
  bool _disposed = false;

  int get contextGeneration => _contextGeneration;

  void resetContext() {
    if (_disposed) return;
    _contextGeneration++;
    _reconciliationGeneration++;
    _cancelTimer();
    _clearFallback();
    _confirmedStudentGenerations.clear();
  }

  int beginReconciliation(String studentId) {
    final generation = ++_reconciliationGeneration;
    _confirmedStudentGenerations[studentId] = generation;
    _cancelTimer();
    return generation;
  }

  bool ownsContext(int generation) =>
      !_disposed && generation == _contextGeneration;

  bool markPendingAndSchedule({
    required int contextGeneration,
    required int reconciliationGeneration,
    required String studentId,
    required Future<void> Function() readback,
  }) {
    if (!_confirmedStudentGenerations.containsKey(studentId)) return false;
    final state = _readState();
    final pending = {...state.pendingStudentIds}..remove(studentId);
    _emit(state.copyWith(pendingStudentIds: pending));
    if (_isCurrent(contextGeneration, reconciliationGeneration)) {
      _schedule(
        contextGeneration: contextGeneration,
        reconciliationGeneration: reconciliationGeneration,
        studentId: studentId,
        readback: readback,
      );
    }
    return true;
  }

  void completeReadback(int reconciliationGeneration) {
    if (_isCurrent(_contextGeneration, reconciliationGeneration)) {
      _cancelTimer();
      _clearFallback();
    }
    final settled = <String>{
      for (final entry in _confirmedStudentGenerations.entries)
        if (entry.value <= reconciliationGeneration) entry.key,
    };
    for (final studentId in settled) {
      _confirmedStudentGenerations.remove(studentId);
    }
    final state = _readState();
    final pending = {...state.pendingStudentIds}..removeAll(settled);
    final optimistic = <String, String>{
      for (final entry in state.optimisticStatuses.entries)
        if (!settled.contains(entry.key)) entry.key: entry.value,
    };
    _emit(
      state.copyWith(
        optimisticStatuses: optimistic,
        pendingStudentIds: pending,
      ),
    );
  }

  void scheduleRealtimeRefresh(Future<void> Function() refresh) {
    if (_disposed || _readState().pendingStudentIds.isNotEmpty) return;
    final request = _RealtimeRefreshRequest(
      contextGeneration: _contextGeneration,
      reconciliationGeneration: ++_reconciliationGeneration,
      fallback: _fallbackReadback,
      fallbackContextGeneration: _fallbackContextGeneration,
      fallbackStudentId: _fallbackStudentId,
    );
    _cancelTimer();
    _timer = Timer(
      realtimeDebounce,
      () => _runRealtimeRefresh(request, refresh),
    );
  }

  void _schedule({
    required int contextGeneration,
    required int reconciliationGeneration,
    required String studentId,
    required Future<void> Function() readback,
    bool rememberAsFallback = true,
  }) {
    if (rememberAsFallback) {
      _fallbackReadback = readback;
      _fallbackContextGeneration = contextGeneration;
      _fallbackStudentId = studentId;
    }
    _cancelTimer();
    _timer = Timer(
      realtimeDebounce,
      () => _runScheduledReadback(
        contextGeneration: contextGeneration,
        reconciliationGeneration: reconciliationGeneration,
        studentId: studentId,
        readback: readback,
      ),
    );
  }

  Future<void> _runScheduledReadback({
    required int contextGeneration,
    required int reconciliationGeneration,
    required String studentId,
    required Future<void> Function() readback,
  }) async {
    if (!_isCurrent(contextGeneration, reconciliationGeneration)) return;
    if (!await _tryReadback(readback)) return;
    if (_isCurrent(contextGeneration, reconciliationGeneration)) {
      completeReadback(reconciliationGeneration);
    }
  }

  Future<void> _runRealtimeRefresh(
    _RealtimeRefreshRequest request,
    Future<void> Function() refresh,
  ) async {
    if (!_ownsRealtimeRequest(request)) return;
    if (!await _tryReadback(refresh)) {
      _retryFallbackIfOwned(request);
      return;
    }
    if (_ownsRealtimeRequest(request)) {
      completeReadback(request.reconciliationGeneration);
    }
  }

  void _retryFallbackIfOwned(_RealtimeRefreshRequest request) {
    if (!_canRetryFallback(request)) return;
    _schedule(
      contextGeneration: request.contextGeneration,
      reconciliationGeneration: ++_reconciliationGeneration,
      studentId: request.fallbackStudentId!,
      readback: request.fallback!,
      rememberAsFallback: false,
    );
  }

  Future<bool> _tryReadback(Future<void> Function() readback) async {
    try {
      await readback();
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _ownsRealtimeRequest(_RealtimeRefreshRequest request) =>
      _isCurrent(request.contextGeneration, request.reconciliationGeneration) &&
      _readState().pendingStudentIds.isEmpty;

  bool _canRetryFallback(_RealtimeRefreshRequest request) =>
      _isCurrent(request.contextGeneration, request.reconciliationGeneration) &&
      request.fallback != null &&
      request.fallbackContextGeneration == request.contextGeneration &&
      request.fallbackStudentId != null &&
      _readState().optimisticStatuses.isNotEmpty;

  bool _isCurrent(int context, int reconciliation) =>
      ownsContext(context) && reconciliation == _reconciliationGeneration;

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _clearFallback() {
    _fallbackReadback = null;
    _fallbackContextGeneration = null;
    _fallbackStudentId = null;
  }

  void dispose() {
    if (_disposed) return;
    _cancelTimer();
    _clearFallback();
    _confirmedStudentGenerations.clear();
    _disposed = true;
    _contextGeneration++;
    _reconciliationGeneration++;
  }
}

class _RealtimeRefreshRequest {
  const _RealtimeRefreshRequest({
    required this.contextGeneration,
    required this.reconciliationGeneration,
    required this.fallback,
    required this.fallbackContextGeneration,
    required this.fallbackStudentId,
  });

  final int contextGeneration;
  final int reconciliationGeneration;
  final Future<void> Function()? fallback;
  final int? fallbackContextGeneration;
  final String? fallbackStudentId;
}
