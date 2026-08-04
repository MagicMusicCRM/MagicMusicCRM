import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/workspace/desktop_workspace_shell.dart';
import 'package:magic_music_crm/core/workspace/workspace_store.dart';
import 'package:magic_music_crm/features/admin/presentation/screens/admin_dashboard_screen.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/show_client_card.dart';

import '../crm/client_card/card_fake_api.dart';

const _student = {
  'id': 'student-1',
  'firstName': 'Анна',
  'lastName': 'Смирнова',
  'customData': <String, dynamic>{},
};

Widget _app(FakeCardApiClient api, Widget child) {
  return ProviderScope(
    overrides: [
      magicApiClientProvider.overrideWithValue(api),
      crmRealtimeProvider.overrideWith(
        (ref) => const Stream<CrmChangedEvent>.empty(),
      ),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  for (final role in const ['admin', 'manager', 'director']) {
    for (final width in const [360.0, 840.0, 1200.0]) {
      testWidgets('$role fills ${width.toInt()} and restores section', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        addTearDown(tester.view.reset);
        final api = FakeCardApiClient(role: role, student: _student);
        await tester.pumpWidget(
          _app(
            api,
            ClientCardRouteSurface(
              snapshot: CapabilitySnapshot(
                accountId: 'account-1',
                role: role,
                accessVersion: 1,
                capabilities: const {
                  'crm.client.read.basic',
                  'commerce.client_finance.read',
                },
                scopes: const {},
              ),
              entityType: 'student',
              entityId: 'student-1',
              initialSection: 'payments',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(Dialog), findsNothing);
        expect(find.byKey(const Key('client-payments-tab')), findsOneWidget);
        expect(find.text('Оплаты и личный счёт'), findsOneWidget);
        expect(find.text('Обзор'), findsOneWidget);
        expect(find.text('Занятия'), findsOneWidget);
        expect(find.text('Абонементы'), findsOneWidget);
        expect(find.text('История и задачи'), findsOneWidget);
        expect(find.text('Контакты'), findsOneWidget);
        expect(find.text('Документы'), findsOneWidget);
        expect(find.text('Доп. поля'), findsOneWidget);
        expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('forbidden client workspace does not mount a data fetcher', (
    tester,
  ) async {
    final api = FakeCardApiClient(role: 'client', student: _student);
    await tester.pumpWidget(
      _app(
        api,
        const ClientCardRouteSurface(
          snapshot: CapabilitySnapshot(
            accountId: 'account-1',
            role: 'client',
            accessVersion: 1,
            capabilities: {},
            scopes: {},
          ),
          entityType: 'student',
          entityId: 'student-1',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Карточка клиента недоступна'), findsOneWidget);
    expect(api.getRequests, isEmpty);
  });

  testWidgets('lead preferred schedule lives only in canonical Lessons', (
    tester,
  ) async {
    const lead = {
      'id': 'lead-1',
      'firstName': 'Пётр',
      'lastName': 'Соколов',
      'customData': {'preferredSchedule': 'Вечером по будням'},
    };
    final api = FakeCardApiClient(role: 'admin', lead: lead);
    await tester.pumpWidget(
      _app(
        api,
        const ClientCard(
          lead: {'id': 'lead-1'},
          entityType: 'lead',
          routed: true,
          capabilitySnapshot: CapabilitySnapshot(
            accountId: 'account-1',
            role: 'admin',
            accessVersion: 1,
            capabilities: {
              'crm.client.read.basic',
              'schedule.lesson.read.assigned',
              'schedule.lesson.write',
            },
            scopes: {'schedule': 'branch'},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Предпочтительное расписание'), findsNothing);
    await tester.tap(find.text('Занятия'));
    await tester.pumpAndSettle();
    expect(find.text('Предпочтительное расписание'), findsOneWidget);
    expect(find.textContaining('Вечером по будням'), findsOneWidget);
    final call = api.getCalls.singleWhere(
      (request) => request.path == '/crm/schedule-series',
    );
    expect(call.query, {'clientType': 'lead', 'clientId': 'lead-1'});
  });

  testWidgets('preferred schedule creates branch-scoped weekday slots', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);
    const lead = {
      'id': 'lead-1',
      'firstName': 'Пётр',
      'branchId': 'branch-a',
      'customData': <String, dynamic>{},
    };
    final api = FakeCardApiClient(
      role: 'admin',
      lead: lead,
      branches: const [
        {'id': 'branch-a', 'name': 'Сокол'},
      ],
      teachers: const [
        {'id': 'teacher-a', 'firstName': 'Мария', 'lastName': 'Иванова'},
      ],
      rooms: const [
        {
          'id': 'room-a',
          'branchId': 'branch-a',
          'branchName': 'Сокол',
          'name': 'Класс 1',
        },
      ],
    );
    await tester.pumpWidget(
      _app(
        api,
        const ClientCard(
          lead: {'id': 'lead-1'},
          entityType: 'lead',
          routed: true,
          initialSection: 'lessons',
          capabilitySnapshot: CapabilitySnapshot(
            accountId: 'account-1',
            role: 'admin',
            accessVersion: 1,
            capabilities: {
              'crm.client.read.basic',
              'schedule.lesson.read.assigned',
              'schedule.lesson.write',
            },
            scopes: {'schedule': 'branch'},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Добавить предпочтение'));
    await tester.pumpAndSettle();
    final initialDay = DateTime.now().weekday;
    final addedDay = initialDay == DateTime.monday
        ? DateTime.tuesday
        : DateTime.monday;
    await tester.tap(
      find.byKey(ValueKey('preferred-schedule-weekday-$addedDay')),
    );
    await tester.tap(find.text('Выберите педагога'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Мария Иванова'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выберите аудиторию'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Класс 1'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('preferred-schedule-lessons-per-day')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('2').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('preferred-schedule-save')),
    );
    await tester.tap(find.byKey(const ValueKey('preferred-schedule-save')));
    await tester.pumpAndSettle();

    final creates = api.postRequests
        .where((request) => request.path == '/crm/schedule-series')
        .toList();
    expect(creates, hasLength(4));
    for (final request in creates) {
      expect(request.data['clientRef'], {'type': 'lead', 'id': 'lead-1'});
      expect(request.data['branchId'], 'branch-a');
      expect(request.data['validUntil'], isNotNull);
    }
    expect(creates.map((request) => request.data['beginTime']).toSet(), {
      '15:00',
      '16:00',
    });
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('production desktop host mounts the routed client workspace', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);
    final api = FakeCardApiClient(role: 'admin', student: _student);
    const snapshot = CapabilitySnapshot(
      accountId: 'account-1',
      role: 'admin',
      accessVersion: 1,
      capabilities: {'crm.client.read.basic', 'commerce.client_finance.read'},
      scopes: {},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          magicApiClientProvider.overrideWithValue(api),
          capabilitySnapshotProvider.overrideWith((ref) async => snapshot),
          accountWorkspaceStoreProvider.overrideWithValue(
            AccountWorkspaceStore(InMemoryWorkspaceKeyValueStore()),
          ),
          crmRealtimeProvider.overrideWith(
            (ref) => const Stream<CrmChangedEvent>.empty(),
          ),
        ],
        child: const MaterialApp(
          home: AdminDashboardScreen(
            initialLink: EntityLink(
              entityType: EntityLinkType.client,
              entityId: 'student-1',
              rawEntityType: 'student',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DesktopWorkspaceShell), findsOneWidget);
    expect(find.byType(ClientCardRouteSurface), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Обзор'), findsOneWidget);
  });

  testWidgets('section selection updates the direct link without refetch', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);
    final api = FakeCardApiClient(role: 'manager', student: _student);
    final router = GoRouter(
      initialLocation: '/students/student-1?section=overview',
      routes: [
        GoRoute(
          path: '/students/:id',
          builder: (context, state) => Scaffold(
            body: ClientCardRouteSurface(
              snapshot: const CapabilitySnapshot(
                accountId: 'account-1',
                role: 'manager',
                accessVersion: 1,
                capabilities: {
                  'crm.client.read.basic',
                  'commerce.client_finance.read',
                },
                scopes: {},
              ),
              entityType: 'student',
              entityId: state.pathParameters['id']!,
              initialSection:
                  state.uri.queryParameters['section'] ?? 'overview',
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          magicApiClientProvider.overrideWithValue(api),
          crmRealtimeProvider.overrideWith(
            (ref) => const Stream<CrmChangedEvent>.empty(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Оплаты'));
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.queryParameters['section'],
      'payments',
    );
    expect(find.byKey(const Key('client-payments-tab')), findsOneWidget);
    expect(api.studentCardLoadCount, 1);
  });

  testWidgets('routed and legacy hosts keep the same client API trace', (
    tester,
  ) async {
    final routedApi = FakeCardApiClient(role: 'manager', student: _student);
    await tester.pumpWidget(
      _app(
        routedApi,
        const ClientCard(
          lead: {'id': 'student-1'},
          entityType: 'student',
          routed: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final routedTrace = [...routedApi.getRequests]..sort();

    final legacyApi = FakeCardApiClient(role: 'manager', student: _student);
    await pumpClientCard(
      tester,
      api: legacyApi,
      seed: const {'id': 'student-1'},
      entityType: 'student',
    );
    final legacyTrace = [...legacyApi.getRequests]..sort();

    expect(routedTrace, legacyTrace);
  });
}
