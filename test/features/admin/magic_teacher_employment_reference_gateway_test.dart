import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/magic_settings_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/magic_teacher_employment_reference_gateway.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_employment_reference_gateway.dart';

void main() {
  test(
    'adapter maps CRM rows and teacher key options to immutable values',
    () async {
      final api = _TeacherEmploymentReferenceApi();
      final gateway = MagicTeacherEmploymentReferenceGateway(
        crm: MagicCrmService(api),
        settings: MagicSettingsService(api),
      );

      final branches = await gateway.loadBranches();
      final disciplines = await gateway.loadDisciplines();
      final levels = await gateway.loadTeacherCustomOptions('levels');
      final categories = await gateway.loadTeacherCustomOptions('categories');

      expect(branches.single.id, 'branch-a');
      expect(branches.single.name, 'Центральный');
      expect(disciplines.single.id, 'discipline-a');
      expect(disciplines.single.lifecycleState, 'archived');
      expect(levels, ['Начальный', 'Средний']);
      expect(categories, isEmpty);
      expect(api.settingsGetCount, 1);
      expect(
        () => branches.add(
          const TeacherEmploymentReferenceOption(id: 'x', name: 'X'),
        ),
        throwsUnsupportedError,
      );
      expect(() => levels.add('Новый'), throwsUnsupportedError);
    },
  );
}

class _TeacherEmploymentReferenceApi extends MagicApiClient {
  _TeacherEmploymentReferenceApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  int settingsGetCount = 0;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/settings/crm-custom-fields') settingsGetCount++;
    final body = switch (path) {
      '/crm/branches' => {
        'items': [
          {'id': 'branch-a', 'name': 'Центральный'},
        ],
      },
      '/crm/disciplines' => {
        'items': [
          {'id': 'discipline-a', 'name': 'Вокал', 'lifecycleState': 'archived'},
        ],
      },
      '/settings/crm-custom-fields' => {
        'fields': [
          {
            'entity': 'leads',
            'key': 'levels',
            'label': 'Уровни заявок',
            'type': 'select',
            'options': ['Не брать'],
          },
          {
            'entity': 'teachers',
            'key': 'levels',
            'label': 'Уровни преподавателей',
            'type': 'select',
            'options': ['Начальный', 'Средний'],
          },
        ],
      },
      _ => throw StateError('Unexpected GET $path'),
    };
    return body as T;
  }
}
