import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/magic_settings_service.dart';

import 'teacher_employment_reference_gateway.dart';

class MagicTeacherEmploymentReferenceGateway
    implements TeacherEmploymentReferenceGateway {
  final MagicCrmService _crm;
  final MagicSettingsService _settings;
  Future<List<CrmCustomFieldDefinition>>? _customFields;

  MagicTeacherEmploymentReferenceGateway({
    required MagicCrmService crm,
    required MagicSettingsService settings,
  }) : _crm = crm,
       _settings = settings;

  @override
  Future<List<TeacherEmploymentReferenceOption>> loadBranches() async {
    final rows = await _crm.listBranches(limit: 100);
    return List.unmodifiable(
      rows.map(TeacherEmploymentReferenceOption.fromRow),
    );
  }

  @override
  Future<List<TeacherEmploymentReferenceOption>> loadDisciplines() async {
    final rows = await _crm.listDisciplines();
    return List.unmodifiable(
      rows.map(TeacherEmploymentReferenceOption.fromRow),
    );
  }

  @override
  Future<List<String>> loadTeacherCustomOptions(String key) async {
    final fields = await (_customFields ??= _settings.getCrmCustomFields());
    CrmCustomFieldDefinition? definition;
    for (final field in fields) {
      if (field.entity == 'teachers' && field.key == key) {
        definition = field;
        break;
      }
    }
    return List.unmodifiable(definition?.options ?? const <String>[]);
  }
}
