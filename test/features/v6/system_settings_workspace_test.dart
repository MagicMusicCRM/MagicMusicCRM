import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';

class _SettingsApi extends MagicApiClient {
  _SettingsApi({
    required this.role,
    required this.capabilities,
    this.groups = const [],
    this.staff = const [],
  }) : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final String role;
  final List<String> capabilities;
  final List<Map<String, dynamic>> groups;
  final List<Map<String, dynamic>> staff;
  final mutations = <String, Object?>{};

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/access/me') {
      return <String, dynamic>{
            'accountId': '10000000-0000-4000-8000-000000000001',
            'role': role,
            'accessVersion': 1,
            'capabilities': capabilities,
            'scopes': const {'schedule': 'branch'},
          }
          as T;
    }
    if (path == '/crm/branches') {
      return <String, dynamic>{
            'items': const [
              {
                'id': '20000000-0000-4000-8000-000000000001',
                'name': 'Сокол',
                'address': 'Ленинградский проспект',
              },
            ],
          }
          as T;
    }
    if (path == '/crm/teachers') {
      return <String, dynamic>{
            'items': const [
              {
                'id': '30000000-0000-4000-8000-000000000001',
                'firstName': 'Мария',
                'lastName': 'Петрова',
              },
            ],
          }
          as T;
    }
    if (path == '/crm/staff') return <String, dynamic>{'items': staff} as T;
    if (path == '/crm/groups') return <String, dynamic>{'items': groups} as T;
    if (path == '/crm/rooms') {
      return <String, dynamic>{'items': const <Map<String, dynamic>>[]} as T;
    }
    if (path == '/crm/schedule-reference') {
      return <String, dynamic>{
            'branch': {
              'id': '20000000-0000-4000-8000-000000000001',
              'timezone': 'Europe/Moscow',
              'version': 2,
              'weekly': const [
                {'weekday': 1, 'open': '09:00', 'close': '21:00'},
              ],
              'exceptions': const <Map<String, dynamic>>[],
            },
            'teacher': {
              'id': '30000000-0000-4000-8000-000000000001',
              'version': 3,
              'assignments': const [
                {
                  'branchId': '20000000-0000-4000-8000-000000000001',
                  'activeFrom': '1970-01-01',
                },
              ],
              'availability': const [
                {
                  'kind': 'recurring',
                  'available': true,
                  'timezone': 'Europe/Moscow',
                  'weekday': 1,
                  'localStart': '10:00',
                  'localEnd': '18:00',
                  'validFrom': '2026-01-01',
                },
              ],
            },
            'teacherBranchAssigned': true,
            'branchWindows': const <Map<String, dynamic>>[],
            'teacherRules': const <Map<String, dynamic>>[],
          }
          as T;
    }
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/staff' ||
        path == '/crm/teachers' ||
        path == '/crm/groups') {
      mutations[path] = data;
      return <String, dynamic>{
            'id': '90000000-0000-4000-8000-000000000001',
            ...Map<String, dynamic>.from(data! as Map),
          }
          as T;
    }
    throw StateError('Unexpected POST $path');
  }
}

Future<void> _pump(
  WidgetTester tester,
  _SettingsApi api, {
  String? initialArea,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [magicApiClientProvider.overrideWithValue(api)],
      child: MaterialApp(
        home: Scaffold(
          body: SystemSettingsWorkspace(
            role: api.role,
            initialArea: initialArea,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('manager sees one six-area settings workspace read-only', (
    tester,
  ) async {
    await _pump(
      tester,
      _SettingsApi(
        role: 'manager',
        capabilities: const [
          'system.settings.manage',
          'schedule.lesson.read.assigned',
        ],
      ),
    );

    for (final label in const [
      'Организация',
      'Расписание',
      'CRM',
      'Продажи и оплаты',
      'Пользователи и доступы',
      'Данные и обслуживание',
    ]) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('Только просмотр назначенных филиалов'), findsOneWidget);
    expect(find.text('Новый филиал'), findsNothing);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
  });

  testWidgets('delegated edit reveals scoped organization actions', (
    tester,
  ) async {
    await _pump(
      tester,
      _SettingsApi(
        role: 'director',
        capabilities: const [
          'system.settings.manage',
          'config.crm.read',
          'config.crm.edit',
        ],
      ),
    );

    expect(find.text('Новый филиал'), findsOneWidget);
    expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
  });

  testWidgets('schedule reference uses human labels and remains read-only', (
    tester,
  ) async {
    await _pump(
      tester,
      _SettingsApi(
        role: 'manager',
        capabilities: const [
          'system.settings.manage',
          'schedule.lesson.read.assigned',
        ],
      ),
    );

    await tester.tap(find.widgetWithText(ListTile, 'Расписание'));
    await tester.pumpAndSettle();

    expect(find.text('Сокол'), findsWidgets);
    expect(find.text('Петрова Мария'), findsWidgets);
    expect(find.text('Рабочие часы филиала'), findsOneWidget);
    expect(
      find.text('Только просмотр. Редактирование выдаёт директор.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Сохранить'), findsNothing);
    final mondaySwitch = find.bySemanticsLabel('Понедельник: включено');
    expect(mondaySwitch, findsOneWidget);
  });

  testWidgets('manager creates staff from the mounted users workspace', (
    tester,
  ) async {
    final api = _SettingsApi(
      role: 'manager',
      capabilities: const ['system.settings.manage', 'crm.client.write'],
    );
    await _pump(tester, api, initialArea: 'users');

    await tester.tap(find.text('Сотрудники').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Новый сотрудник'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('create-employee-form')), findsOneWidget);
    expect(find.text('Управляющий'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Фамилия *'),
      'Иванов',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Имя *'), 'Иван');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Электронная почта *'),
      'ivan@example.test',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Добавить сотрудника'));
    await tester.pumpAndSettle();

    expect(api.mutations, contains('/crm/staff'));
  });

  testWidgets('director creates teacher from the mounted users workspace', (
    tester,
  ) async {
    final api = _SettingsApi(
      role: 'director',
      capabilities: const ['system.settings.manage', 'crm.client.write'],
    );
    await _pump(tester, api, initialArea: 'users');

    await tester.tap(find.text('Преподаватели').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Новый преподаватель'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('create-teacher-form')), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Имя *'),
      'Мария',
    );
    await tester.tap(
      find.widgetWithText(FilledButton, 'Создать преподавателя'),
    );
    await tester.pumpAndSettle();

    expect(api.mutations, contains('/crm/teachers'));
  });

  testWidgets('manager creates a group from the mounted schedule workspace', (
    tester,
  ) async {
    final api = _SettingsApi(
      role: 'manager',
      capabilities: const ['system.settings.manage', 'schedule.lesson.write'],
    );
    await _pump(tester, api, initialArea: 'schedule');

    await tester.tap(find.text('Группы').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Новая группа'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('create-group-form')), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Название группы *'),
      'Вокал 1',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Создать группу'));
    await tester.pumpAndSettle();

    expect(api.mutations, contains('/crm/groups'));
  });

  testWidgets('settings lists localized staff status and group size', (
    tester,
  ) async {
    final api = _SettingsApi(
      role: 'director',
      capabilities: const ['system.settings.manage', 'schedule.lesson.write'],
      staff: const [
        {
          'id': 'staff-1',
          'role': 'manager',
          'status': 'working',
          'firstName': 'Ольга',
          'lastName': 'Смирнова',
          'email': 'hollihop-staff-1@migration.invalid',
          'isAppAccount': false,
        },
      ],
      groups: const [
        {
          'id': 'group-1',
          'name': 'Вокал',
          'teacherName': 'Мария Петрова',
          'branchName': 'Сокол',
          'studentsCount': 7,
        },
      ],
    );
    await _pump(tester, api, initialArea: 'users');

    await tester.tap(find.text('Сотрудники').first);
    await tester.pumpAndSettle();
    expect(find.text('Работает'), findsOneWidget);
    expect(find.textContaining('@migration.invalid'), findsNothing);

    await tester.tap(find.widgetWithText(ListTile, 'Расписание'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Группы'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Поиск группы'), findsOneWidget);
    expect(find.textContaining('Учеников: 7'), findsOneWidget);
  });
}
