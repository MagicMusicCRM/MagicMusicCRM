import 'dart:async';

import 'package:flutter/foundation.dart';

import 'students_board_models.dart';

typedef StudentsBoardBranchesLoader =
    Future<List<Map<String, dynamic>>> Function();
typedef StudentsBoardPageLoader =
    Future<StudentsBoardPageResult> Function({
      required String branchId,
      required String cursor,
    });
typedef StudentsBoardStatusUpdater =
    Future<void> Function({required String studentId, required String status});

class StudentsBoardController extends ChangeNotifier {
  StudentsBoardController({
    required StudentsBoardBranchesLoader loadBranches,
    required StudentsBoardPageLoader loadStudentsPage,
    required StudentsBoardStatusUpdater updateStudentStatus,
    this.realtimeDebounce = const Duration(milliseconds: 350),
  }) : _loadBranches = loadBranches,
       _loadStudentsPage = loadStudentsPage,
       _updateStudentStatus = updateStudentStatus;

  final StudentsBoardBranchesLoader _loadBranches;
  final StudentsBoardPageLoader _loadStudentsPage;
  final StudentsBoardStatusUpdater _updateStudentStatus;
  final Duration realtimeDebounce;

  StudentsBoardState _state = StudentsBoardState();
  StudentsBoardState get state => _state;
  Timer? _reconciliationTimer;
  Future<void> Function()? _fallbackReconciliation;
  int? _fallbackContextGeneration;
  String? _fallbackStudentId;
  int _contextGeneration = 0;
  int _pageGeneration = 0;
  int _branchLoadGeneration = 0;
  int _reconciliationGeneration = 0;
  bool _disposed = false;

  Future<void> loadBranches() async {
    if (_disposed) return;
    final generation = ++_branchLoadGeneration;
    _emit(_state.copyWith(branchesLoaded: false, branchLoadError: null));
    try {
      final branches = await _loadBranches();
      if (!_isBranchLoadCurrent(generation)) return;
      final copy = List<Map<String, dynamic>>.from(branches);
      _emit(
        _state.copyWith(
          branches: copy,
          selectedBranchId:
              _state.selectedBranchId ??
              (copy.isEmpty ? null : copy.first['id']?.toString()),
          branchesLoaded: true,
          branchLoadError: null,
        ),
      );
    } catch (_) {
      if (!_isBranchLoadCurrent(generation)) return;
      _emit(
        _state.copyWith(
          branchesLoaded: true,
          branchLoadError: 'Не удалось загрузить филиалы',
        ),
      );
    }
  }

  void selectBranch(String branchId) {
    if (_disposed || branchId.isEmpty || branchId == _state.selectedBranchId) {
      return;
    }
    _contextGeneration++;
    _pageGeneration++;
    _reconciliationGeneration++;
    _reconciliationTimer?.cancel();
    _clearFallbackReconciliation();
    _emit(
      _state.copyWith(
        selectedBranchId: branchId,
        extraStudents: const [],
        nextStudentCursor: null,
        loadingMoreStudents: false,
        optimisticStatuses: const {},
        pendingStudentIds: const {},
      ),
    );
  }

  void setQuery(String value) {
    final query = value.trim().toLowerCase();
    if (query != _state.query) _emit(_state.copyWith(query: query));
  }

  void toggleFilters() {
    _emit(_state.copyWith(filtersOpen: !_state.filtersOpen));
  }

  void resetPages() {
    if (_disposed) return;
    _pageGeneration++;
    _emit(
      _state.copyWith(
        extraStudents: const [],
        nextStudentCursor: null,
        loadingMoreStudents: false,
      ),
    );
  }

  Future<void> loadMoreStudents({
    required String branchId,
    required String? cursor,
    required List<Map<String, dynamic>> initialStudents,
  }) async {
    final activeCursor = cursor?.trim();
    if (_disposed ||
        branchId != _state.selectedBranchId ||
        activeCursor == null ||
        activeCursor.isEmpty ||
        _state.loadingMoreStudents) {
      return;
    }
    final generation = _pageGeneration;
    _emit(_state.copyWith(loadingMoreStudents: true));
    try {
      final page = await _loadStudentsPage(
        branchId: branchId,
        cursor: activeCursor,
      );
      if (!_isPageCurrent(branchId, generation)) return;
      final known = <String>{
        for (final student in initialStudents)
          if (student['id'] != null) student['id'].toString(),
        for (final student in _state.extraStudents)
          if (student['id'] != null) student['id'].toString(),
      };
      final additions = page.items.where((student) {
        final id = student['id']?.toString() ?? '';
        return known.add(id);
      }).toList();
      _emit(
        _state.copyWith(
          extraStudents: [..._state.extraStudents, ...additions],
          nextStudentCursor: page.nextCursor,
          loadingMoreStudents: false,
        ),
      );
    } catch (_) {
      if (_isPageCurrent(branchId, generation)) {
        _emit(_state.copyWith(loadingMoreStudents: false));
      }
    }
  }

  Future<StudentsBoardMoveResult> moveStatus(
    Map<String, dynamic> student,
    String newStatus, {
    required Future<void> Function(String branchId) refreshAndReadback,
  }) async {
    final id = student['id']?.toString() ?? '';
    final current =
        _state.optimisticStatuses[id] ?? student['status']?.toString() ?? '';
    if (_disposed ||
        id.isEmpty ||
        _state.pendingStudentIds.contains(id) ||
        current == newStatus) {
      return const StudentsBoardMoveResult.success();
    }
    final branchId = _state.selectedBranchId;
    final generation = _contextGeneration;
    final previous = _state.optimisticStatuses[id];
    _emit(
      _state.copyWith(
        optimisticStatuses: {..._state.optimisticStatuses, id: newStatus},
        pendingStudentIds: {..._state.pendingStudentIds, id},
      ),
    );
    try {
      await _updateStudentStatus(studentId: id, status: newStatus);
    } catch (error) {
      if (!_isCurrent(generation)) {
        return const StudentsBoardMoveResult.success();
      }
      final optimistic = {..._state.optimisticStatuses};
      previous == null ? optimistic.remove(id) : optimistic[id] = previous;
      final pending = {..._state.pendingStudentIds}..remove(id);
      _emit(
        _state.copyWith(
          optimisticStatuses: optimistic,
          pendingStudentIds: pending,
        ),
      );
      return StudentsBoardMoveResult.failure(error);
    }

    if (!_isCurrent(generation)) {
      return const StudentsBoardMoveResult.success();
    }
    final reconciliationGeneration = ++_reconciliationGeneration;
    _reconciliationTimer?.cancel();
    _reconciliationTimer = null;
    _pageGeneration++;
    _emit(
      _state.copyWith(
        extraStudents: const [],
        nextStudentCursor: null,
        loadingMoreStudents: false,
      ),
    );
    if (branchId == null) {
      _completeReconciliation(id);
      return const StudentsBoardMoveResult.success();
    }

    try {
      await refreshAndReadback(branchId);
    } catch (_) {
      if (!_isCurrent(generation)) {
        return const StudentsBoardMoveResult.success();
      }
      _markReconciliationPending(id);
      _scheduleReconciliation(
        generation: generation,
        reconciliationGeneration: reconciliationGeneration,
        studentId: id,
        readback: () => refreshAndReadback(branchId),
      );
      return const StudentsBoardMoveResult.success(reconciliationPending: true);
    }
    if (!_isCurrent(generation)) {
      return const StudentsBoardMoveResult.success();
    }
    _completeReconciliation(id);
    return const StudentsBoardMoveResult.success();
  }

  void _markReconciliationPending(String studentId) {
    final pending = {..._state.pendingStudentIds}..remove(studentId);
    _emit(_state.copyWith(pendingStudentIds: pending));
  }

  void _scheduleReconciliation({
    required int generation,
    required int reconciliationGeneration,
    required String studentId,
    required Future<void> Function() readback,
    bool rememberAsFallback = true,
  }) {
    if (rememberAsFallback) {
      _fallbackReconciliation = readback;
      _fallbackContextGeneration = generation;
      _fallbackStudentId = studentId;
    }
    _reconciliationTimer?.cancel();
    _reconciliationTimer = Timer(realtimeDebounce, () async {
      if (!_isReconciliationCurrent(generation, reconciliationGeneration)) {
        return;
      }
      try {
        await readback();
      } catch (_) {
        return;
      }
      if (!_isReconciliationCurrent(generation, reconciliationGeneration)) {
        return;
      }
      _completeReconciliation(studentId);
    });
  }

  void _completeReconciliation(String studentId) {
    _reconciliationTimer?.cancel();
    _reconciliationTimer = null;
    _clearFallbackReconciliation();
    final pending = {..._state.pendingStudentIds}..remove(studentId);
    final optimistic = <String, String>{
      for (final entry in _state.optimisticStatuses.entries)
        if (pending.contains(entry.key)) entry.key: entry.value,
    };
    _emit(
      _state.copyWith(
        optimisticStatuses: optimistic,
        pendingStudentIds: pending,
      ),
    );
  }

  void scheduleRealtimeRefresh(Future<void> Function() refresh) {
    if (_disposed || _state.pendingStudentIds.isNotEmpty) return;
    final generation = _contextGeneration;
    final fallback = _fallbackReconciliation;
    final fallbackContext = _fallbackContextGeneration;
    final fallbackStudentId = _fallbackStudentId;
    final reconciliationGeneration = ++_reconciliationGeneration;
    _reconciliationTimer?.cancel();
    _reconciliationTimer = Timer(realtimeDebounce, () async {
      if (!_isReconciliationCurrent(generation, reconciliationGeneration) ||
          _state.pendingStudentIds.isNotEmpty) {
        return;
      }
      try {
        await refresh();
      } catch (_) {
        if (_isReconciliationCurrent(generation, reconciliationGeneration) &&
            fallback != null &&
            fallbackContext == generation &&
            fallbackStudentId != null &&
            _state.optimisticStatuses.isNotEmpty) {
          final retryGeneration = ++_reconciliationGeneration;
          _scheduleReconciliation(
            generation: generation,
            reconciliationGeneration: retryGeneration,
            studentId: fallbackStudentId,
            readback: fallback,
            rememberAsFallback: false,
          );
        }
        return;
      }
      if (!_isReconciliationCurrent(generation, reconciliationGeneration) ||
          _state.pendingStudentIds.isNotEmpty) {
        return;
      }
      _completeReconciliation('');
    });
  }

  void _clearFallbackReconciliation() {
    _fallbackReconciliation = null;
    _fallbackContextGeneration = null;
    _fallbackStudentId = null;
  }

  bool _isCurrent(int generation) =>
      !_disposed && generation == _contextGeneration;

  bool _isReconciliationCurrent(int context, int reconciliation) =>
      _isCurrent(context) && reconciliation == _reconciliationGeneration;

  bool _isBranchLoadCurrent(int generation) =>
      !_disposed && generation == _branchLoadGeneration;

  bool _isPageCurrent(String branchId, int generation) =>
      !_disposed &&
      generation == _pageGeneration &&
      branchId == _state.selectedBranchId;

  void _emit(StudentsBoardState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _reconciliationTimer?.cancel();
    _reconciliationTimer = null;
    _clearFallbackReconciliation();
    _disposed = true;
    _contextGeneration++;
    _pageGeneration++;
    _branchLoadGeneration++;
    _reconciliationGeneration++;
    super.dispose();
  }
}
