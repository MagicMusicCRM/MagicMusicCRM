import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';

import 'card_fake_api.dart';

void main() {
  late FakeCardApiClient api;
  late StreamController<CrmChangedEvent> events;
  late ProviderContainer container;

  setUp(() {
    api = FakeCardApiClient(
      student: {
        'id': 'student-1',
        'version': 2,
        'status': 'active',
        'firstName': 'Иван',
        'lastName': 'Петров',
        'customData': <String, dynamic>{},
      },
    );
    events = StreamController<CrmChangedEvent>();
    container = ProviderContainer(
      overrides: [
        magicApiClientProvider.overrideWithValue(api),
        crmRealtimeProvider.overrideWith((ref) => events.stream),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await events.close();
  });

  Future<void> open(WidgetTester tester) async {
    await pumpClientCard(
      tester,
      api: api,
      seed: const {'id': 'student-1'},
      entityType: 'student',
      container: container,
    );
    api.getCalls.clear();
  }

  testWidgets('finance burst requests only one commerce projection', (
    tester,
  ) async {
    await open(tester);
    for (var i = 0; i < 6; i++) {
      events.add(
        CrmChangedEvent(entity: 'finance', action: 'updated', id: '$i'),
      );
    }
    await tester.pumpAndSettle();
    expect(api.getCalls.map((c) => c.path).toList(), [
      '/crm/students/student-1/commerce',
    ]);
    expect(find.text('Иван'), findsWidgets);
  });

  testWidgets('events during opening preserve the initial identity', (
    tester,
  ) async {
    final gate = Completer<void>();
    api.nextStudentCardGate = gate;
    await pumpClientCard(
      tester,
      api: api,
      seed: const {'id': 'student-1'},
      entityType: 'student',
      container: container,
      settle: false,
    );
    events.add(const CrmChangedEvent(entity: 'finance', action: 'updated'));
    await tester.pump();
    expect(api.studentCardLoadCount, 1);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Иван'), findsWidgets);
    expect(api.studentCardLoadCount, 1);
    expect(api.getCalls.where((c) => c.path.endsWith('/commerce')).length, 2);
  });

  testWidgets('events during an active request produce one trailing refresh', (
    tester,
  ) async {
    await open(tester);
    final gate = Completer<void>();
    api.nextStudentCardGate = gate;
    events.add(const CrmChangedEvent(entity: 'student', action: 'updated'));
    await tester.pump();
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      events.add(
        CrmChangedEvent(entity: 'lesson', action: 'updated', id: '$i'),
      );
      await tester.pump();
    }
    expect(api.studentCardLoadCount, 2);
    gate.complete();
    await tester.pumpAndSettle();
    expect(api.studentCardLoadCount, 3);
    expect(api.getCalls.where((c) => c.path.endsWith('/commerce')).length, 2);
  });

  testWidgets('student and finance burst share a single full student read', (
    tester,
  ) async {
    await open(tester);
    for (final entity in ['student', 'lesson', 'group', 'finance']) {
      events.add(CrmChangedEvent(entity: entity, action: 'updated'));
    }
    await tester.pumpAndSettle();
    expect(api.getCalls.where((c) => c.path.endsWith('/card')).length, 1);
    expect(api.getCalls.where((c) => c.path.endsWith('/commerce')).length, 1);
  });

  testWidgets(
    'hidden workspace accumulates changes and refreshes once on activation',
    (tester) async {
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (_, active, child) =>
                  TickerMode(enabled: active, child: child!),
              child: const Material(
                child: ClientCard(
                  lead: {'id': 'student-1'},
                  entityType: 'student',
                  routed: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      visible.value = false;
      await tester.pump();
      api.getCalls.clear();
      for (var i = 0; i < 6; i++) {
        events.add(const CrmChangedEvent(entity: 'finance', action: 'updated'));
        await tester.pump();
      }
      expect(api.getCalls, isEmpty);
      visible.value = true;
      await tester.pumpAndSettle();
      expect(api.getCalls.map((c) => c.path).toList(), [
        '/crm/students/student-1/commerce',
      ]);
    },
  );
}
