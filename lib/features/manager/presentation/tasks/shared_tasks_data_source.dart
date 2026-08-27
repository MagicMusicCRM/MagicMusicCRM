import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/magic_profile_admin_service.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_task_editor_gateway.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_models.dart';

abstract class SharedTasksDataSource implements SharedTaskEditorGateway {
  Future<Map<String, dynamic>> list({
    String? state,
    String? taskId,
    String? linkedEntityType,
    String? linkedEntityId,
  });

  Future<Map<String, dynamic>> listFiltered({
    String? state,
    String? taskId,
    String? linkedEntityType,
    String? linkedEntityId,
    String? q,
    String? priority,
    String? scope,
    String? from,
    String? to,
  }) => list(
    state: state,
    taskId: taskId,
    linkedEntityType: linkedEntityType,
    linkedEntityId: linkedEntityId,
  );

  Future<Map<String, int>> calendar({
    required String from,
    required String to,
    String? state,
    String? q,
    String? priority,
    String? scope,
    String? linkedEntityType,
    String? linkedEntityId,
  }) async {
    final result = await listFiltered(
      state: state,
      q: q,
      priority: priority,
      scope: scope,
      from: from,
      to: to,
      linkedEntityType: linkedEntityType,
      linkedEntityId: linkedEntityId,
    );
    final counts = <String, int>{};
    for (final task in (result['items'] as List? ?? const [])) {
      if (task is! Map<String, dynamic>) continue;
      final start = DateTime.tryParse(task['startAt']?.toString() ?? '');
      if (start == null) continue;
      final local = start.toLocal();
      final day =
          '${local.year.toString().padLeft(4, '0')}-'
          '${local.month.toString().padLeft(2, '0')}-'
          '${local.day.toString().padLeft(2, '0')}';
      counts[day] = (counts[day] ?? 0) + 1;
    }
    return counts;
  }

  Future<List<Map<String, dynamic>>> history(String taskId);

  @override
  Future<Map<String, dynamic>> previewAudience(
    List<Map<String, dynamic>> audiences,
  );

  @override
  Future<Map<String, dynamic>> create(
    Map<String, dynamic> data,
    MagicMutationIdentity identity,
  );

  @override
  Future<Map<String, dynamic>> update(
    String taskId,
    Map<String, dynamic> data,
    MagicMutationIdentity identity,
  );

  Future<Map<String, dynamic>> close(
    String taskId,
    int expectedVersion,
    MagicMutationIdentity identity,
  );

  Future<List<SharedTaskAudienceOption>> audienceOptions();
}

class MagicCrmSharedTasksDataSource implements SharedTasksDataSource {
  MagicCrmSharedTasksDataSource(Ref ref) : _ref = ref, _widgetRef = null;

  MagicCrmSharedTasksDataSource.fromWidgetRef(WidgetRef ref)
    : _ref = null,
      _widgetRef = ref;

  final Ref? _ref;
  final WidgetRef? _widgetRef;

  MagicCrmService get _crm =>
      _ref?.read(magicCrmServiceProvider) ??
      _widgetRef!.read(magicCrmServiceProvider);

  MagicProfileAdminService get _profiles =>
      _ref?.read(magicProfileAdminServiceProvider) ??
      _widgetRef!.read(magicProfileAdminServiceProvider);

  @override
  Future<Map<String, dynamic>> list({
    String? state,
    String? taskId,
    String? linkedEntityType,
    String? linkedEntityId,
  }) {
    return _crm.listSharedTasks(
      state: state,
      taskId: taskId,
      linkedEntityType: linkedEntityType,
      linkedEntityId: linkedEntityId,
    );
  }

  @override
  Future<Map<String, dynamic>> listFiltered({
    String? state,
    String? taskId,
    String? linkedEntityType,
    String? linkedEntityId,
    String? q,
    String? priority,
    String? scope,
    String? from,
    String? to,
  }) {
    return _crm.listSharedTasks(
      state: state,
      taskId: taskId,
      linkedEntityType: linkedEntityType,
      linkedEntityId: linkedEntityId,
      q: q,
      priority: priority,
      scope: scope,
      from: from,
      to: to,
    );
  }

  @override
  Future<Map<String, int>> calendar({
    required String from,
    required String to,
    String? state,
    String? q,
    String? priority,
    String? scope,
    String? linkedEntityType,
    String? linkedEntityId,
  }) {
    return _crm.sharedTaskCalendar(
      from: from,
      to: to,
      state: state,
      q: q,
      priority: priority,
      scope: scope,
      linkedEntityType: linkedEntityType,
      linkedEntityId: linkedEntityId,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> history(String taskId) {
    return _crm.listSharedTaskHistory(taskId);
  }

  @override
  Future<Map<String, dynamic>> previewAudience(
    List<Map<String, dynamic>> audiences,
  ) {
    return _crm.previewSharedTaskAudience(audiences);
  }

  @override
  Future<Map<String, dynamic>> create(
    Map<String, dynamic> data,
    MagicMutationIdentity identity,
  ) {
    return _crm.createSharedTask(data: data, identity: identity);
  }

  @override
  Future<Map<String, dynamic>> update(
    String taskId,
    Map<String, dynamic> data,
    MagicMutationIdentity identity,
  ) {
    return _crm.updateSharedTask(
      taskId: taskId,
      data: data,
      identity: identity,
    );
  }

  @override
  Future<Map<String, dynamic>> close(
    String taskId,
    int expectedVersion,
    MagicMutationIdentity identity,
  ) {
    return _crm.closeSharedTask(
      taskId: taskId,
      expectedVersion: expectedVersion,
      identity: identity,
    );
  }

  @override
  Future<List<SharedTaskAudienceOption>> audienceOptions() async {
    const taskRoles = {'admin', 'manager', 'director'};
    final profiles = _profiles;
    final result = await Future.wait([
      ...taskRoles.map((role) => profiles.listProfiles(role: role, limit: 100)),
      _crm.listBranches(limit: 100),
    ]);
    final branches = result.removeLast();
    return [
      ...result
          .expand((rows) => rows)
          .where((row) => row['user_id'] != null)
          .map(
            (row) => SharedTaskAudienceOption(
              type: 'user',
              id: row['user_id'].toString(),
              label: _profileLabel(row),
            ),
          ),
      ...branches.map(
        (row) => SharedTaskAudienceOption(
          type: 'branch',
          id: row['id'].toString(),
          label: row['name']?.toString() ?? 'Филиал',
        ),
      ),
    ];
  }
}

String _profileLabel(Map<String, dynamic> profile) {
  final first = profile['first_name']?.toString().trim() ?? '';
  final last = profile['last_name']?.toString().trim() ?? '';
  final name = '$first $last'.trim();
  return name.isEmpty ? 'Сотрудник' : name;
}
