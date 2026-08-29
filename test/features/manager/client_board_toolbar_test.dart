import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/client_board_toolbar.dart';

void main() {
  testWidgets(
    'narrow client toolbar wraps controls without a nested scrollbar',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(340, 520);
      addTearDown(tester.view.reset);
      final searchController = TextEditingController();
      addTearDown(searchController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClientBoardToolbar(
              title: 'Воронка продаж · 1',
              searchKey: const ValueKey('test-search'),
              searchController: searchController,
              searchHint: 'Имя или телефон',
              activeFilterCount: 0,
              onSearchChanged: (_) {},
              onSearchSubmitted: (_) {},
              onClearSearch: () {},
              onFiltersPressed: () {},
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.text('Фильтры'), findsOneWidget);
      expect(find.byKey(const ValueKey('test-search')), findsOneWidget);
    },
  );
}
