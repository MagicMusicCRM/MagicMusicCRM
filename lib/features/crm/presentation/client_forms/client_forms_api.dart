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
    // The canonical backend stores one field definition with lead/student
    // visibility flags, so current responses no longer carry the legacy
    // `entityType` discriminator. The caller still requests one projection at
    // a time; preserve that projection on the client boundary so card code can
    // distinguish lead and student copies while remaining compatible with an
    // older server that still returns `entityType` explicitly.
    return [
      for (final item in _items(response))
        if (item['entityType'] == null)
          {...item, 'entityType': entityType}
        else
          item,
    ];
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
        'snapshot': configurationSnapshotForWire(snapshot),
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
        'snapshot': configurationSnapshotForWire(snapshot),
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
        'snapshot': configurationSnapshotForWire(snapshot),
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
    required String key,
    required String label,
    required String valueType,
    required bool required,
    required List<String> options,
    bool visibleOnLead = true,
    bool visibleOnStudent = true,
  }) {
    return _api.post<Map<String, dynamic>>(
      '/crm/client-config/fields',
      data: {
        'key': key.trim(),
        'label': label.trim(),
        'valueType': valueType,
        'required': required,
        'visibleOnLead': visibleOnLead,
        'visibleOnStudent': visibleOnStudent,
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
    bool? visibleOnLead,
    bool? visibleOnStudent,
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
        'visibleOnLead': ?visibleOnLead,
        'visibleOnStudent': ?visibleOnStudent,
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

/// Converts the canonical one-field model to the compatibility wire shape.
///
/// Servers through migration 0132 require one `entityType` row per Lead or
/// Student card. Newer servers merge these rows back into one definition with
/// visibility flags, so the same payload is safe across a rolling upgrade.
Map<String, dynamic> configurationSnapshotForWire(
  Map<String, dynamic> snapshot,
) {
  final result = Map<String, dynamic>.from(snapshot);
  final rawFields = snapshot['fields'];
  if (rawFields is! List) return result;

  final fields = <Map<String, dynamic>>[];
  for (final rawField in rawFields.whereType<Map>()) {
    final field = Map<String, dynamic>.from(rawField);
    final visibility = field['visibility'];
    final legacyEntityType = field['entityType']?.toString();
    final visibleOnLead = visibility is Map
        ? visibility['lead'] == true
        : legacyEntityType == null || legacyEntityType == 'lead';
    final visibleOnStudent = visibility is Map
        ? visibility['student'] == true
        : legacyEntityType == null || legacyEntityType == 'student';

    void addLegacyCopy(String entityType) {
      fields.add({...field, 'entityType': entityType}..remove('visibility'));
    }

    if (visibleOnLead) addLegacyCopy('lead');
    if (visibleOnStudent) addLegacyCopy('student');
  }
  result['fields'] = fields;
  return result;
}
