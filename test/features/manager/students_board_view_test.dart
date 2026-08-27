import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/students_board_models.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/students_board_widgets.dart';

void main() {
  testWidgets(
    'transfer uses the effective branch before controller branches load',
    (tester) async {
      final searchController = TextEditingController();
      final scrollController = ScrollController();
      addTearDown(searchController.dispose);
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: StudentsBoardView(
            state: StudentsBoardState(),
            canWrite: false,
            transferActive: true,
            activeBranchId: 'branch-transfer',
            contentState: StudentsBoardContentState.loading,
            columns: const [],
            transitions: const {},
            searchController: searchController,
            scrollController: scrollController,
            onSearchChanged: (_) {},
            onClearSearch: () {},
            onToggleFilters: () {},
            onSelectBranch: (_) {},
            onRetryBranches: () {},
            onRetryBoard: () {},
            onCreateStudent: () {},
            onOpenStudent: (_) {},
            onMoveStatus: (_, _) async {},
            onOpenChat: (_) {},
            onDragUpdate: (_) {},
            onDragEnd: () {},
            onLoadMore: () {},
          ),
        ),
      );

      expect(find.byKey(const ValueKey('students-search')), findsNothing);
      expect(find.byType(KanbanSkeleton), findsOneWidget);
    },
  );
}
