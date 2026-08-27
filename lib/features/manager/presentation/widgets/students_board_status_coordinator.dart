import 'students_board_models.dart';
import 'students_board_reconciliation_runtime.dart';

typedef StudentsBoardStatusUpdater =
    Future<void> Function({required String studentId, required String status});

/// Owns optimistic status persistence and delegates eventual readback timing.
class StudentsBoardStatusCoordinator {
  StudentsBoardStatusCoordinator({
    required StudentsBoardStatusUpdater updateStudentStatus,
    required StudentsBoardStateReader readState,
    required StudentsBoardStateEmitter emit,
    required void Function() resetPages,
    required Duration realtimeDebounce,
  }) : _updateStudentStatus = updateStudentStatus,
       _readState = readState,
       _emit = emit,
       _resetPages = resetPages {
    _reconciliation = StudentsBoardReconciliationRuntime(
      readState: readState,
      emit: emit,
      realtimeDebounce: realtimeDebounce,
    );
  }

  final StudentsBoardStatusUpdater _updateStudentStatus;
  final StudentsBoardStateReader _readState;
  final StudentsBoardStateEmitter _emit;
  final void Function() _resetPages;
  late final StudentsBoardReconciliationRuntime _reconciliation;

  void resetContext() => _reconciliation.resetContext();

  Future<StudentsBoardMoveResult> moveStatus(
    Map<String, dynamic> student,
    String newStatus, {
    required Future<void> Function(String branchId) refreshAndReadback,
  }) async {
    final state = _readState();
    final studentId = student['id']?.toString() ?? '';
    final currentStatus =
        state.optimisticStatuses[studentId] ??
        student['status']?.toString() ??
        '';
    if (!_canMove(state, studentId, currentStatus, newStatus)) {
      return const StudentsBoardMoveResult.success();
    }

    final lease = _StatusMoveLease(
      studentId: studentId,
      branchId: state.selectedBranchId,
      contextGeneration: _reconciliation.contextGeneration,
      previousStatus: state.optimisticStatuses[studentId],
    );
    _applyOptimisticMove(studentId, newStatus);
    try {
      await _updateStudentStatus(studentId: studentId, status: newStatus);
    } catch (error) {
      return _handlePersistenceFailure(lease, error);
    }

    if (!_owns(lease)) return const StudentsBoardMoveResult.success();
    final reconciliationGeneration = _reconciliation.beginReconciliation(
      studentId,
    );
    _resetPages();
    final branchId = lease.branchId;
    if (branchId == null) {
      _reconciliation.completeReadback(reconciliationGeneration);
      return const StudentsBoardMoveResult.success();
    }

    Future<void> readback() => refreshAndReadback(branchId);
    final readbackSucceeded = await _tryReadback(readback);
    if (!_owns(lease)) return const StudentsBoardMoveResult.success();
    if (!readbackSucceeded) {
      final reconciliationPending = _reconciliation.markPendingAndSchedule(
        contextGeneration: lease.contextGeneration,
        reconciliationGeneration: reconciliationGeneration,
        studentId: studentId,
        readback: readback,
      );
      return StudentsBoardMoveResult.success(
        reconciliationPending: reconciliationPending,
      );
    }

    _reconciliation.completeReadback(reconciliationGeneration);
    return const StudentsBoardMoveResult.success();
  }

  void scheduleRealtimeRefresh(Future<void> Function() refresh) {
    _reconciliation.scheduleRealtimeRefresh(refresh);
  }

  bool _canMove(
    StudentsBoardState state,
    String studentId,
    String currentStatus,
    String newStatus,
  ) =>
      _reconciliation.ownsContext(_reconciliation.contextGeneration) &&
      studentId.isNotEmpty &&
      !state.pendingStudentIds.contains(studentId) &&
      currentStatus != newStatus;

  void _applyOptimisticMove(String studentId, String newStatus) {
    final state = _readState();
    _emit(
      state.copyWith(
        optimisticStatuses: {...state.optimisticStatuses, studentId: newStatus},
        pendingStudentIds: {...state.pendingStudentIds, studentId},
      ),
    );
  }

  StudentsBoardMoveResult _handlePersistenceFailure(
    _StatusMoveLease lease,
    Object error,
  ) {
    if (!_owns(lease)) return const StudentsBoardMoveResult.success();
    final state = _readState();
    final optimistic = {...state.optimisticStatuses};
    final previous = lease.previousStatus;
    if (previous == null) {
      optimistic.remove(lease.studentId);
    } else {
      optimistic[lease.studentId] = previous;
    }
    final pending = {...state.pendingStudentIds}..remove(lease.studentId);
    _emit(
      state.copyWith(
        optimisticStatuses: optimistic,
        pendingStudentIds: pending,
      ),
    );
    return StudentsBoardMoveResult.failure(error);
  }

  Future<bool> _tryReadback(Future<void> Function() readback) async {
    try {
      await readback();
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _owns(_StatusMoveLease lease) =>
      _reconciliation.ownsContext(lease.contextGeneration);

  void dispose() => _reconciliation.dispose();
}

class _StatusMoveLease {
  const _StatusMoveLease({
    required this.studentId,
    required this.branchId,
    required this.contextGeneration,
    required this.previousStatus,
  });

  final String studentId;
  final String? branchId;
  final int contextGeneration;
  final String? previousStatus;
}
