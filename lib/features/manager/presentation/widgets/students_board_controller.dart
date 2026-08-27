import 'package:flutter/foundation.dart';

import 'students_board_models.dart';
import 'students_board_status_coordinator.dart';
export 'students_board_status_coordinator.dart' show StudentsBoardStatusUpdater;

typedef StudentsBoardBranchesLoader =
    Future<List<Map<String, dynamic>>> Function();
typedef StudentsBoardPageLoader =
    Future<StudentsBoardPageResult> Function({
      required String branchId,
      required String cursor,
    });

class StudentsBoardController extends ChangeNotifier {
  StudentsBoardController({
    required StudentsBoardBranchesLoader loadBranches,
    required StudentsBoardPageLoader loadStudentsPage,
    required StudentsBoardStatusUpdater updateStudentStatus,
    this.realtimeDebounce = const Duration(milliseconds: 350),
  }) : _loadBranches = loadBranches,
       _loadStudentsPage = loadStudentsPage {
    _statusCoordinator = StudentsBoardStatusCoordinator(
      updateStudentStatus: updateStudentStatus,
      readState: () => _state,
      emit: _emit,
      resetPages: resetPages,
      realtimeDebounce: realtimeDebounce,
    );
  }

  final StudentsBoardBranchesLoader _loadBranches;
  final StudentsBoardPageLoader _loadStudentsPage;
  final Duration realtimeDebounce;
  late final StudentsBoardStatusCoordinator _statusCoordinator;

  StudentsBoardState _state = StudentsBoardState();
  StudentsBoardState get state => _state;
  int _pageGeneration = 0;
  int _branchLoadGeneration = 0;
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
    if (!_canSelectBranch(branchId)) return;
    _statusCoordinator.resetContext();
    _pageGeneration++;
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
    if (!_canLoadPage(branchId, activeCursor)) return;
    final generation = _pageGeneration;
    _emit(_state.copyWith(loadingMoreStudents: true));
    try {
      final page = await _loadStudentsPage(
        branchId: branchId,
        cursor: activeCursor!,
      );
      if (!_isPageCurrent(branchId, generation)) return;
      _emit(
        _state.copyWith(
          extraStudents: [
            ..._state.extraStudents,
            ..._newPageItems(initialStudents, page.items),
          ],
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
  }) => _statusCoordinator.moveStatus(
    student,
    newStatus,
    refreshAndReadback: refreshAndReadback,
  );

  void scheduleRealtimeRefresh(Future<void> Function() refresh) {
    _statusCoordinator.scheduleRealtimeRefresh(refresh);
  }

  bool _canSelectBranch(String branchId) =>
      !_disposed && branchId.isNotEmpty && branchId != _state.selectedBranchId;

  bool _canLoadPage(String branchId, String? cursor) =>
      !_disposed &&
      branchId == _state.selectedBranchId &&
      cursor != null &&
      cursor.isNotEmpty &&
      !_state.loadingMoreStudents;

  Iterable<Map<String, dynamic>> _newPageItems(
    List<Map<String, dynamic>> initialStudents,
    List<Map<String, dynamic>> pageItems,
  ) {
    final known = <String>{
      for (final student in initialStudents)
        if (student['id'] != null) student['id'].toString(),
      for (final student in _state.extraStudents)
        if (student['id'] != null) student['id'].toString(),
    };
    return pageItems.where((student) {
      final id = student['id']?.toString() ?? '';
      return known.add(id);
    });
  }

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
    _statusCoordinator.dispose();
    _disposed = true;
    _pageGeneration++;
    _branchLoadGeneration++;
    super.dispose();
  }
}
