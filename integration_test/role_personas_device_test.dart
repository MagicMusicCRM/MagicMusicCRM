import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/workspace/workspace_store.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';
import 'package:magic_music_crm/features/client/presentation/screens/client_dashboard_screen.dart';
import 'package:magic_music_crm/features/crm/presentation/staff_workspace_screen.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/clients_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/manager_overview_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/reports_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_panel.dart';
import 'package:magic_music_crm/features/teacher/presentation/widgets/teacher_schedule_widget.dart';
import 'package:magic_music_crm/features/teacher/presentation/widgets/teacher_students_widget.dart';

import 'evidence_screenshot.dart';

const _studentId = '10000000-0000-4000-8000-000000000140';
const _branchId = '20000000-0000-4000-8000-000000000140';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru', null));

  testWidgets('UAT-140 Client completes the private mobile functional tour', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _PersonaApi(role: 'client');

    await tester.pumpWidget(_clientApp(api));
    await _pumpFor(tester);

    for (final label in const ['Чат', 'Занятия', 'Абонемент', 'Профиль']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('Администрация'), findsOneWidget);
    expect(find.text('Клиенты'), findsNothing);
    expect(find.text('Служебная заметка'), findsNothing);
    expect(find.text('Финансы всей школы'), findsNothing);

    await tester.tap(find.text('Занятия').last);
    await _pumpFor(tester);
    expect(find.textContaining('Мария Петрова'), findsOneWidget);
    expect(find.textContaining('Главный филиал'), findsOneWidget);

    await tester.tap(find.text('История'));
    await _pumpFor(tester);
    expect(find.textContaining('Иван Соколов'), findsOneWidget);

    await tester.tap(find.text('Задания'));
    await _pumpFor(tester);
    expect(find.text('Гамма до мажор'), findsOneWidget);
    expect(find.text('Назначено'), findsOneWidget);

    await tester.tap(find.text('Абонемент').last);
    await _pumpFor(tester);
    expect(find.text('ВОКАЛ — 8 ЧАСОВ'), findsOneWidget);
    expect(find.byKey(const Key('subscription-paid')), findsOneWidget);
    expect(find.byKey(const Key('subscription-debt')), findsOneWidget);
    expect(find.byKey(const Key('subscription-pending')), findsOneWidget);
    await captureEvidence(tester, 'client-android-persona-subscription');

    await tester.tap(find.text('Оплаты'));
    await _pumpFor(tester);
    expect(find.textContaining('5 000'), findsOneWidget);
    expect(find.textContaining('Наличные'), findsOneWidget);

    await tester.tap(find.text('Профиль').last);
    await _pumpFor(tester);
    expect(find.text('Алёна'), findsWidgets);
    expect(find.text('Клиент'), findsOneWidget);
    await captureEvidence(tester, 'client-android-persona-profile');

    expect(
      api.getPaths.where((path) => path.startsWith('/crm/students/')),
      isEmpty,
      reason: 'Client must use only actor-scoped own endpoints',
    );
    for (final forbidden in const [
      '/crm/payments',
      '/crm/expenses',
      '/analytics/v4/school-finance',
      '/crm/subscription-packages',
    ]) {
      expect(api.getPaths, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(
      api.getPaths.any(
        (path) =>
            path.contains('/internal-note') ||
            path.contains('/operational-history'),
      ),
      isFalse,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('UAT-141 Teacher completes the assigned-only mobile tour', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _PersonaApi(role: 'teacher');

    await tester.pumpWidget(_teacherApp(api));
    await _pumpFor(tester);

    for (final label in const ['Чат', 'Расписание', 'Ученики']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    for (final hidden in const [
      'Клиенты',
      'Задачи',
      'Аналитика',
      'Настройки',
      'Финансы',
    ]) {
      expect(find.text(hidden), findsNothing, reason: hidden);
    }

    await tester.tap(find.text('Расписание').first);
    await _pumpFor(tester);
    expect(find.byType(TeacherScheduleWidget), findsOneWidget);
    expect(find.byKey(const ValueKey('teacher-calendar-grid')), findsOneWidget);
    expect(find.text('Создать занятие'), findsNothing);
    await captureEvidence(tester, 'teacher-android-persona-schedule');

    await tester.tap(find.text('Ученики').first);
    await _pumpFor(tester);
    expect(find.byType(TeacherStudentsWidget), findsOneWidget);
    expect(find.text('Анна Ученица'), findsOneWidget);
    await captureEvidence(tester, 'teacher-android-persona-students');

    expect(api.getPaths, contains('/crm/teachers'));
    expect(api.getPaths, contains('/crm/students/search'));
    expect(api.getPaths.any((path) => path == '/crm/schedule/matrix'), isTrue);
    expect(
      api.getPaths.any(
        (path) =>
            path.contains('/commerce') ||
            path.contains('/contacts') ||
            path.contains('/internal-note'),
      ),
      isFalse,
    );
    expect(
      api.mutations.where((call) => call.path != '/crm/sections/seen'),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('UAT-142 Admin completes the front-desk desktop tour', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _PersonaApi(role: 'admin');

    await tester.pumpWidget(_adminApp(api));
    await _pumpFor(tester);

    for (final label in const ['Чат', 'Расписание', 'Клиенты', 'Задачи']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    for (final hidden in const ['Обзор', 'Аналитика', 'Настройки', 'Финансы']) {
      expect(find.text(hidden), findsNothing, reason: hidden);
    }
    await _openDesktopSection<ScheduleWidget>(tester, 'Расписание');
    await _openDesktopSection<ClientsWidget>(tester, 'Клиенты');
    await _openDesktopSection<SharedTasksPanel>(tester, 'Задачи');
    final scope = tester.widget<DropdownButton<String>>(
      find.byKey(const Key('shared-task-scope-filter')),
    );
    expect(scope.value, 'mine');
    expect(find.text('Сегодня'), findsWidgets);
    await captureEvidence(tester, 'admin-windows-persona-tasks');

    expect(api.getPaths, isNot(contains('/crm/dashboard/manager')));
    expect(api.getPaths, isNot(contains('/analytics/v4/school-finance')));
    expect(api.getPaths, isNot(contains('/crm/expenses')));
    expect(
      api.mutations.where((call) => call.path != '/crm/sections/seen'),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('UAT-143 Manager completes the scoped desktop functional tour', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _PersonaApi(role: 'manager');

    await tester.pumpWidget(_managerApp(api));
    await _pumpFor(tester);

    for (final label in const [
      'Чат',
      'Обзор',
      'Расписание',
      'Клиенты',
      'Задачи',
      'Аналитика',
      'Настройки',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('Финансы'), findsNothing);

    await _openDesktopSection<ManagerOverviewWidget>(tester, 'Обзор');
    expect(find.text('Выручка'), findsNothing);
    await _openDesktopSection<ScheduleWidget>(tester, 'Расписание');
    await _openDesktopSection<ClientsWidget>(tester, 'Клиенты');
    expect(find.text('Лиды'), findsWidgets);
    expect(find.text('Ученики'), findsWidgets);
    await _openDesktopSection<SharedTasksPanel>(tester, 'Задачи');
    await _openDesktopSection<ReportsWidget>(tester, 'Аналитика');
    expect(find.text('Финансы XLSX'), findsNothing);
    await captureEvidence(tester, 'manager-windows-persona-analytics');

    await _openDesktopSection<SystemSettingsWorkspace>(tester, 'Настройки');
    expect(find.text('Организация'), findsWidgets);
    expect(find.text('Продажи и оплаты'), findsOneWidget);
    await tester.tap(find.text('Продажи и оплаты'));
    await _pumpFor(tester);
    expect(find.text('Каталог абонементов'), findsOneWidget);
    expect(find.text('Новый абонемент'), findsNothing);
    await captureEvidence(tester, 'manager-windows-persona-settings');

    expect(api.getPaths, isNot(contains('/analytics/v4/school-finance')));
    expect(api.getPaths, isNot(contains('/crm/payments')));
    expect(api.getPaths, isNot(contains('/crm/expenses')));
    expect(
      api.mutations.any(
        (call) =>
            call.path.startsWith('/crm/subscription-packages') ||
            call.path.startsWith('/access/users'),
      ),
      isFalse,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('UAT-144 Director completes the privileged desktop tour', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _PersonaApi(role: 'director');

    await tester.pumpWidget(_directorApp(api));
    await _pumpFor(tester);

    for (final label in const [
      'Чат',
      'Обзор',
      'Расписание',
      'Клиенты',
      'Задачи',
      'Аналитика',
      'Настройки',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    await _openDesktopSection<ManagerOverviewWidget>(tester, 'Обзор');
    await _openDesktopSection<ScheduleWidget>(tester, 'Расписание');
    await _openDesktopSection<ClientsWidget>(tester, 'Клиенты');
    await _openDesktopSection<SharedTasksPanel>(tester, 'Задачи');
    await _openDesktopSection<ReportsWidget>(tester, 'Аналитика');
    expect(find.text('Финансы XLSX'), findsOneWidget);
    await captureEvidence(tester, 'director-windows-persona-analytics');

    await _openDesktopSection<SystemSettingsWorkspace>(tester, 'Настройки');
    expect(find.text('Пользователи и доступы'), findsWidgets);
    expect(find.text('Продажи и оплаты'), findsOneWidget);
    await tester.tap(find.text('Продажи и оплаты'));
    await _pumpFor(tester);
    expect(find.text('Каталог абонементов'), findsOneWidget);
    expect(find.text('Новый абонемент'), findsOneWidget);
    await captureEvidence(tester, 'director-windows-persona-settings');

    expect(api.getPaths, contains('/analytics/v4/school-finance'));
    expect(api.getPaths, contains('/crm/subscription-packages'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

Future<void> _openDesktopSection<T extends Widget>(
  WidgetTester tester,
  String label,
) async {
  await tester.tap(find.text(label).first);
  await _pumpFor(tester);
  expect(find.byType(T), findsOneWidget, reason: label);
  expect(tester.takeException(), isNull, reason: label);
}

Future<void> _pumpFor(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));
}

Widget _clientApp(_PersonaApi api) => ProviderScope(
  overrides: [magicApiClientProvider.overrideWithValue(api)],
  child: RepaintBoundary(
    key: evidenceRootKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const ClientDashboardScreen(),
    ),
  ),
);

const _teacherSnapshot = CapabilitySnapshot(
  accountId: 'teacher-persona',
  role: 'teacher',
  accessVersion: 1,
  capabilities: {
    'crm.client.read.basic',
    'crm.comment.read.shared',
    'schedule.lesson.read.assigned',
  },
  scopes: {'client': 'assigned', 'schedule': 'assigned'},
);

Widget _teacherApp(_PersonaApi api) => ProviderScope(
  overrides: [
    magicApiClientProvider.overrideWithValue(api),
    capabilitySnapshotProvider.overrideWith((ref) async => _teacherSnapshot),
    accountWorkspaceStoreProvider.overrideWithValue(
      AccountWorkspaceStore(InMemoryWorkspaceKeyValueStore()),
    ),
  ],
  child: RepaintBoundary(
    key: evidenceRootKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const StaffWorkspaceScreen(),
    ),
  ),
);

const _adminSnapshot = CapabilitySnapshot(
  accountId: 'admin-persona',
  role: 'admin',
  accessVersion: 1,
  capabilities: {
    'schedule.lesson.read.assigned',
    'schedule.lesson.write',
    'crm.client.read.basic',
    'crm.client.write',
    'commerce.client_finance.read',
    'commerce.client_finance.write',
    'commerce.package.read',
    'commerce.subscription.issue',
    'workflow.task.read',
  },
  scopes: {'branchIds': _branchId},
);

Widget _adminApp(_PersonaApi api) => ProviderScope(
  overrides: [
    magicApiClientProvider.overrideWithValue(api),
    capabilitySnapshotProvider.overrideWith((ref) async => _adminSnapshot),
    accountWorkspaceStoreProvider.overrideWithValue(
      AccountWorkspaceStore(InMemoryWorkspaceKeyValueStore()),
    ),
  ],
  child: RepaintBoundary(
    key: evidenceRootKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const StaffWorkspaceScreen(),
    ),
  ),
);

const _managerSnapshot = CapabilitySnapshot(
  accountId: 'manager-persona',
  role: 'manager',
  accessVersion: 1,
  capabilities: {
    'report.status.read',
    'schedule.lesson.read.assigned',
    'schedule.lesson.write',
    'crm.client.read.basic',
    'crm.client.write',
    'crm.client_finance.read',
    'crm.client_finance.write',
    'workflow.task.read',
    'workflow.task.write',
    'config.crm.read',
    'config.crm.edit',
    'commerce.package.read',
    'commerce.teacher_payroll.read',
    'commerce.teacher_payroll.write',
  },
  scopes: {'branchIds': _branchId},
);

Widget _managerApp(_PersonaApi api) => ProviderScope(
  overrides: [
    magicApiClientProvider.overrideWithValue(api),
    capabilitySnapshotProvider.overrideWith((ref) async => _managerSnapshot),
    accountWorkspaceStoreProvider.overrideWithValue(
      AccountWorkspaceStore(InMemoryWorkspaceKeyValueStore()),
    ),
  ],
  child: RepaintBoundary(
    key: evidenceRootKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const StaffWorkspaceScreen(),
    ),
  ),
);

const _directorSnapshot = CapabilitySnapshot(
  accountId: 'director-persona',
  role: 'director',
  accessVersion: 1,
  capabilities: {
    'access.user.role.assign',
    'access.user.override.manage',
    'crm.client.read.basic',
    'crm.client.read.contacts',
    'crm.client.write',
    'schedule.lesson.read.assigned',
    'schedule.lesson.write',
    'commerce.client_finance.read',
    'commerce.client_finance.write',
    'commerce.school_finance.read',
    'commerce.package.read',
    'commerce.package.manage',
    'commerce.subscription.issue',
    'workflow.task.read',
    'workflow.task.write',
    'report.status.read',
    'report.export.xlsx',
    'system.settings.manage',
    'config.crm.read',
    'config.crm.edit',
    'config.crm.publish',
  },
  scopes: {'client': 'allBranches', 'schedule': 'allBranches'},
);

Widget _directorApp(_PersonaApi api) => ProviderScope(
  overrides: [
    magicApiClientProvider.overrideWithValue(api),
    capabilitySnapshotProvider.overrideWith((ref) async => _directorSnapshot),
    accountWorkspaceStoreProvider.overrideWithValue(
      AccountWorkspaceStore(InMemoryWorkspaceKeyValueStore()),
    ),
  ],
  child: RepaintBoundary(
    key: evidenceRootKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const StaffWorkspaceScreen(),
    ),
  ),
);

typedef _MutationCall = ({String method, String path, Object? data});

class _PersonaApi extends MagicApiClient {
  _PersonaApi({required this.role})
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final String role;
  final List<String> getPaths = [];
  final List<_MutationCall> mutations = [];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    getPaths.add(path);
    if (path == '/profile/me') return _profile() as T;
    if (path == '/messenger/chats') {
      return <String, dynamic>{
            'items': [
              {
                'id': 'administration-chat',
                'type': 'administration',
                'rawType': 'administration',
                'unreadCount': 1,
              },
            ],
          }
          as T;
    }
    if (path == '/messenger/channels') {
      return <String, dynamic>{'items': <dynamic>[]} as T;
    }
    if (path.endsWith('/messages') || path.endsWith('/posts')) {
      return <String, dynamic>{'items': <dynamic>[]} as T;
    }
    if (path == '/settings/admin-chat-avatar') {
      return <String, dynamic>{'value': null} as T;
    }
    if (path == '/crm/sections/unseen') return <String, dynamic>{} as T;
    if (path == '/crm/me') {
      return <String, dynamic>{
            'students': [
              {
                'id': _studentId,
                'firstName': 'Алёна',
                'lastName': 'Смирнова',
                'branchId': _branchId,
                'branchName': 'Главный филиал',
                'customData': <String, dynamic>{},
              },
            ],
          }
          as T;
    }
    if (path == '/crm/me/commerce') return _clientCommerce() as T;
    if (path == '/crm/teachers') {
      return <String, dynamic>{
            'items': [
              {
                'id': 'teacher-1',
                'profileUserId': 'teacher-persona',
                'firstName': 'Мария',
                'lastName': 'Педагог',
                'status': 'active',
              },
            ],
          }
          as T;
    }
    if (path == '/crm/students/search') {
      return <String, dynamic>{
            'items': [
              {
                'id': _studentId,
                'firstName': 'Анна',
                'lastName': 'Ученица',
                'status': 'active',
                'branchId': _branchId,
                'branchName': 'Главный филиал',
                'lessonsCount': 4,
                'customData': <String, dynamic>{},
              },
            ],
            'totalCount': 1,
            'nextCursor': null,
          }
          as T;
    }
    if (path == '/crm/lessons') {
      final history = queryParameters?.containsKey('to') == true;
      return <String, dynamic>{
            'items': [
              {
                'id': history ? 'lesson-history' : 'lesson-upcoming',
                'studentId': _studentId,
                'teacherId': history ? 'teacher-history' : 'teacher-upcoming',
                'teacherName': history ? 'Иван Соколов' : 'Мария Петрова',
                'branchId': _branchId,
                'branchName': 'Главный филиал',
                'roomId': 'room-1',
                'roomName': 'Аудитория 1',
                'scheduledAt': history
                    ? '2026-08-01T09:00:00.000Z'
                    : '2026-08-20T09:00:00.000Z',
                'durationMinutes': 60,
                'status': history ? 'completed' : 'scheduled',
                'isTrial': false,
              },
            ],
          }
          as T;
    }
    if (path == '/crm/homeworks') {
      return <String, dynamic>{
            'items': [
              {
                'id': 'homework-1',
                'title': 'Гамма до мажор',
                'description': 'Сыграть ровно под метроном',
                'status': 'assigned',
                'dueAt': '2026-08-25T18:00:00.000Z',
                'attachments': <dynamic>[],
              },
            ],
          }
          as T;
    }
    if (path == '/crm/branches') {
      return <String, dynamic>{
            'items': [
              {'id': _branchId, 'name': 'Главный филиал', 'active': true},
            ],
          }
          as T;
    }
    if (path == '/crm/rooms') {
      return <String, dynamic>{
            'items': [
              {
                'id': 'room-1',
                'branchId': _branchId,
                'name': 'Аудитория 1',
                'active': true,
              },
            ],
          }
          as T;
    }
    if (path == '/crm/schedule/matrix') {
      return <String, dynamic>{
            'items': <dynamic>[],
            'groups': <dynamic>[],
            'conflicts': <dynamic>[],
          }
          as T;
    }
    if (path == '/crm/dashboard/manager') {
      return <String, dynamic>{
            'kpis': <String, dynamic>{
              'activeStudents': 1,
              'newLeads': 0,
              'lessons': 1,
              'revenue': null,
              'expectedPayments': null,
            },
            'sources': <String, dynamic>{},
          }
          as T;
    }
    if (path == '/crm/shared-tasks') {
      return <String, dynamic>{
            'items': <dynamic>[],
            'counters': <String, dynamic>{'open': 0, 'overdue': 0},
          }
          as T;
    }
    if (path == '/crm/shared-tasks/calendar') {
      return <String, dynamic>{'items': <dynamic>[]} as T;
    }
    if (path == '/crm/leads/board') {
      return <String, dynamic>{
            'columns': <dynamic>[],
            'totalCount': 0,
            'nextCursor': null,
          }
          as T;
    }
    if (path == '/crm/students/board') {
      return <String, dynamic>{
            'columns': <dynamic>[],
            'totalCount': 0,
            'nextCursor': null,
          }
          as T;
    }
    if (path == '/analytics/v4/client-status/summary') {
      return <String, dynamic>{
            'rows': <dynamic>[],
            'summary': <String, dynamic>{},
          }
          as T;
    }
    if (path == '/analytics/v4/lesson-success') {
      return <String, dynamic>{'rows': <dynamic>[]} as T;
    }
    if (path == '/analytics/v4/school-finance') {
      return <String, dynamic>{
            'rows': <dynamic>[],
            'summary': <String, dynamic>{
              'revenue': 0,
              'expenses': 0,
              'profit': 0,
            },
          }
          as T;
    }
    if (path == '/crm/subscription-packages') {
      return <String, dynamic>{'items': <dynamic>[]} as T;
    }
    return <String, dynamic>{
          'items': <dynamic>[],
          'rows': <dynamic>[],
          'summary': <String, dynamic>{},
          'counters': <String, dynamic>{'open': 0, 'overdue': 0},
        }
        as T;
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    mutations.add((method: 'POST', path: path, data: data));
    return <String, dynamic>{'ok': true} as T;
  }

  @override
  Future<T> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    mutations.add((method: 'PUT', path: path, data: data));
    return <String, dynamic>{'ok': true} as T;
  }

  @override
  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    mutations.add((method: 'PATCH', path: path, data: data));
    return path == '/profile/me'
        ? _profile() as T
        : <String, dynamic>{'ok': true} as T;
  }

  Map<String, dynamic> _profile() => {
    'userId': '$role-persona',
    'email': '$role@magic.test',
    'role': role,
    'firstName': role == 'client' ? 'Алёна' : 'Мария',
    'lastName': role == 'client' ? 'Смирнова' : 'Управляющая',
    'phone': '+79991234567',
    'dob': '2000-01-02',
  };
}

Map<String, dynamic> _clientCommerce() => {
  'projection': 'client_self',
  'students': [
    {
      'studentId': _studentId,
      'accounts': [
        {
          'currencyCode': 'RUB',
          'actualPaymentsMinor': '500000',
          'adjustmentsMinor': '0',
          'obligationDebitsMinor': '640000',
          'obligationCreditsMinor': '0',
          'writeOffsMinor': '160000',
          'balanceMinor': '-140000',
          'debtMinor': '140000',
          'pendingMinor': '70000',
          'remainingObligationMinor': '140000',
        },
      ],
      'subscriptions': [
        {
          'id': 'subscription-1',
          'status': 'active',
          'startsAt': '2026-08-01T00:00:00.000Z',
          'expiresAt': '2027-08-01T00:00:00.000Z',
          'units': {
            'total': '8',
            'used': '2',
            'reserved': '1',
            'paid': '5',
            'available': '3',
            'remaining': '6',
          },
          'financial': {
            'actualPaidMinor': '500000',
            'obligationMinor': '640000',
            'debtMinor': '140000',
            'pendingMinor': '70000',
            'remainingObligationMinor': '140000',
            'overpaymentMinor': '0',
            'nextPaymentAt': '2026-09-01T00:00:00.000Z',
          },
          'terms': {
            'displayName': 'Вокал — 8 часов',
            'validityDays': 365,
            'basePriceMinor': '640000',
            'finalPriceMinor': '640000',
            'currencyCode': 'RUB',
            'discount': {'type': 'none'},
            'surcharge': {'type': 'none'},
          },
          'installments': <dynamic>[],
        },
      ],
      'movements': [
        {
          'id': 'payment-1',
          'kind': 'payment',
          'direction': 'credit',
          'amountMinor': '500000',
          'currencyCode': 'RUB',
          'occurredAt': '2026-08-02T10:00:00.000Z',
          'method': 'Наличные',
          'comment': 'Первый платёж',
          'factType': null,
          'chargeType': null,
        },
      ],
      'technicalHistory': <dynamic>[],
      'lessonBalance': {
        'activeSubscriptionCount': 1,
        'total': '8',
        'used': '2',
        'reserved': '1',
        'paid': '5',
        'available': '3',
        'debts': [
          {'currencyCode': 'RUB', 'amountMinor': '140000'},
        ],
        'nextPaymentAt': '2026-09-01T00:00:00.000Z',
        'expiresAt': '2027-08-01T00:00:00.000Z',
      },
    },
  ],
};
