import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/magic_desktop_scrollbar.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/client_board_toolbar.dart';

import 'students_board_columns.dart';
import 'students_board_models.dart';

typedef StudentsBoardColumnWrapper =
    Widget Function(BuildContext, StudentsBoardColumnData, Widget);

class StudentsBoardView extends StatelessWidget {
  const StudentsBoardView({
    super.key,
    required this.state,
    required this.canWrite,
    required this.transferActive,
    required this.activeBranchId,
    required this.contentState,
    required this.columns,
    required this.transitions,
    required this.searchController,
    required this.scrollController,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onToggleFilters,
    required this.onSelectBranch,
    required this.onRetryBranches,
    required this.onRetryBoard,
    required this.onCreateStudent,
    required this.onOpenStudent,
    required this.onMoveStatus,
    required this.onOpenChat,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onLoadMore,
    this.nextCursor,
    this.wrapColumn,
  });

  final StudentsBoardState state;
  final bool canWrite;
  final bool transferActive;
  final String? activeBranchId;
  final StudentsBoardContentState contentState;
  final List<StudentsBoardColumnData> columns;
  final Map<String, Set<String>> transitions;
  final TextEditingController searchController;
  final ScrollController scrollController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onToggleFilters;
  final ValueChanged<String> onSelectBranch;
  final VoidCallback onRetryBranches;
  final VoidCallback onRetryBoard;
  final VoidCallback onCreateStudent;
  final ValueChanged<Map<String, dynamic>> onOpenStudent;
  final Future<void> Function(Map<String, dynamic>, String) onMoveStatus;
  final ValueChanged<String> onOpenChat;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onLoadMore;
  final String? nextCursor;
  final StudentsBoardColumnWrapper? wrapColumn;

  @override
  Widget build(BuildContext context) {
    if (transferActive && activeBranchId != null) {
      return Column(children: [Expanded(child: _buildBoard())]);
    }
    final toolbar = _StudentsToolbar(
      state: state,
      searchController: searchController,
      onSearchChanged: onSearchChanged,
      onClearSearch: onClearSearch,
      onToggleFilters: onToggleFilters,
      onSelectBranch: onSelectBranch,
    );
    if (!state.branchesLoaded && state.branchLoadError == null) {
      return Column(
        children: [
          toolbar,
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }
    if (state.branchLoadError != null) {
      return Column(
        children: [
          toolbar,
          Expanded(
            child: _LoadError(
              title: state.branchLoadError!,
              onRetry: onRetryBranches,
            ),
          ),
        ],
      );
    }
    if (state.branches.isEmpty) {
      return Column(
        children: [
          toolbar,
          const Expanded(child: _NoBranches()),
        ],
      );
    }
    if (state.selectedBranchId == null) {
      return Column(
        children: [
          toolbar,
          const Expanded(child: KanbanSkeleton()),
        ],
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canWrite
          ? FloatingActionButton(
              key: const ValueKey('students-create'),
              onPressed: onCreateStudent,
              tooltip: 'Новый ученик',
              child: const Icon(Icons.person_add_rounded),
            )
          : null,
      body: Column(
        children: [
          toolbar,
          Expanded(child: _buildBoard()),
        ],
      ),
    );
  }

  Widget _buildBoard() => switch (contentState) {
    StudentsBoardContentState.loading ||
    StudentsBoardContentState.idle => const KanbanSkeleton(),
    StudentsBoardContentState.error => _LoadError(
      title: 'Не удалось загрузить учеников',
      onRetry: onRetryBoard,
    ),
    StudentsBoardContentState.data => MagicDesktopScrollbar(
      axis: Axis.horizontal,
      controller: scrollController,
      builder: (context, controller) => SingleChildScrollView(
        controller: controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final column in columns) _wrap(context, column)],
        ),
      ),
    ),
  };

  Widget _wrap(BuildContext context, StudentsBoardColumnData column) {
    final child = StudentStatusColumn(
      column: column,
      transitions: transitions,
      pendingStudentIds: state.pendingStudentIds,
      onTap: onOpenStudent,
      onMove: onMoveStatus,
      onOpenChat: onOpenChat,
      onDragUpdate: onDragUpdate,
      onDragEnd: onDragEnd,
      nextCursor: nextCursor,
      loadingMore: state.loadingMoreStudents,
      onLoadMore: onLoadMore,
    );
    return wrapColumn?.call(context, column, child) ?? child;
  }
}

class _StudentsToolbar extends StatelessWidget {
  const _StudentsToolbar({
    required this.state,
    required this.searchController,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onToggleFilters,
    required this.onSelectBranch,
  });

  final StudentsBoardState state;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onToggleFilters;
  final ValueChanged<String> onSelectBranch;

  @override
  Widget build(BuildContext context) {
    final seen = <String>{};
    final items =
        state.branches
            .where((branch) => seen.add(branch['id']?.toString() ?? ''))
            .map(
              (branch) => DropdownMenuItem<String>(
                value: branch['id']?.toString() ?? '',
                child: Text(
                  branch['name']?.toString() ?? branch['id']?.toString() ?? '',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList()
          ..add(
            const DropdownMenuItem(
              value: '__none__',
              child: Text('Без филиала'),
            ),
          );
    final filter =
        state.filtersOpen &&
            state.branchesLoaded &&
            state.branchLoadError == null &&
            state.branches.isNotEmpty
        ? Container(
            key: const ValueKey('students-filters-panel'),
            width: 360,
            margin: const EdgeInsets.only(top: AppSpace.sm),
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: DropdownButtonFormField<String>(
              menuMaxHeight: 256,
              key: ValueKey('branch:${state.selectedBranchId}'),
              initialValue: state.selectedBranchId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Филиал',
                isDense: true,
              ),
              items: items,
              onChanged: (value) {
                if (value?.isNotEmpty == true) onSelectBranch(value!);
              },
            ),
          )
        : null;
    return ClientBoardToolbar(
      title: 'Ученики',
      searchKey: const ValueKey('students-search'),
      searchController: searchController,
      searchHint: 'Имя или телефон',
      activeFilterCount: state.selectedBranchId == null ? 0 : 1,
      onSearchChanged: onSearchChanged,
      onSearchSubmitted: onSearchChanged,
      onClearSearch: onClearSearch,
      onFiltersPressed: onToggleFilters,
      inlineFilters: filter,
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.title, required this.onRetry});

  final String title;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppTheme.danger,
            size: 42,
          ),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text(
            'Проверьте подключение и попробуйте снова.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Повторить'),
          ),
        ],
      ),
    ),
  );
}

class _NoBranches extends StatelessWidget {
  const _NoBranches();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.location_off_rounded, size: 42, color: Colors.grey),
        SizedBox(height: 10),
        Text(
          'Нет филиалов',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        SizedBox(height: 4),
        Text(
          'Добавьте хотя бы один филиал в настройках.',
          style: TextStyle(color: Colors.grey),
        ),
      ],
    ),
  );
}
