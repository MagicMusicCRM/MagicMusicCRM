import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/workspace/desktop_workspace_shell.dart';
import 'package:magic_music_crm/core/workspace/workspace_store.dart';
import 'package:magic_music_crm/core/widgets/v7/v7_nav_shell.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/show_client_card.dart';
import 'package:magic_music_crm/features/crm/presentation/staff_workspace_screen.dart';

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
  setUpAll(() => initializeDateFormatting('ru'));

  test('payment and subscription refs reuse the canonical client sections', () {
    const snapshot = CapabilitySnapshot(
      accountId: 'account-1',
      role: 'manager',
      accessVersion: 1,
      capabilities: {'crm.client.read.basic', 'commerce.client_finance.read'},
      scopes: {},
    );
    for (final entry in const [
      (type: EntityLinkType.payment, section: 'payments', idKey: 'paymentId'),
      (
        type: EntityLinkType.subscription,
        section: 'subscriptions',
        idKey: 'subscriptionId',
      ),
    ]) {
      final surface = buildClientWorkspaceSurface(
        snapshot: snapshot,
        route: ContextRouteState(
          link: EntityLink.typed(
            entityType: entry.type,
            entityId: 'commerce-1',
            optionalFocus: EntityLinkFocus(
              focus: entry.type.name,
              filter: {
                'studentId': 'student-1',
                'section': entry.section,
                entry.idKey: 'commerce-1',
              },
            ),
          ),
          viewState: ContextViewState(scrollOffset: 144),
        ),
        tabId: 'tab-1',
      );

      expect(surface, isA<ClientCardRouteSurface>());
      final card = surface! as ClientCardRouteSurface;
      expect(card.entityId, 'student-1');
      expect(card.initialSection, entry.section);
      expect(card.viewState?.filters[entry.idKey], 'commerce-1');
      expect(card.viewState?.scrollOffset, 144);
    }
  });

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
                capabilities: {
                  'crm.client.read.basic',
                  'commerce.client_finance.read',
                  'workflow.task.read',
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
        expect(find.text('Прогресс'), findsOneWidget);
        expect(find.text('История и задачи'), findsWidgets);
        expect(find.text('Контакты'), findsOneWidget);
        expect(find.text('Документы'), findsOneWidget);
        expect(find.text('Доп. поля'), findsNothing);
        expect(api.getRequests, isNot(contains('/crm/schedule-plans')));
        expect(api.getRequests, isNot(contains('/crm/schedule-series')));
        expect(
          find.byKey(
            const Key('client-custom-fields-expansion'),
            skipOffstage: false,
          ),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'desktop client card is one canvas with a lazy calendar after preferences',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.reset);
      final api = FakeCardApiClient(
        role: 'manager',
        student: _student,
        branches: const [
          {'id': 'branch-1', 'name': 'Главный'},
        ],
        teachers: const [
          {'id': 'teacher-1', 'firstName': 'Мария', 'lastName': 'Иванова'},
        ],
        studentLessons: const [
          {
            'id': 'lesson-1',
            'studentId': 'student-1',
            'studentName': 'Анна Смирнова',
            'branchId': 'branch-1',
            'teacherId': 'teacher-1',
            'scheduledAt': '2026-08-08T12:00:00.000Z',
            'durationMinutes': 60,
            'status': 'scheduled',
            'version': 1,
          },
        ],
        schedulePlans: const [
          {
            'id': 'plan-1',
            'kind': 'individual',
            'title': 'Индивидуальный вокал',
            'studentId': 'student-1',
            'activeFrom': '2026-08-01',
            'activeUntil': null,
            'status': 'active',
            'version': 1,
            'rows': [
              {
                'id': 'series-1',
                'teacherId': 'teacher-1',
                'teacherName': 'Мария Иванова',
                'branchId': 'branch-1',
                'branchName': 'Главный',
                'weekday': 6,
                'beginTime': '12:00',
                'durationMinutes': 60,
                'validFrom': '2026-08-01',
                'validUntil': null,
                'active': true,
              },
            ],
          },
        ],
        schedulePlanTrays: {
          'plan-1': {
            'planId': 'plan-1',
            'items': [
              {
                'id': 'lesson-1',
                'scheduledAt': '2026-08-08T12:00:00.000Z',
                'localDate': '2026-08-08',
                'localTime': '12:00',
                'state': 'scheduled',
                'settlementMarkers': [],
                'relationMarker': 'none',
                'teacher': {'id': 'teacher-1', 'name': 'Мария Иванова'},
                'room': null,
              },
            ],
            'hasPrevious': false,
            'hasNext': false,
          },
        },
      );
      await tester.pumpWidget(
        _app(
          api,
          const ClientCard(
            lead: {'id': 'student-1'},
            entityType: 'student',
            routed: true,
            capabilitySnapshot: CapabilitySnapshot(
              accountId: 'account-1',
              role: 'manager',
              accessVersion: 1,
              capabilities: {
                'crm.client.read.basic',
                'commerce.client_finance.read',
                'schedule.lesson.read.assigned',
                'schedule.lesson.write',
                'workflow.task.read',
              },
              scopes: {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('client-desktop-canvas')), findsOneWidget);
      expect(
        find.byKey(const Key('client-desktop-section-rail')),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('client-desktop-canvas'))).dx,
        greaterThan(
          tester
              .getTopRight(find.byKey(const Key('client-desktop-section-rail')))
              .dx,
        ),
      );
      for (final section in const [
        'Обзор',
        'Занятия',
        'Оплаты',
        'Абонементы',
        'Прогресс',
        'История и задачи',
        'Контакты',
        'Документы',
      ]) {
        expect(find.text(section), findsOneWidget);
      }
      expect(
        find.byKey(const Key('client-calendar-expansion')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('client-calendar-widget')), findsNothing);
      expect(find.text('Постоянные расписания'), findsOneWidget);
      expect(find.text('Индивидуальный вокал'), findsOneWidget);
      expect(find.byKey(const Key('client-lesson-date-tray')), findsOneWidget);
      expect(find.text('Фактические занятия'), findsNothing);
      expect(find.text('Предстоящие'), findsNothing);
      expect(find.text('Прошедшие'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Обзор')).dy,
        tester.getTopLeft(find.text('Контакты')).dy,
      );
      expect(
        tester.getTopLeft(find.text('Абонементы')).dy,
        tester.getTopLeft(find.text('Прогресс')).dy,
      );
      expect(
        tester.getTopLeft(find.text('Оплаты')).dy,
        greaterThan(tester.getTopLeft(find.text('Абонементы')).dy),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('client-lesson-lesson-1')),
      );
      await tester.tap(find.byKey(const ValueKey('client-lesson-lesson-1')));
      await tester.pumpAndSettle();
      expect(find.text('Перенести или изменить занятие'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Постоянные расписания')).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const Key('client-calendar-expansion')))
              .dy,
        ),
      );

      await tester.ensureVisible(
        find.byKey(const Key('client-calendar-expansion')),
      );
      await tester.tap(find.byKey(const Key('client-calendar-expansion')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('client-calendar-widget')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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

  testWidgets('lead lessons do not mount the legacy preference editor', (
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
    expect(find.text('Предпочтительное расписание'), findsNothing);
    expect(find.text('Добавить предпочтение'), findsNothing);
    expect(find.textContaining('Вечером по будням'), findsNothing);
    expect(
      api.getCalls.where((request) => request.path == '/crm/schedule-series'),
      isEmpty,
    );
  });

  testWidgets('student schedule uses Plan without the legacy series API', (
    tester,
  ) async {
    final api = FakeCardApiClient(role: 'admin', student: _student);
    await tester.pumpWidget(
      _app(
        api,
        const ClientCard(
          lead: {'id': 'student-1'},
          entityType: 'student',
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

    expect(find.text('Постоянные расписания'), findsOneWidget);
    expect(find.text('Предпочтительное расписание'), findsNothing);
    expect(find.text('Добавить предпочтение'), findsNothing);
    expect(
      api.getCalls
          .where((request) => request.path == '/crm/schedule-series')
          .toList(),
      isEmpty,
    );
    expect(
      api.postRequests.where(
        (request) => request.path == '/crm/schedule-series',
      ),
      isEmpty,
    );
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
          home: StaffWorkspaceScreen(
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
    expect(find.byType(V7NavShell), findsOneWidget);
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
      initialLocation: '/manager',
      routes: [
        GoRoute(
          path: '/manager',
          builder: (context, state) => const Scaffold(body: Text('Manager')),
        ),
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
    router.push('/students/student-1?section=overview');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('client-section-jump-payments')));
    await tester.pumpAndSettle();

    expect(router.state.uri.queryParameters['section'], 'payments');
    expect(find.byType(ClientCardRouteSurface), findsOneWidget);
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
