import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_data_source.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_models.dart';

class RecordingSharedTasksDataSource extends SharedTasksDataSource {
  final requests = <_ListRequest>[];
  List<Map<String, dynamic>> items = const [];

  @override
  Future<Map<String, dynamic>> list({
    String? state,
    String? taskId,
    String? linkedEntityType,
    String? linkedEntityId,
  }) async {
    requests.add(
      _ListRequest(
        state: state,
        taskId: taskId,
        linkedEntityType: linkedEntityType,
        linkedEntityId: linkedEntityId,
      ),
    );
    return {'items': items};
  }

  @override
  Future<List<Map<String, dynamic>>> history(String taskId) async => [];

  @override
  Future<Map<String, dynamic>> previewAudience(
    List<Map<String, dynamic>> audiences,
  ) async => {'count': 0, 'recipients': []};

  @override
  Future<Map<String, dynamic>> create(
    Map<String, dynamic> data,
    MagicMutationIdentity identity,
  ) async => data;

  @override
  Future<Map<String, dynamic>> update(
    String taskId,
    Map<String, dynamic> data,
    MagicMutationIdentity identity,
  ) async => data;

  @override
  Future<Map<String, dynamic>> close(
    String taskId,
    int expectedVersion,
    MagicMutationIdentity identity,
  ) async => {'id': taskId};

  @override
  Future<List<SharedTaskAudienceOption>> audienceOptions() async => [];
}

class _ListRequest {
  const _ListRequest({
    required this.state,
    required this.taskId,
    required this.linkedEntityType,
    required this.linkedEntityId,
  });

  final String? state;
  final String? taskId;
  final String? linkedEntityType;
  final String? linkedEntityId;

  @override
  bool operator ==(Object other) =>
      other is _ListRequest &&
      state == other.state &&
      taskId == other.taskId &&
      linkedEntityType == other.linkedEntityType &&
      linkedEntityId == other.linkedEntityId;

  @override
  int get hashCode =>
      Object.hash(state, taskId, linkedEntityType, linkedEntityId);
}

class _RecordedApiRequest {
  const _RecordedApiRequest({
    required this.method,
    required this.path,
    this.data,
    this.queryParameters,
    this.mutationIdentity,
  });

  final String method;
  final String path;
  final Object? data;
  final Map<String, dynamic>? queryParameters;
  final MagicMutationIdentity? mutationIdentity;
}

class _RecordingApiClient extends MagicApiClient {
  _RecordingApiClient()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final requests = <_RecordedApiRequest>[];

  @override
  Future<T> request<T>(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
    ResponseType? responseType,
    MagicMutationIdentity? mutationIdentity,
  }) async {
    requests.add(
      _RecordedApiRequest(
        method: method,
        path: path,
        data: data,
        queryParameters: queryParameters,
        mutationIdentity: mutationIdentity,
      ),
    );

    if (path == '/crm/shared-tasks' && method == 'GET') {
      return {
            'items': <Map<String, dynamic>>[],
            'counters': {'open': 0, 'overdue': 0},
          }
          as T;
    }
    if (path == '/crm/shared-tasks/calendar') {
      return {
            'items': [
              {'day': '2026-08-22', 'count': 2},
            ],
          }
          as T;
    }
    if (path == '/crm/shared-tasks/task-1/history') {
      return {'items': <Map<String, dynamic>>[]} as T;
    }
    if (path == '/admin/profiles') {
      final role = queryParameters?['role'];
      final emptyName = role == 'director';
      return {
            'items': [
              {
                'id': 'profile-$role',
                'userId': 'user-$role',
                'firstName': emptyName ? null : role,
                'lastName': emptyName ? null : 'Сотрудник',
              },
            ],
          }
          as T;
    }
    if (path == '/crm/branches') {
      return {
            'items': [
              {'id': 'branch-named', 'name': 'Центральный'},
              {'id': 'branch-fallback'},
            ],
          }
          as T;
    }
    return <String, dynamic>{} as T;
  }
}

final _sourceProvider = Provider<SharedTasksDataSource>(
  (ref) => MagicCrmSharedTasksDataSource(ref),
);

String _localDay(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

_RecordedApiRequest _request(
  _RecordingApiClient api,
  String method,
  String path,
) {
  return api.requests.lastWhere(
    (request) => request.method == method && request.path == path,
  );
}

void main() {
  test(
    'inherited defaults forward list filters and aggregate calendar days',
    () async {
      final source = RecordingSharedTasksDataSource();
      final first = DateTime.utc(2026, 8, 22, 12);
      final second = DateTime.utc(2026, 8, 23, 12);
      source.items = [
        {'startAt': first.toIso8601String()},
        {'startAt': first.toIso8601String()},
        {'startAt': second.toIso8601String()},
        {'startAt': 'not-a-date'},
      ];

      await source.listFiltered(
        state: 'open',
        taskId: 'task-1',
        linkedEntityType: 'student',
        linkedEntityId: 'student-1',
        q: 'отчёт',
        priority: 'high',
        scope: 'mine',
        from: '2026-08-22',
        to: '2026-08-23',
      );
      final calendar = await source.calendar(
        from: '2026-08-22',
        to: '2026-08-23',
        state: 'closed',
        q: 'архив',
        priority: 'low',
        scope: 'all',
        linkedEntityType: 'lead',
        linkedEntityId: 'lead-1',
      );

      expect(source.requests, [
        const _ListRequest(
          state: 'open',
          taskId: 'task-1',
          linkedEntityType: 'student',
          linkedEntityId: 'student-1',
        ),
        const _ListRequest(
          state: 'closed',
          taskId: null,
          linkedEntityType: 'lead',
          linkedEntityId: 'lead-1',
        ),
      ]);
      expect(calendar, {_localDay(first): 2, _localDay(second): 1});
    },
  );

  test(
    'MagicCrm adapter forwards commands and maps directory audiences',
    () async {
      final api = _RecordingApiClient();
      final container = ProviderContainer(
        overrides: [magicApiClientProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      final source = container.read(_sourceProvider);
      final identity = MagicMutationIdentity.create('shared-task-test');
      final audiences = <Map<String, dynamic>>[
        {'type': 'branch', 'targetId': 'branch-named'},
      ];

      await source.list(
        state: 'open',
        taskId: 'task-1',
        linkedEntityType: 'student',
        linkedEntityId: 'student-1',
      );
      await source.listFiltered(
        state: 'closed',
        taskId: 'task-2',
        linkedEntityType: 'lead',
        linkedEntityId: 'lead-1',
        q: 'позвонить',
        priority: 'high',
        scope: 'mine',
        from: '2026-08-20',
        to: '2026-08-22',
      );
      await source.calendar(
        from: '2026-08-20',
        to: '2026-08-22',
        state: 'open',
        q: 'позвонить',
        priority: 'medium',
        scope: 'all',
        linkedEntityType: 'student',
        linkedEntityId: 'student-1',
      );
      await source.history('task-1');
      await source.previewAudience(audiences);
      await source.create({'title': 'Создать'}, identity);
      await source.update('task-1', {'title': 'Обновить'}, identity);
      await source.close('task-1', 7, identity);
      final options = await source.audienceOptions();

      final taskCalls = api.requests
          .where(
            (request) =>
                request.method == 'GET' && request.path == '/crm/shared-tasks',
          )
          .toList();
      expect(taskCalls, hasLength(2));
      expect(taskCalls.first.queryParameters, {
        'limit': 2000,
        'state': 'open',
        'taskId': 'task-1',
        'linkedEntityType': 'student',
        'linkedEntityId': 'student-1',
      });
      expect(taskCalls.last.queryParameters, {
        'limit': 2000,
        'state': 'closed',
        'taskId': 'task-2',
        'linkedEntityType': 'lead',
        'linkedEntityId': 'lead-1',
        'q': 'позвонить',
        'priority': 'high',
        'scope': 'mine',
        'from': '2026-08-20',
        'to': '2026-08-22',
      });
      expect(
        _request(api, 'GET', '/crm/shared-tasks/calendar').queryParameters,
        {
          'from': '2026-08-20',
          'to': '2026-08-22',
          'state': 'open',
          'q': 'позвонить',
          'priority': 'medium',
          'scope': 'all',
          'linkedEntityType': 'student',
          'linkedEntityId': 'student-1',
        },
      );
      expect(
        _request(api, 'GET', '/crm/shared-tasks/task-1/history'),
        isNotNull,
      );
      expect(_request(api, 'POST', '/crm/shared-tasks/audience-preview').data, {
        'audiences': audiences,
      });
      expect(_request(api, 'POST', '/crm/shared-tasks').data, {
        'title': 'Создать',
      });
      expect(
        _request(api, 'POST', '/crm/shared-tasks').mutationIdentity,
        same(identity),
      );
      expect(_request(api, 'PATCH', '/crm/shared-tasks/task-1').data, {
        'title': 'Обновить',
      });
      expect(
        _request(api, 'PATCH', '/crm/shared-tasks/task-1').mutationIdentity,
        same(identity),
      );
      expect(_request(api, 'POST', '/crm/shared-tasks/task-1/close').data, {
        'expectedVersion': 7,
      });
      expect(
        _request(
          api,
          'POST',
          '/crm/shared-tasks/task-1/close',
        ).mutationIdentity,
        same(identity),
      );

      final profileCalls = api.requests
          .where((request) => request.path == '/admin/profiles')
          .toList();
      expect(profileCalls, hasLength(3));
      expect(
        profileCalls.map((request) => request.queryParameters?['role']).toSet(),
        {'admin', 'manager', 'director'},
      );
      expect(
        profileCalls.every(
          (request) => request.queryParameters?['limit'] == 100,
        ),
        isTrue,
      );
      expect(_request(api, 'GET', '/crm/branches').queryParameters, {
        'limit': 100,
      });
      expect(
        options.where((option) => option.id == 'user-director').single.label,
        'Сотрудник',
      );
      expect(
        options.where((option) => option.id == 'branch-named').single.label,
        'Центральный',
      );
      expect(
        options.where((option) => option.id == 'branch-fallback').single.label,
        'Филиал',
      );
    },
  );
}
