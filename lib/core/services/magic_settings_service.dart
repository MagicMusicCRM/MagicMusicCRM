import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';

final magicSettingsServiceProvider = Provider<MagicSettingsService>((ref) {
  return MagicSettingsService(ref.watch(magicApiClientProvider));
});

const crmCustomFieldEntities = <String, String>{
  'students': 'Ученики',
  'leads': 'Заявки',
  'teachers': 'Преподаватели',
};

const crmCustomFieldTypes = <String, String>{
  'text': 'Текст',
  'number': 'Число',
  'date': 'Дата',
  'phone': 'Телефон',
  'email': 'Почта',
  'url': 'Ссылка',
  'select': 'Список',
  'boolean': 'Да/нет',
};

class CrmCustomFieldDefinition {
  final String? id;
  final String entity;
  final String key;
  final String label;
  final String type;
  final bool required;
  final String? hint;
  final List<String> options;
  final String width;
  final List<String> placements;

  const CrmCustomFieldDefinition({
    this.id,
    required this.entity,
    required this.key,
    required this.label,
    required this.type,
    this.required = false,
    this.hint,
    this.options = const [],
    this.width = 'full',
    this.placements = const ['edit', 'card'],
  });

  factory CrmCustomFieldDefinition.fromJson(Map<String, dynamic> json) {
    final options = json['options'];
    return CrmCustomFieldDefinition(
      id: json['id']?.toString(),
      entity: json['entity']?.toString() ?? 'students',
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      type: json['type']?.toString() ?? 'text',
      required: json['required'] == true,
      hint: json['hint']?.toString(),
      options: options is List
          ? options.map((e) => e.toString()).toList()
          : const [],
      width: json['width']?.toString() ?? 'full',
      placements: (json['placements'] as List? ?? const ['edit', 'card'])
          .map((value) => value.toString())
          .toList(growable: false),
    );
  }

  factory CrmCustomFieldDefinition.fromClientConfig(Map<String, dynamic> json) {
    final entityType = json['entityType']?.toString() ?? 'student';
    return CrmCustomFieldDefinition(
      id: json['id']?.toString(),
      entity: entityType == 'lead' ? 'leads' : 'students',
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      type: json['valueType']?.toString() ?? 'text',
      required: json['required'] == true,
      options: (json['options'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      width: json['width']?.toString() ?? 'full',
      placements: (json['placements'] as List? ?? const ['edit', 'card'])
          .map((value) => value.toString())
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'entity': entity,
      'key': key,
      'label': label,
      'type': type,
      'required': required,
      if (hint != null && hint!.trim().isNotEmpty) 'hint': hint!.trim(),
      if (type == 'select') 'options': options,
    };
  }
}

/// Service for managing global system settings.
class MagicSettingsService {
  final MagicApiClient _api;

  const MagicSettingsService(this._api);

  /// Retrieves the administration chat avatar URL.
  Future<String?> getAdminChatAvatar() async {
    try {
      final res = await _api.get<Map<String, dynamic>>(
        '/settings/admin-chat-avatar',
      );

      final value = res['value'];
      return value?.toString();
    } catch (e) {
      debugPrint('MagicSettingsService: Error getting admin avatar: $e');
      return null;
    }
  }

  /// Updates the administration chat avatar URL.
  Future<void> updateAdminChatAvatar(String? url) async {
    try {
      await _api.patch<Map<String, dynamic>>(
        '/admin/settings/admin-chat-avatar',
        data: {'url': url},
      );
    } catch (e) {
      debugPrint('MagicSettingsService: Error updating admin avatar: $e');
      rethrow;
    }
  }

  /// Retrieves CRM custom field templates.
  Future<List<CrmCustomFieldDefinition>> getCrmCustomFields() async {
    final res = await _api.get<Map<String, dynamic>>(
      '/settings/crm-custom-fields',
    );
    final fields = res['fields'];
    if (fields is! List) return const [];
    return fields
        .whereType<Map<String, dynamic>>()
        .map(CrmCustomFieldDefinition.fromJson)
        .where((field) => field.key.isNotEmpty && field.label.isNotEmpty)
        .toList();
  }

  /// Updates CRM custom field templates.
  Future<List<CrmCustomFieldDefinition>> updateCrmCustomFields(
    List<CrmCustomFieldDefinition> fields,
  ) async {
    final res = await _api.patch<Map<String, dynamic>>(
      '/admin/settings/crm-custom-fields',
      data: {'fields': fields.map((field) => field.toJson()).toList()},
    );
    final savedFields = res['fields'];
    if (savedFields is! List) return const [];
    return savedFields
        .whereType<Map<String, dynamic>>()
        .map(CrmCustomFieldDefinition.fromJson)
        .toList();
  }
}
