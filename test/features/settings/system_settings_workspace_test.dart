import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';

class SettingsTestApi extends MagicApiClient {
  SettingsTestApi({
    required this.role,
    required this.capabilities,
    this.groups = const [],
    this.staff = const [],
    this.branches = const [
      {
        'id': '20000000-0000-4000-8000-000000000001',
        'name': 'Сокол',
        'address': 'Ленинградский проспект',
      },
    ],
    this.teachers = const [
      {
        'id': '30000000-0000-4000-8000-000000000001',
        'status': 'active',
        'firstName': 'Мария',
        'lastName': 'Петрова',
        'assignedBranches': [
          {'id': '20000000-0000-4000-8000-000000000001', 'name': 'Сокол'},
        ],
      },
    ],
    this.managedCredentials = const {},
  }) : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final String role;
  final List<String> capabilities;
  final List<Map<String, dynamic>> groups;
  final List<Map<String, dynamic>> staff;
  final List<Map<String, dynamic>> branches;
  final List<Map<String, dynamic>> teachers;
  final Map<String, Map<String, dynamic>> managedCredentials;
  final mutations = <String, Object?>{};
  int branchReads = 0;

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
      branchReads++;
      return <String, dynamic>{'items': branches} as T;
    }
    if (path == '/crm/teachers') {
      return <String, dynamic>{'items': teachers} as T;
    }
    if (path ==
        '/crm/branches/20000000-0000-4000-8000-000000000001/disciplines') {
      return <String, dynamic>{
            'items': const [
              {
                'id': 'branch-discipline-1',
                'disciplineId': '40000000-0000-4000-8000-000000000001',
                'name': 'Вокал',
                'sortOrder': 0,
              },
            ],
          }
          as T;
    }
    if (path == '/crm/disciplines') {
      return <String, dynamic>{
            'items': const [
              {
                'id': '40000000-0000-4000-8000-000000000001',
                'name': 'Вокал',
                'lifecycleState': 'active',
                'version': 1,
                'activeUsage': {
                  'branchAssignments': 1,
                  'teachers': 1,
                  'students': 2,
                  'packages': 0,
                },
              },
            ],
          }
          as T;
    }
    if (path == '/crm/loss-reasons') {
      return <String, dynamic>{
            'items': const [
              {
                'id': '60000000-0000-4000-8000-000000000001',
                'name': 'Высокая цена',
                'kind': 'lost',
                'lifecycleState': 'active',
                'version': 1,
                'historicalUses': 3,
              },
            ],
          }
          as T;
    }
    if (path == '/crm/staff') return <String, dynamic>{'items': staff} as T;
    if (managedCredentials.containsKey(path)) {
      return managedCredentials[path]! as T;
    }
    if (path == '/crm/groups') return <String, dynamic>{'items': groups} as T;
    if (path == '/crm/rooms') {
      return <String, dynamic>{
            'items': const [
              {
                'id': '50000000-0000-4000-8000-000000000001',
                'branchId': '20000000-0000-4000-8000-000000000001',
                'branchName': 'Сокол',
                'name': 'Вокальный класс',
                'capacity': 8,
              },
            ],
          }
          as T;
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
              'id': queryParameters?['teacherId'],
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
    if (path ==
        '/crm/schedule-reference/branches/20000000-0000-4000-8000-000000000001/hours') {
      return <String, dynamic>{
            'id': '20000000-0000-4000-8000-000000000001',
            'timezone': 'Europe/Moscow',
            'version': 2,
            'weekly': const [
              {'weekday': 1, 'open': '09:00', 'close': '21:00'},
            ],
            'exceptions': const <Map<String, dynamic>>[],
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
    if (path.endsWith('/access')) {
      mutations[path] = data;
      final body = Map<String, dynamic>.from(data! as Map);
      return <String, dynamic>{
            'id': path.contains('/teachers/')
                ? 'legacy-teacher'
                : 'legacy-staff',
            'email': body['email'],
            'role': body['role'] ?? 'teacher',
            'appRole': body['role'] ?? 'teacher',
            'isAppAccount': true,
          }
          as T;
    }
    throw StateError('Unexpected POST $path');
  }

  @override
  Future<T> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path.contains('/crm/schedule-reference/teachers/')) {
      mutations[path] = data;
      final body = Map<String, dynamic>.from(data! as Map);
      return <String, dynamic>{
            'version': (body['expectedVersion'] as num).toInt() + 1,
          }
          as T;
    }
    throw StateError('Unexpected PUT $path');
  }

  @override
  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path.startsWith('/crm/staff/') || path.startsWith('/crm/teachers/')) {
      mutations[path] = data;
      return <String, dynamic>{
            'id': path.split('/').last,
            ...Map<String, dynamic>.from(data! as Map),
          }
          as T;
    }
    throw StateError('Unexpected PATCH $path');
  }
}

Future<void> _pump(
  WidgetTester tester,
  SettingsTestApi api, {
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

Future<void> _chooseSearchable(
  WidgetTester tester,
  Key field,
  String option,
) async {
  await tester.tap(find.byKey(field));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(Scrollbar).last,
      matching: find.text(option),
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
      SettingsTestApi(
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
      'Клиенты',
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
      SettingsTestApi(
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

  testWidgets('organization refresh replaces a stale branch catalog', (
    tester,
  ) async {
    final api = SettingsTestApi(
      role: 'director',
      capabilities: const [
        'system.settings.manage',
        'config.crm.read',
        'config.crm.edit',
      ],
      branches: [
        {
          'id': '20000000-0000-4000-8000-000000000001',
          'name': 'Старый филиал',
          'address': 'До очистки',
        },
      ],
    );
    await _pump(tester, api);

    expect(find.text('Старый филиал'), findsOneWidget);
    final readsBeforeRefresh = api.branchReads;
    api.branches.clear();
    await tester.tap(find.byKey(const ValueKey('refresh-branch-catalog')));
    await tester.pumpAndSettle();

    expect(api.branchReads, greaterThan(readsBeforeRefresh));
    expect(find.text('Старый филиал'), findsNothing);
    expect(find.text('Нет филиалов'), findsOneWidget);
  });

  testWidgets('director can manage organization reference catalogs', (
    tester,
  ) async {
    await _pump(
      tester,
      SettingsTestApi(
        role: 'director',
        capabilities: const [
          'system.settings.manage',
          'config.crm.read',
          'config.crm.edit',
        ],
      ),
    );

    await tester.tap(find.text('Справочники'));
    await tester.pumpAndSettle();

    expect(find.text('Организационные справочники'), findsOneWidget);
    expect(find.text('Дисциплины'), findsOneWidget);
    expect(find.text('Причины отказа'), findsOneWidget);
    expect(find.text('Вокал'), findsOneWidget);
    expect(find.text('Активных связей: 4'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('create-reference-button')),
      findsOneWidget,
    );

    await tester.tap(find.text('Причины отказа'));
    await tester.pumpAndSettle();
    expect(find.text('Высокая цена'), findsOneWidget);
    expect(find.text('отказ • использовано: 3'), findsOneWidget);
  });

  testWidgets(
    'branch hours and teacher schedules are separate read-only views',
    (tester) async {
      await _pump(
        tester,
        SettingsTestApi(
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
      expect(find.text('Часы работы филиалов'), findsOneWidget);
      expect(find.text('Рабочие часы филиала'), findsOneWidget);
      expect(find.text('Петрова Мария'), findsNothing);
      expect(
        find.text('Только просмотр. Редактирование выдаёт директор.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Сохранить'), findsNothing);
      final mondaySwitch = find.bySemanticsLabel('Понедельник: включено');
      expect(mondaySwitch, findsOneWidget);

      await tester.tap(find.text('Графики преподавателей'));
      await tester.pumpAndSettle();

      expect(find.text('Графики преподавателей'), findsWidgets);
      expect(find.text('Петрова Мария'), findsWidgets);
      expect(find.text('Филиалы преподавателя'), findsOneWidget);
      expect(find.text('Доступность преподавателя'), findsOneWidget);
      expect(find.text('Рабочие часы филиала'), findsNothing);
    },
  );

  testWidgets('teacher unavailability requires and displays a reason', (
    tester,
  ) async {
    await _pump(
      tester,
      SettingsTestApi(
        role: 'director',
        capabilities: const [
          'system.settings.manage',
          'schedule.lesson.read.assigned',
          'config.crm.edit',
        ],
      ),
    );

    await tester.tap(find.widgetWithText(ListTile, 'Расписание'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Графики преподавателей'));
    await tester.pumpAndSettle();
    final addInterval = find.widgetWithText(TextButton, 'Добавить');
    await tester.ensureVisible(addInterval);
    await tester.pumpAndSettle();
    await tester.tap(addInterval);
    await tester.pumpAndSettle();
    await tester.tap(find.text('${DateTime.now().day}').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Причина недоступности *'), findsOneWidget);
    final addButton = find.widgetWithText(FilledButton, 'Добавить');
    expect(tester.widget<FilledButton>(addButton).onPressed, isNull);
    await tester.enterText(
      find.widgetWithText(TextField, 'Причина недоступности *'),
      'UAT: преподаватель занят',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(addButton).onPressed, isNotNull);
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    expect(find.text('UAT: преподаватель занят'), findsOneWidget);
  });

  testWidgets(
    'director saves branch assignments and working hours for all three teachers',
    (tester) async {
      const teachers = <Map<String, dynamic>>[
        {
          'id': '30000000-0000-4000-8000-000000000001',
          'status': 'active',
          'firstName': 'Мария',
          'lastName': 'Петрова',
        },
        {
          'id': '30000000-0000-4000-8000-000000000002',
          'status': 'active',
          'firstName': 'Анна',
          'lastName': 'Соколова',
        },
        {
          'id': '30000000-0000-4000-8000-000000000003',
          'status': 'active',
          'firstName': 'Ирина',
          'lastName': 'Орлова',
        },
      ];
      final api = SettingsTestApi(
        role: 'director',
        capabilities: const [
          'system.settings.manage',
          'schedule.lesson.read.assigned',
          'config.crm.edit',
        ],
        teachers: teachers,
      );
      await _pump(tester, api, initialArea: 'schedule');
      await tester.tap(find.text('Графики преподавателей'));
      await tester.pumpAndSettle();

      for (var index = 0; index < teachers.length; index += 1) {
        final teacher = teachers[index];
        final id = teacher['id']!;
        if (index > 0) {
          final previousId = teachers[index - 1]['id']!;
          await _chooseSearchable(
            tester,
            ValueKey('settings-teacher-$previousId'),
            '${teacher['lastName']} ${teacher['firstName']}',
          );
        }

        final assignmentsCard = find
            .ancestor(
              of: find.text('Филиалы преподавателя'),
              matching: find.byType(Card),
            )
            .first;
        await tester.tap(
          find.descendant(
            of: assignmentsCard,
            matching: find.widgetWithText(FilledButton, 'Сохранить'),
          ),
        );
        await tester.pumpAndSettle();

        final availabilityCard = find
            .ancestor(
              of: find.text('Доступность преподавателя'),
              matching: find.byType(Card),
            )
            .first;
        await tester.tap(
          find.descendant(
            of: availabilityCard,
            matching: find.widgetWithText(FilledButton, 'Сохранить'),
          ),
        );
        await tester.pumpAndSettle();

        final branchesPath = '/crm/schedule-reference/teachers/$id/branches';
        final availabilityPath =
            '/crm/schedule-reference/teachers/$id/availability';
        expect(api.mutations[branchesPath], {
          'expectedVersion': 3,
          'assignments': [
            {
              'branchId': '20000000-0000-4000-8000-000000000001',
              'activeFrom': '1970-01-01',
            },
          ],
        });
        final availability =
            api.mutations[availabilityPath]! as Map<String, dynamic>;
        expect(availability['expectedVersion'], 4);
        expect(availability['rules'], contains(containsPair('weekday', 1)));
      }
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets('director creates staff with a role and multiple branches', (
    tester,
  ) async {
    final api = SettingsTestApi(
      role: 'director',
      capabilities: const ['system.settings.manage', 'crm.client.write'],
      branches: const [
        {'id': '20000000-0000-4000-8000-000000000001', 'name': 'Сокол'},
        {'id': '20000000-0000-4000-8000-000000000002', 'name': 'Спортивная'},
      ],
    );
    await _pump(tester, api, initialArea: 'users');

    await tester.tap(find.text('Сотрудники').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Новый сотрудник'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('create-employee-form')), findsOneWidget);
    expect(
      find.byKey(const Key('create-employee-access-role')),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Фамилия *'),
      'Иванов',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Имя *'), 'Иван');
    expect(
      find.widgetWithText(TextFormField, 'Электронная почта (необязательно)'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(TextFormField, 'Пароль (необязательно)'),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Электронная почта (необязательно)'),
      'staff@example.test',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Пароль (необязательно)'),
      '12345678',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Повторите пароль'),
      '12345678',
    );
    await tester.tap(find.byKey(const Key('create-employee-access-role')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Управляющий').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Сокол'));
    await tester.tap(find.widgetWithText(FilterChip, 'Спортивная'));
    await tester.tap(find.widgetWithText(FilledButton, 'Добавить сотрудника'));
    await tester.pumpAndSettle();

    expect(api.mutations, contains('/crm/staff'));
    final payload = api.mutations['/crm/staff']! as Map<String, dynamic>;
    expect(payload['password'], '12345678');
    expect(payload['accessRole'], 'manager');
    expect(payload['branchIds'], [
      '20000000-0000-4000-8000-000000000001',
      '20000000-0000-4000-8000-000000000002',
    ]);
  });

  for (final actorRole in const ['manager', 'director']) {
    testWidgets('$actorRole sees the correct staff role action in the card', (
      tester,
    ) async {
      final api = SettingsTestApi(
        role: actorRole,
        capabilities: const ['system.settings.manage', 'crm.client.write'],
        staff: const [
          {
            'id': 'staff-read-only-role',
            'role': 'admin',
            'status': 'working',
            'firstName': 'Ольга',
            'lastName': 'Смирнова',
            'email': 'staff@example.test',
            'isAppAccount': true,
            'appRole': 'admin',
            'profileUserId': '10000000-0000-4000-8000-000000000099',
            'passwordConfigured': true,
            'branches': [
              {'id': '20000000-0000-4000-8000-000000000001', 'name': 'Сокол'},
            ],
          },
        ],
      );
      await _pump(tester, api, initialArea: 'users');
      await tester.tap(find.text('Сотрудники').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Смирнова Ольга'));
      await tester.pumpAndSettle();

      expect(find.text('Роль доступа'), findsOneWidget);
      expect(
        find.text('Определяет права пользователя в приложении'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('staff-change-access-role')),
        actorRole == 'director' ? findsOneWidget : findsNothing,
      );
    });
  }

  testWidgets('director creates teacher from the mounted users workspace', (
    tester,
  ) async {
    final api = SettingsTestApi(
      role: 'director',
      capabilities: const ['system.settings.manage', 'crm.client.write'],
      branches: const [
        {'id': '20000000-0000-4000-8000-000000000001', 'name': 'Сокол'},
        {'id': '20000000-0000-4000-8000-000000000002', 'name': 'Спортивная'},
      ],
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
    expect(
      find.widgetWithText(TextFormField, 'Почта для входа (необязательно)'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(TextFormField, 'Пароль (необязательно)'),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Почта для входа (необязательно)'),
      'teacher@example.test',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Пароль (необязательно)'),
      '12345678',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Повторите пароль'),
      '12345678',
    );
    await tester.tap(find.byKey(const Key('create-teacher-access-role')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Управляющий').last);
    await tester.pumpAndSettle();
    final branchChip = find.widgetWithText(FilterChip, 'Сокол');
    await tester.ensureVisible(branchChip);
    await tester.tap(branchChip);
    await tester.tap(find.widgetWithText(FilterChip, 'Спортивная'));
    await tester.pumpAndSettle();
    final disciplineChip = find.widgetWithText(FilterChip, 'Вокал');
    await tester.ensureVisible(disciplineChip);
    await tester.tap(disciplineChip);
    await tester.pumpAndSettle();
    final rateSelector = find.byType(DropdownButtonFormField<String>).last;
    await tester.ensureVisible(rateSelector);
    await tester.tap(rateSelector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('750 ₽').last);
    await tester.pumpAndSettle();
    final createButton = find.widgetWithText(FilledButton, 'Создать');
    await tester.ensureVisible(createButton);
    await tester.tap(createButton);
    await tester.pumpAndSettle();

    expect(api.mutations, contains('/crm/teachers'));
    final payload = api.mutations['/crm/teachers']! as Map<String, dynamic>;
    expect(payload['accessRole'], 'manager');
    expect(payload['branchIds'], [
      '20000000-0000-4000-8000-000000000001',
      '20000000-0000-4000-8000-000000000002',
    ]);
    expect(payload['disciplineIds'], ['40000000-0000-4000-8000-000000000001']);
    expect(payload['rate'], 750);
  });

  testWidgets('director can change access role from the teacher card', (
    tester,
  ) async {
    final api = SettingsTestApi(
      role: 'director',
      capabilities: const ['system.settings.manage', 'crm.client.write'],
      teachers: const [
        {
          'id': '30000000-0000-4000-8000-000000000001',
          'status': 'active',
          'firstName': 'Мария',
          'lastName': 'Петрова',
          'profileUserId': '10000000-0000-4000-8000-000000000099',
          'appRole': 'teacher',
          'isAppAccount': true,
          'assignedBranches': [
            {'id': '20000000-0000-4000-8000-000000000001', 'name': 'Сокол'},
          ],
        },
      ],
    );
    await _pump(tester, api, initialArea: 'users');

    await tester.tap(find.text('Преподаватели').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Мария Петрова'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('teacher-change-access-role')), findsOneWidget);
    expect(
      find.text('Определяет права пользователя в приложении'),
      findsOneWidget,
    );
  });

  testWidgets('manager creates a group from the mounted schedule workspace', (
    tester,
  ) async {
    final api = SettingsTestApi(
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
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сокол').last);
    await tester.pumpAndSettle();
    await _chooseSearchable(
      tester,
      const ValueKey('group-teacher-field'),
      'Мария Петрова',
    );
    await _chooseSearchable(
      tester,
      const ValueKey('group-room-field'),
      'Вокальный класс',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Создать группу'));
    await tester.pumpAndSettle();

    expect(api.mutations, contains('/crm/groups'));
  });

  testWidgets('settings lists localized staff status and group size', (
    tester,
  ) async {
    final api = SettingsTestApi(
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

  testWidgets('director creates login access for a legacy staff record', (
    tester,
  ) async {
    final api = SettingsTestApi(
      role: 'director',
      capabilities: const ['system.settings.manage', 'crm.client.write'],
      staff: const [
        {
          'id': 'legacy-staff',
          'role': 'admin',
          'status': 'working',
          'firstName': 'Ольга',
          'lastName': 'Смирнова',
          'email': 'hollihop-staff-1@migration.invalid',
          'isAppAccount': false,
          'branches': [
            {'id': '20000000-0000-4000-8000-000000000001', 'name': 'Сокол'},
          ],
        },
      ],
    );
    await _pump(tester, api, initialArea: 'users');
    await tester.tap(find.text('Сотрудники').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Смирнова Ольга'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Создать доступ'));
    await tester.pumpAndSettle();

    final emailField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Почта для входа *'),
    );
    expect(emailField.controller!.text, isEmpty);
    final accessDialog = find.widgetWithText(
      AlertDialog,
      'Создать доступ: Смирнова Ольга',
    );
    expect(
      find.descendant(
        of: accessDialog,
        matching: find.byType(DropdownButtonFormField<String>),
      ),
      findsNothing,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Почта для входа *'),
      'legacy.staff@example.test',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Пароль *'),
      'password-123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Повторите новый пароль'),
      'password-123',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Создать доступ').last);
    await tester.pumpAndSettle();

    expect(api.mutations, contains('/crm/staff/legacy-staff/access'));
  });

  testWidgets('director reveals the current managed staff password', (
    tester,
  ) async {
    final api = SettingsTestApi(
      role: 'director',
      capabilities: const ['system.settings.manage', 'crm.client.write'],
      staff: const [
        {
          'id': 'staff-with-access',
          'role': 'admin',
          'status': 'working',
          'firstName': 'Ольга',
          'lastName': 'Смирнова',
          'email': 'staff@example.test',
          'isAppAccount': true,
          'passwordConfigured': true,
          'branches': [
            {'id': '20000000-0000-4000-8000-000000000001', 'name': 'Сокол'},
          ],
        },
      ],
      managedCredentials: const {
        '/crm/staff/staff-with-access/access': {
          'email': 'staff@example.test',
          'password': 'current-password-123',
          'passwordRecoverable': true,
        },
      },
    );
    await _pump(tester, api, initialArea: 'users');
    await tester.tap(find.text('Сотрудники').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Смирнова Ольга'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Данные для входа'));
    await tester.pumpAndSettle();

    expect(find.text('Актуальный пароль'), findsOneWidget);
    expect(
      find.text('Доступен только директору и администратору системы'),
      findsOneWidget,
    );
    final currentPasswordField = find.descendant(
      of: find.widgetWithText(TextFormField, 'Актуальный пароль'),
      matching: find.byType(TextField),
    );
    expect(
      tester.widget<TextField>(currentPasswordField).controller!.text,
      'current-password-123',
    );
    expect(tester.widget<TextField>(currentPasswordField).obscureText, isTrue);
  });

  testWidgets(
    'staff card without access saves profile data without credentials',
    (tester) async {
      final api = SettingsTestApi(
        role: 'director',
        capabilities: const ['system.settings.manage', 'crm.client.write'],
        staff: const [
          {
            'id': 'staff-without-access',
            'role': 'admin',
            'status': 'working',
            'firstName': 'Ольга',
            'lastName': 'Смирнова',
            'email': null,
            'isAppAccount': false,
            'branches': [
              {'id': '20000000-0000-4000-8000-000000000001', 'name': 'Сокол'},
            ],
          },
        ],
      );
      await _pump(tester, api, initialArea: 'users');
      await tester.tap(find.text('Сотрудники').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Смирнова Ольга'));
      await tester.pumpAndSettle();

      expect(
        find.text('Доступ не создан. Карточку можно сохранить без него'),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Должность'),
        'Старший администратор',
      );
      final save = find.widgetWithText(FilledButton, 'Сохранить');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      final payload = Map<String, dynamic>.from(
        api.mutations['/crm/staff/staff-without-access']! as Map,
      );
      expect(payload['position'], 'Старший администратор');
      expect(payload, isNot(contains('email')));
      expect(
        api.mutations,
        isNot(contains('/crm/staff/staff-without-access/access')),
      );
    },
  );

  testWidgets(
    'teacher card without access saves profile data without credentials',
    (tester) async {
      final api = SettingsTestApi(
        role: 'director',
        capabilities: const ['system.settings.manage', 'crm.client.write'],
        teachers: const [
          {
            'id': 'teacher-without-access',
            'status': 'active',
            'firstName': 'Мария',
            'lastName': 'Петрова',
            'email': null,
            'isAppAccount': false,
            'assignedBranches': [
              {'id': '20000000-0000-4000-8000-000000000001', 'name': 'Сокол'},
            ],
          },
        ],
      );
      await _pump(tester, api, initialArea: 'users');
      await tester.tap(find.text('Преподаватели').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Мария Петрова'));
      await tester.pumpAndSettle();

      expect(
        find.text('Доступ не создан. Карточку можно сохранить без него'),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Имя Фамилия'),
        'Марина Петрова',
      );
      final save = find.widgetWithText(FilledButton, 'Сохранить').last;
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      final payload = Map<String, dynamic>.from(
        api.mutations['/crm/teachers/teacher-without-access']! as Map,
      );
      expect(payload['firstName'], 'Марина');
      expect(payload, isNot(contains('email')));
      expect(
        api.mutations,
        isNot(contains('/crm/teachers/teacher-without-access/access')),
      );
    },
  );
}
