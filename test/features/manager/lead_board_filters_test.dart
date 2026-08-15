import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/manager/presentation/providers/leads_providers.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/lead_board_filters.dart';

void main() {
  testWidgets(
    'lead board exposes every canonical filter, period and deterministic sort',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      var latest = const LeadBoardFilters(
        q: 'UAT',
        branchId: 'branch-a',
        statusId: 'status-a',
        assignedTo: 'manager-a',
        source: 'Сайт',
        discipline: 'Вокал',
        level: 'Начальный',
        category: 'Взрослый',
        requestType: 'Пробное занятие',
        goal: 'Поставить голос',
        gender: 'Женский',
        preferredSchedule: 'вечер',
        from: '2026-06-01T00:00:00.000Z',
        to: '2026-07-01T00:00:00.000Z',
        sort: 'oldest',
        quick: 'active',
        openTasks: true,
        hideConverted: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: LeadsInlineFilterPanel(
                filters: latest,
                searchText: 'UAT',
                branches: const [
                  {'id': 'branch-a', 'name': 'Центр'},
                ],
                sources: const [
                  {'id': 'source-a', 'name': 'Сайт'},
                ],
                responsibles: const [
                  {'id': 'manager-a', 'name': 'Мария Менеджер'},
                ],
                statuses: const [('status-a', 'Новый', Colors.amber)],
                disciplines: const [
                  {'id': 'Вокал', 'name': 'Вокал'},
                ],
                levels: const [
                  {'id': 'Начальный', 'name': 'Начальный'},
                ],
                categories: const [
                  {'id': 'Взрослый', 'name': 'Взрослый'},
                ],
                onApply: (filters) => latest = filters,
                onCollapse: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final label in const [
        'Филиал',
        'Статус',
        'Источник',
        'Ответственный',
        'Направление',
        'Уровень',
        'Категория',
        'Тип обращения',
        'Цель обучения',
        'Пол',
        'Предпочитаемое расписание',
        'Сортировка',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('Есть задачи'), findsOneWidget);
      expect(find.text('Скрыть ставших учениками'), findsOneWidget);
      expect(find.text('Сначала старые'), findsOneWidget);
      expect(find.text('01.06.2026 - 30.06.2026'), findsOneWidget);
      expect(find.byKey(const ValueKey('lead-filter-period')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('lead-filter-period-clear')));
      expect(latest.from, isEmpty);
      expect(latest.to, isEmpty);

      await tester.tap(find.text('Сбросить'));
      expect(latest, const LeadBoardFilters(q: 'UAT'));
    },
  );

  testWidgets('inline source and free-text filters commit through one state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var latest = const LeadBoardFilters(q: 'Анна');

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: LeadsInlineFilterPanel(
                filters: latest,
                searchText: 'Анна',
                branches: const [],
                sources: const [
                  {'id': 'source-a', 'name': 'Сайт'},
                ],
                responsibles: const [
                  {'id': 'manager-a', 'name': 'Мария Менеджер'},
                ],
                statuses: const [],
                disciplines: const [],
                levels: const [],
                categories: const [],
                onApply: (filters) => setState(() => latest = filters),
                onCollapse: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('Источник:')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сайт').last);
    await tester.pumpAndSettle();
    expect(latest.q, 'Анна');
    expect(latest.source, 'Сайт');

    final requestType = find.byKey(
      const ValueKey('lead-filter-Тип обращения:'),
    );
    await tester.ensureVisible(requestType);
    await tester.enterText(requestType, 'Пробное занятие');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(latest.q, 'Анна');
    expect(latest.source, 'Сайт');
    expect(latest.requestType, 'Пробное занятие');
  });
}
