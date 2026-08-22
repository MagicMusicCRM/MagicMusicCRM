import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_data_source.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_models.dart';

class RecordingSharedTasksDataSource implements SharedTasksDataSource {
  String? requestedState;

  @override
  Future<Map<String, dynamic>> list({
    String? state,
    String? taskId,
    String? linkedEntityType,
    String? linkedEntityId,
  }) async {
    requestedState = state;
    return {'items': <Map<String, dynamic>>[]};
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
    return list(
      state: state,
      taskId: taskId,
      linkedEntityType: linkedEntityType,
      linkedEntityId: linkedEntityId,
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
  }) async => <String, int>{};

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

void main() {
  test('data source contract preserves state filtering', () async {
    final source = RecordingSharedTasksDataSource();

    await source.list(state: 'open');

    expect(source.requestedState, 'open');
  });
}
