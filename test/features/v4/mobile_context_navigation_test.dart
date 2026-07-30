import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/mobile_context_navigator.dart';
import 'package:magic_music_crm/core/navigation/mobile_context_stack.dart';

void main() {
  EntityLink link(String type, String id) {
    return EntityLink.fromJson({'entityType': type, 'entityId': id});
  }

  test('four-level back restores filter date scroll and selected column', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(mobileContextStackProvider.notifier);
    final schedule = link('report', 'schedule');
    controller.start(schedule);

    final states = [
      ContextViewState(
        filters: const {'branch': 'north'},
        date: DateTime.utc(2026, 7, 30),
        scrollOffset: 420,
        selectedColumn: 'day',
      ),
      ContextViewState(
        filters: const {'status': 'active'},
        scrollOffset: 120,
        selectedColumn: 'lessons',
      ),
      ContextViewState(
        filters: const {'kind': 'subscription'},
        scrollOffset: 64,
        selectedColumn: 'finance',
      ),
    ];

    controller.push(link('student', 'student-1'), currentViewState: states[0]);
    controller.push(link('lesson', 'lesson-1'), currentViewState: states[1]);
    controller.push(link('homework', 'homework-1'), currentViewState: states[2]);
    expect(container.read(mobileContextStackProvider).entries, hasLength(4));

    controller.pop();
    expect(
      container
          .read(mobileContextStackProvider)
          .current
          ?.viewState
          .selectedColumn,
      'finance',
    );
    controller.pop();
    expect(
      container.read(mobileContextStackProvider).current?.viewState.filters,
      {'status': 'active'},
    );
    controller.pop();
    final restored = container
        .read(mobileContextStackProvider)
        .current
        ?.viewState;
    expect(restored?.date, DateTime.utc(2026, 7, 30));
    expect(restored?.scrollOffset, 420);
    expect(restored?.selectedColumn, 'day');
  });

  test('context route state round-trips without domain DTO', () {
    final route = ContextRouteState(
      link: link('student', 'student-1'),
      viewState: ContextViewState(
        filters: const {'status': 'trial'},
        date: DateTime.utc(2026, 7, 30),
        scrollOffset: 90.5,
        selectedColumn: 'trial',
      ),
    );
    final restored = ContextRouteState.fromJson(route.toJson());
    expect(restored.link.entityId, 'student-1');
    expect(restored.viewState.filters, {'status': 'trial'});
    expect(restored.viewState.scrollOffset, 90.5);
    expect(restored.toJson().toString(), isNot(contains('token')));
  });

  test('authenticated deep link creates a correct home back path', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(mobileContextStackProvider.notifier);
    final home = link('report', 'reports-home');
    final target = link('student', 'student-1');

    controller.openAuthenticatedDeepLink(
      home: home,
      target: target,
      authenticated: false,
    );
    var state = container.read(mobileContextStackProvider);
    expect(state.awaitingAuthentication, isTrue);
    expect(state.pendingDeepLink?.entityId, 'student-1');

    controller.completeAuthentication(home);
    state = container.read(mobileContextStackProvider);
    expect(
      state.entries.map((entry) => entry.link.entityId),
      ['reports-home', 'student-1'],
    );
    controller.pop();
    expect(
      container.read(mobileContextStackProvider).current?.link.entityId,
      'reports-home',
    );
  });

  testWidgets('mobile navigator uses stack only and handles system back', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(mobileContextStackProvider.notifier);
    controller.start(link('report', 'root'));
    controller.push(link('student', 'student-1'));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: MobileContextNavigator(
            pageBuilder: (_, route) => Scaffold(
              body: Text(route.link.entityId),
            ),
          ),
        ),
      ),
    );
    expect(find.text('student-1'), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('root'), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
  });
}
