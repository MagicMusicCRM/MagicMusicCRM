import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/providers/crm_navigation_provider.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card_launcher.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/client_forms.dart';
import 'package:magic_music_crm/features/manager/presentation/providers/students_board_providers.dart';
import 'package:magic_music_crm/features/manager/presentation/transfer/lead_transfer_controller.dart';
import 'package:magic_music_crm/features/manager/presentation/transfer/lead_transfer_widgets.dart';

import 'students_board_auto_scroll_controller.dart';
import 'students_board_controller.dart';
import 'students_board_models.dart';
import 'students_board_projection.dart';
import 'students_board_widgets.dart';

/// Per-branch student status board. Runtime dependencies remain in this shell;
/// controller and view own state transitions and presentation respectively.
class StudentsBoardWidget extends ConsumerStatefulWidget {
  const StudentsBoardWidget({super.key});

  @override
  ConsumerState<StudentsBoardWidget> createState() =>
      _StudentsBoardWidgetState();
}

class _StudentsBoardWidgetState extends ConsumerState<StudentsBoardWidget> {
  late final StudentsBoardController _controller;
  late final StudentsBoardAutoScrollController _autoScroll;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final crm = ref.read(magicCrmServiceProvider);
    _controller = StudentsBoardController(
      loadBranches: () => crm.listBranches(limit: 100),
      loadStudentsPage: ({required branchId, required cursor}) async {
        final response = branchId == kNoBranchBoardId
            ? await crm.searchStudents(
                noBranch: true,
                cursor: cursor,
                limit: 100,
              )
            : await crm.searchStudents(
                branchId: branchId,
                cursor: cursor,
                limit: 100,
              );
        return StudentsBoardPageResult(
          items: (response['items'] as List? ?? const [])
              .whereType<Map<String, dynamic>>()
              .toList(),
          nextCursor: response['next_cursor']?.toString(),
        );
      },
      updateStudentStatus: ({required studentId, required status}) async {
        await crm.updateStudent(studentId, status: status);
      },
    );
    final transfer = ref.read(leadTransferControllerProvider);
    final transferBranchId = transfer.isActive
        ? transfer.selectedBranchId
        : null;
    if (transferBranchId != null && transferBranchId.isNotEmpty) {
      _controller.selectBranch(transferBranchId);
    }
    _controller.addListener(_onControllerChanged);
    _autoScroll = StudentsBoardAutoScrollController();
    _controller.loadBranches();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    _autoScroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _refreshBoard([String? requestedBranchId]) {
    final branchId = requestedBranchId ?? _controller.state.selectedBranchId;
    if (branchId == null) return;
    _controller.resetPages();
    ref.invalidate(studentFunnelProvider(branchId));
    ref.invalidate(studentBoardProvider(branchId));
  }

  Future<void> _refreshAndReadback(String branchId) async {
    ref.invalidate(studentFunnelProvider(branchId));
    ref.invalidate(studentBoardProvider(branchId));
    await ref.read(studentBoardProvider(branchId).future);
  }

  Future<void> _moveStatus(
    Map<String, dynamic> student,
    String newStatus,
  ) async {
    final result = await _controller.moveStatus(
      student,
      newStatus,
      refreshAndReadback: _refreshAndReadback,
    );
    if (!mounted || result.succeeded) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          userErrorMessage(
            result.error,
            fallback: 'Не удалось изменить статус ученика.',
          ),
        ),
        backgroundColor: AppTheme.danger,
      ),
    );
  }

  Future<void> _openStudent(Map<String, dynamic> student) async {
    final id = student['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final changed = await showClientCard(
      context,
      entityType: 'student',
      entityId: id,
      seed: student,
    );
    if (mounted && changed == true) _refreshBoard();
  }

  Future<void> _createStudent() async {
    final selectedBranchId = _controller.state.selectedBranchId;
    final student = await showStudentCreateSurface(
      context,
      initialBranchId: selectedBranchId == kNoBranchBoardId
          ? null
          : selectedBranchId,
    );
    if (!mounted || student == null) return;
    _refreshBoard();
    await _openStudent(student);
  }

  void _openChat(String linkedUserId) {
    ref
        .read(crmNavigationRequestProvider.notifier)
        .navigateTo(CrmNavigationRequest.directChat(linkedUserId));
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    final canWrite =
        ref
            .watch(capabilitySnapshotProvider)
            .asData
            ?.value
            .allows('crm.client.write') ==
        true;
    final transfer = ref.watch(leadTransferControllerProvider);
    _listenToExternalState();

    final branchId = transfer.isActive
        ? transfer.selectedBranchId ?? state.selectedBranchId
        : state.selectedBranchId;
    var contentState = StudentsBoardContentState.idle;
    var columns = const <StudentsBoardColumnData>[];
    var initialStudents = const <Map<String, dynamic>>[];
    String? nextCursor;
    if (branchId != null) {
      final board = ref.watch(studentBoardProvider(branchId));
      board.when(
        loading: () => contentState = StudentsBoardContentState.loading,
        error: (_, _) => contentState = StudentsBoardContentState.error,
        data: (page) {
          contentState = StudentsBoardContentState.data;
          initialStudents = page.students;
          columns = projectStudentsBoard(
            groupStudentsByStatus([
              ...page.students,
              ...state.extraStudents,
            ], page.stages),
            optimisticStatuses: state.optimisticStatuses,
            query: state.query,
          );
          nextCursor =
              state.extraStudents.isEmpty && state.nextStudentCursor == null
              ? page.nextCursor
              : state.nextStudentCursor;
        },
      );
    }

    return StudentsBoardView(
      state: state,
      canWrite: canWrite,
      transferActive: transfer.isActive,
      activeBranchId: branchId,
      contentState: contentState,
      columns: columns,
      transitions: columns.transitions,
      searchController: _searchController,
      scrollController: _autoScroll.scrollController,
      onSearchChanged: _controller.setQuery,
      onClearSearch: () {
        _searchController.clear();
        _controller.setQuery('');
      },
      onToggleFilters: _controller.toggleFilters,
      onSelectBranch: _controller.selectBranch,
      onRetryBranches: _controller.loadBranches,
      onRetryBoard: _refreshBoard,
      onCreateStudent: _createStudent,
      onOpenStudent: _openStudent,
      onMoveStatus: _moveStatus,
      onOpenChat: _openChat,
      onDragUpdate: (position) => _autoScroll.updateDrag(
        globalPosition: position,
        viewportWidth: MediaQuery.sizeOf(context).width,
        reducedMotion: MediaQuery.maybeOf(context)?.disableAnimations ?? false,
      ),
      onDragEnd: _autoScroll.stop,
      nextCursor: nextCursor,
      onLoadMore: () => _controller.loadMoreStudents(
        branchId: branchId ?? '',
        cursor: nextCursor,
        initialStudents: initialStudents,
      ),
      wrapColumn: transfer.isActive
          ? (context, column, child) =>
                _wrapTransferColumn(transfer, column, child)
          : null,
    );
  }

  void _listenToExternalState() {
    ref.listen(crmRealtimeProvider, (_, next) {
      final event = next.value;
      if (event == null || event.entity != 'student' || event.isFallbackPoll) {
        return;
      }
      final branchId = _controller.state.selectedBranchId;
      if (branchId == null) return;
      _controller.scheduleRealtimeRefresh(() async {
        _controller.resetPages();
        await _refreshAndReadback(branchId);
      });
    });
    ref.listen<String?>(
      leadTransferControllerProvider.select(
        (controller) => controller.selectedBranchId,
      ),
      (_, next) {
        if (next != null) _controller.selectBranch(next);
      },
    );
  }

  Widget _wrapTransferColumn(
    LeadTransferController transfer,
    StudentsBoardColumnData column,
    Widget child,
  ) {
    if (column.status == null) return child;
    return TransferDropZone(
      zoneId: 'column:${column.status}',
      kind: TransferZoneKind.column,
      value: column.status,
      label: column.name,
      controller: transfer,
      builder: (_, hovering, _) => DashedRoundedBorder(
        color: hovering ? AppColor.transferCyan : Colors.transparent,
        child: child,
      ),
    );
  }
}
