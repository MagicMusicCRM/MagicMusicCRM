import 'package:magic_music_crm/core/api/magic_api_client.dart';

abstract interface class SharedTaskEditorGateway {
  Future<Map<String, dynamic>> previewAudience(
    List<Map<String, dynamic>> audiences,
  );

  Future<Map<String, dynamic>> create(
    Map<String, dynamic> data,
    MagicMutationIdentity identity,
  );

  Future<Map<String, dynamic>> update(
    String taskId,
    Map<String, dynamic> data,
    MagicMutationIdentity identity,
  );
}
