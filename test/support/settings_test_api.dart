import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';

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
