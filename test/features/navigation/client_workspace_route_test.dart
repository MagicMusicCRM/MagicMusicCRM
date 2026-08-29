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
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';
import 'package:magic_music_crm/core/workspace/workspace_store.dart';
import 'package:magic_music_crm/core/navigation/responsive_navigation_shell.dart';
import 'package:magic_music_crm/features/auth/data/models/release_gate_models.dart';
import 'package:magic_music_crm/features/auth/providers/release_gate_provider.dart';
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

class _ClientSurfaceSwitchHost extends StatefulWidget {
  const _ClientSurfaceSwitchHost({required this.snapshot});

  final CapabilitySnapshot snapshot;

  @override
  State<_ClientSurfaceSwitchHost> createState() =>
      _ClientSurfaceSwitchHostState();
}

class _ClientSurfaceSwitchHostState extends State<_ClientSurfaceSwitchHost> {
  var _showLead = false;

  @override
  Widget build(BuildContext context) {
    final entityId = _showLead ? 'lead-1' : 'student-1';
    return Column(
      children: [
        TextButton(
          key: const Key('switch-client-entity'),
          onPressed: () => setState(() => _showLead = true),
          child: const Text('Другой клиент'),
        ),
        Expanded(
          child: buildClientWorkspaceSurface(
            snapshot: widget.snapshot,
            route: ContextRouteState(
              link: EntityLink(
                entityType: EntityLinkType.client,
                entityId: entityId,
                rawEntityType: _showLead ? 'lead' : 'student',
              ),
              viewState: ContextViewState(),
            ),
            tabId: 'tab-1',
          )!,
        ),
      ],
    );
  }
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

  test('workspace section change overrides the original commerce focus', () {
    const snapshot = CapabilitySnapshot(
      accountId: 'account-1',
      role: 'manager',
      accessVersion: 1,
      capabilities: {'crm.client.read.basic', 'commerce.client_finance.read'},
      scopes: {},
    );
    final surface =
        buildClientWorkspaceSurface(
              snapshot: snapshot,
              route: ContextRouteState(
                link: EntityLink.typed(
                  entityType: EntityLinkType.payment,
                  entityId: 'payment-1',
                  optionalFocus: EntityLinkFocus(
                    focus: 'payment',
                    filter: {
                      'studentId': 'student-1',
                      'section': 'payments',
                      'paymentId': 'payment-1',
                    },
                  ),
                ),
                viewState: ContextViewState(
                  filters: const {'section': 'subscriptions'},
                ),
              ),
              tabId: 'tab-1',
            )!
            as ClientCardRouteSurface;

    expect(surface.initialSection, 'subscriptions');
    expect(surface.viewState?.filters['section'], 'subscriptions');
    expect(surface.viewState?.filters['paymentId'], 'payment-1');
  });

  for (final role in const ['admin', 'manager', 'director', 'system_admin']) {
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
        expect(find.text('Обзор'), findsWidgets);
        expect(find.text('Занятия'), findsWidgets);
        expect(find.text('Абонементы'), findsWidgets);
        expect(find.text('Прогресс'), findsWidgets);
        expect(find.text('История и задачи'), findsWidgets);
        expect(find.text('Контакты'), findsWidgets);
        expect(find.text('Документы'), findsNothing);
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
        expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'system admin snapshot opens subscription sale while release gate is pending',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.reset);
      final gate = Completer<ReleaseGateStatus>();
      addTearDown(() {
        if (!gate.isCompleted) {
          gate.complete(
            const ReleaseGateStatus(
              role: 'system_admin',
              profileComplete: true,
              legalAccepted: true,
              deletionPending: false,
            ),
          );
        }
      });
      final api = FakeCardApiClient(
        role: 'system_admin',
        student: _student,
        currentProfile: const {
          'id': 'system-admin-1',
          'email': 'root@example.test',
          'role': 'system_admin',
          'firstName': 'Системный',
          'lastName': 'Администратор',
        },
        subscriptionPackages: const [
          {
            'id': 'package-1',
            'name': 'Фортепиано — 8 занятий',
            'lessonsTotal': 8,
            'price': 24000,
          },
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            magicApiClientProvider.overrideWithValue(api),
            crmRealtimeProvider.overrideWith(
              (ref) => const Stream<CrmChangedEvent>.empty(),
            ),
            releaseGateStatusProvider.overrideWith((ref) => gate.future),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ClientCardRouteSurface(
                snapshot: CapabilitySnapshot(
                  accountId: 'system-admin-1',
                  role: 'system_admin',
                  accessVersion: 1,
                  capabilities: {
                    'crm.client.read.basic',
                    'commerce.client_finance.read',
                    'commerce.client_finance.write',
                  },
                  scopes: {},
                ),
                entityType: 'student',
                entityId: 'student-1',
                initialSection: 'subscriptions',
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final sale = find.byKey(
        const Key('subscription-add'),
        skipOffstage: false,
      );
      expect(
        find.byKey(const Key('client-desktop-section-subscriptions')),
        findsOneWidget,
      );
      expect(sale, findsOneWidget);
      tester.widget<FilledButton>(sale).onPressed!();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(
        find.byKey(const Key('subscription-package-selector')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('subscription-payment-method')),
        findsOneWidget,
      );
      expect(find.text('Оплачено сейчас'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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
        ('overview', 'Обзор'),
        ('contacts', 'Контакты'),
        ('lessons', 'Занятия'),
        ('subscriptions', 'Абонементы'),
        ('progress', 'Прогресс'),
        ('payments', 'Оплаты'),
        ('history_tasks', 'История и задачи'),
      ]) {
        expect(
          find.descendant(
            of: find.byKey(Key('client-section-jump-${section.$1}')),
            matching: find.text(section.$2),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(Key('client-desktop-section-${section.$1}')),
          findsOneWidget,
        );
      }
      expect(find.text('Документы'), findsNothing);
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
        tester
            .getTopLeft(
              find.byKey(const Key('client-desktop-section-overview')),
            )
            .dy,
        tester
            .getTopLeft(
              find.byKey(const Key('client-desktop-section-contacts')),
            )
            .dy,
      );
      expect(
        tester
            .getTopLeft(
              find.byKey(const Key('client-desktop-section-subscriptions')),
            )
            .dy,
        tester
            .getTopLeft(
              find.byKey(const Key('client-desktop-section-progress')),
            )
            .dy,
      );
      for (final section in const ['subscriptions', 'progress']) {
        expect(
          tester
              .getSize(find.byKey(Key('client-desktop-section-$section')))
              .height,
          greaterThan(0),
          reason: section,
        );
      }
      expect(
        tester
            .getTopLeft(
              find.byKey(const Key('client-desktop-section-payments')),
            )
            .dy,
        greaterThan(
          tester
              .getTopLeft(
                find.byKey(const Key('client-desktop-section-subscriptions')),
              )
              .dy,
        ),
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
    expect(find.byType(ResponsiveNavigationShell), findsOneWidget);
    expect(find.byType(ClientCardRouteSurface), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(
      find.byKey(const Key('client-section-jump-overview')),
      findsOneWidget,
    );
  });

  testWidgets('desktop tab Save flushes pending card and note before unmount', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);
    final api = FakeCardApiClient(
      role: 'admin',
      student: const {
        ..._student,
        'version': 2,
        'status': 'active',
        'phone': '+79990000000',
      },
      internalNote: const {
        'id': 'note-1',
        'body': 'Старый текст',
        'version': 2,
        'updatedByName': 'Администратор',
        'updatedAt': '2026-08-07T10:00:00.000Z',
      },
    );
    const snapshot = CapabilitySnapshot(
      accountId: 'account-1',
      role: 'admin',
      accessVersion: 1,
      capabilities: {'crm.client.read.basic'},
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

    final workspace = tester
        .widget<DesktopWorkspaceShell>(find.byType(DesktopWorkspaceShell))
        .controller;
    final clientTabId = workspace.state.activeTabId;
    workspace.open(
      const EntityLink(
        entityType: EntityLinkType.client,
        entityId: 'student-2',
        rawEntityType: 'student',
      ),
      explicitNew: true,
    );
    workspace.selectTab(clientTabId);
    await tester.pump();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Имя'),
      'Свежая Анна',
    );
    await tester.pump();
    expect(find.text('Сохраняем…'), findsWidgets);
    expect(
      workspace.state.activeTab.forms.values.any((form) => form.dirty),
      isTrue,
    );
    await tester.enterText(
      find.byKey(const Key('client-internal-note-input')),
      'Свежая заметка',
    );
    await tester.pump();

    await tester.tap(find.byKey(ValueKey('workspace-tab-close-$clientTabId')));
    await tester.pump();
    expect(find.text('Сохранить изменения?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();

    expect(api.updateInternalNoteBody, {
      'body': 'Свежая заметка',
      'expectedVersion': 2,
    });
    expect(
      workspace.state.tabs.any((tab) => tab.tabId == clientTabId),
      isFalse,
      reason: 'The dirty form save must finish before the tab is removed.',
    );
    expect(
      api.updateStudentBody?['firstName'],
      'Свежая Анна',
      reason:
          'PATCH requests: ${api.patchRequests}; tab exists: '
          '${workspace.state.tabs.any((tab) => tab.tabId == clientTabId)}',
    );
  });

  testWidgets('same workspace tab mounts state for the new client entity', (
    tester,
  ) async {
    final api = FakeCardApiClient(
      role: 'admin',
      student: const {..._student, 'version': 1, 'status': 'active'},
      lead: const {
        'id': 'lead-1',
        'version': 1,
        'firstName': 'Борис',
        'lastName': 'Соколов',
        'customData': <String, dynamic>{},
      },
    );
    const snapshot = CapabilitySnapshot(
      accountId: 'account-1',
      role: 'admin',
      accessVersion: 1,
      capabilities: {'crm.client.read.basic'},
      scopes: {},
    );
    await tester.pumpWidget(
      _app(api, const _ClientSurfaceSwitchHost(snapshot: snapshot)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Анна'), findsWidgets);

    await tester.tap(find.byKey(const Key('switch-client-entity')));
    await tester.pumpAndSettle();

    expect(find.text('Борис'), findsWidgets);
    expect(api.getRequests, contains('/crm/leads/lead-1/card'));
  });

  testWidgets('direct client-card unmount unregisters its workspace form', (
    tester,
  ) async {
    final api = FakeCardApiClient(
      role: 'admin',
      student: const {..._student, 'version': 1, 'status': 'active'},
    );
    const snapshot = CapabilitySnapshot(
      accountId: 'account-1',
      role: 'admin',
      accessVersion: 1,
      capabilities: {'crm.client.read.basic'},
      scopes: {},
    );
    final workspace = WorkspaceController(
      accountId: 'account-1',
      initialLink: const EntityLink(
        entityType: EntityLinkType.client,
        entityId: 'student-1',
        rawEntityType: 'student',
      ),
      sharedScope: WorkspaceSharedScope(
        session: Object(),
        cache: Object(),
        realtime: Object(),
      ),
      titleResolver: (_) => 'Клиент',
    );
    addTearDown(workspace.dispose);
    late StateSetter updateHost;
    var mounted = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          magicApiClientProvider.overrideWithValue(api),
          crmRealtimeProvider.overrideWith(
            (ref) => const Stream<CrmChangedEvent>.empty(),
          ),
        ],
        child: MaterialApp(
          home: WorkspaceNavigationScope(
            controller: workspace,
            isDesktop: true,
            child: StatefulBuilder(
              builder: (context, setState) {
                updateHost = setState;
                return mounted
                    ? buildClientWorkspaceSurface(
                        snapshot: snapshot,
                        route: workspace.state.activeTab.currentRoute,
                        tabId: workspace.state.activeTabId,
                      )!
                    : const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(workspace.state.activeTab.forms, isNotEmpty);

    updateHost(() => mounted = false);
    await tester.pump();

    expect(workspace.state.activeTab.forms, isEmpty);
    expect(tester.takeException(), isNull);
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
