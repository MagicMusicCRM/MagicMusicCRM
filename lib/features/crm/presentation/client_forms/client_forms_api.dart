import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';

final clientFormsApiProvider = Provider<ClientFormsApi>((ref) {
  return ClientFormsApi(ref.watch(magicApiClientProvider));
});

class ClientFormsApi {
  const ClientFormsApi(this._api);

  final MagicApiClient _api;

  Future<List<Map<String, dynamic>>> listSources({
    bool includeArchived = false,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/client-config/sources',
      queryParameters: {'includeArchived': includeArchived},
    );
    return _items(response);
  }

  Future<List<Map<String, dynamic>>> listFields({
    required String entityType,
    bool includeArchived = false,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/client-config/fields',
      queryParameters: {
        'entityType': entityType,
        'includeArchived': includeArchived,
      },
    );
    return _items(response);
  }

  Future<List<Map<String, dynamic>>> listBranches() async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/branches',
      queryParameters: const {'limit': 100},
    );
    return _items(response);
  }

  Future<Map<String, dynamic>> getConfigurationDraft({String? branchId}) {
    return _api.get<Map<String, dynamic>>(
      '/crm/configuration/draft',
      queryParameters: {'branchId': ?branchId},
    );
  }

  Future<Map<String, dynamic>> saveConfigurationDraft({
    String? branchId,
    required int baseVersion,
    required Map<String, dynamic> snapshot,
  }) {
    return _api.put<Map<String, dynamic>>(
      '/crm/configuration/draft',
      data: {
        'branchId': ?branchId,
        'baseVersion': baseVersion,
        'snapshot': snapshot,
      },
    );
  }

  Future<Map<String, dynamic>> previewConfiguration({
    String? branchId,
    required int baseVersion,
    required Map<String, dynamic> snapshot,
  }) {
    return _api.post<Map<String, dynamic>>(
      '/crm/configuration/preview',
      data: {
        'branchId': ?branchId,
        'baseVersion': baseVersion,
        'snapshot': snapshot,
      },
    );
  }

  Future<Map<String, dynamic>> publishConfiguration({
    String? branchId,
    required int baseVersion,
    required String reason,
    required Map<String, dynamic> snapshot,
  }) {
    return _api.post<Map<String, dynamic>>(
      '/crm/configuration/publish',
      data: {
        'branchId': ?branchId,
        'baseVersion': baseVersion,
        'reason': reason.trim(),
        'snapshot': snapshot,
      },
    );
  }

  Future<List<Map<String, dynamic>>> listConfigurationRevisions({
    String? branchId,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/configuration/revisions',
      queryParameters: {'branchId': ?branchId},
    );
    return _items(response);
  }

  Future<Map<String, dynamic>> rollbackConfiguration({
    String? branchId,
    required int expectedVersion,
    required int targetVersion,
    required String reason,
  }) {
    return _api.post<Map<String, dynamic>>(
      '/crm/configuration/rollback',
      data: {
        'branchId': ?branchId,
        'expectedVersion': expectedVersion,
        'targetVersion': targetVersion,
        'reason': reason.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> createLead({
    required String firstName,
    required String lastName,
    required String phone,
    required String sourceId,
    required String branchId,
    required String status,
    required List<Map<String, dynamic>> customFields,
  }) {
    return _api.post<Map<String, dynamic>>(
      '/crm/leads',
      data: {
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'phone': phone.trim(),
        'sourceId': sourceId,
        'branchId': branchId,
        'status': status.trim(),
        'customFields': customFields,
      },
    );
  }

  Future<Map<String, dynamic>> createStudent({
    required String firstName,
    required String lastName,
    required String phone,
    required String branchId,
    required String status,
    required String sourceId,
    required List<Map<String, dynamic>> customFields,
  }) {
    return _api.post<Map<String, dynamic>>(
      '/crm/students',
      data: {
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'phone': phone.trim(),
        'branchId': branchId,
        'status': status.trim(),
        'sourceId': sourceId,
        'customFields': customFields,
      },
    );
  }

  Future<Map<String, dynamic>> createSource({
    required String canonicalName,
    required String displayName,
  }) {
    return _api.post<Map<String, dynamic>>(
      '/crm/client-config/sources',
      data: {
        'canonicalName': canonicalName.trim(),
        'displayName': displayName.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> updateSource(
    String id, {
    required int expectedVersion,
    String? canonicalName,
    String? displayName,
    bool? isActive,
  }) {
    return _api.patch<Map<String, dynamic>>(
      '/crm/client-config/sources/$id',
      data: {
        'expectedVersion': expectedVersion,
        'canonicalName': ?canonicalName?.trim(),
        'displayName': ?displayName?.trim(),
        'isActive': ?isActive,
      },
    );
  }

  Future<Map<String, dynamic>> archiveSource(
    String id, {
    required int expectedVersion,
  }) {
    return _api.delete<Map<String, dynamic>>(
      '/crm/client-config/sources/$id',
      queryParameters: {'expectedVersion': expectedVersion},
    );
  }

  Future<Map<String, dynamic>> createField({
    required String entityType,
    required String key,
    required String label,
    required String valueType,
    required bool required,
    required List<String> options,
  }) {
    return _api.post<Map<String, dynamic>>(
      '/crm/client-config/fields',
      data: {
        'entityType': entityType,
        'key': key.trim(),
        'label': label.trim(),
        'valueType': valueType,
        'required': required,
        if (valueType == 'select') 'options': options,
      },
    );
  }

  Future<Map<String, dynamic>> updateField(
    String id, {
    required int expectedVersion,
    String? label,
    String? valueType,
    bool? required,
    bool? isActive,
    List<String>? options,
  }) {
    return _api.patch<Map<String, dynamic>>(
      '/crm/client-config/fields/$id',
      data: {
        'expectedVersion': expectedVersion,
        'label': ?label?.trim(),
        'valueType': ?valueType,
        'required': ?required,
        'isActive': ?isActive,
        'options': ?options,
      },
    );
  }

  Future<Map<String, dynamic>> archiveField(
    String id, {
    required int expectedVersion,
  }) {
    return _api.delete<Map<String, dynamic>>(
      '/crm/client-config/fields/$id',
      queryParameters: {'expectedVersion': expectedVersion},
    );
  }

  static List<Map<String, dynamic>> _items(Map<String, dynamic> response) {
    final raw = response['items'];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList(growable: false);
  }
}
