import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/magic_settings_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_employment_fields.dart';

void main() {
  testWidgets(
    'shared teacher fields return branches disciplines configured options and rate',
    (tester) async {
      final api = _TeacherFieldsApi();
      final key = GlobalKey<TeacherEmploymentFieldsState>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            magicCrmServiceProvider.overrideWithValue(MagicCrmService(api)),
            magicSettingsServiceProvider.overrideWithValue(
              MagicSettingsService(api),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TeacherEmploymentFields(key: key, requireRate: true),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Центральный'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Вокал'));

      await tester.tap(find.text('Выберите ставку'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('750 ₽').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Уровни'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Начальный'));
      await tester.tap(find.text('Категории'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Дети'));

      final value = key.currentState!.validateAndRead();
      await tester.pump();

      expect(value, isNotNull);
      expect(value!.branchIds, ['branch-a']);
      expect(value.disciplineIds, ['discipline-a']);
      expect(value.levels, ['Начальный']);
      expect(value.categories, ['Дети']);
      expect(value.rate, 750);
      expect(value.rateChanged, isTrue);
      expect(value.salary, isNull);
      expect(value.customDataPatch['level'], 'Начальный');
      expect(value.customDataPatch['category'], 'Дети');
    },
  );

  testWidgets('disciplines categories and levels are optional metadata', (
    tester,
  ) async {
    final api = _TeacherFieldsApi();
    final key = GlobalKey<TeacherEmploymentFieldsState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          magicCrmServiceProvider.overrideWithValue(MagicCrmService(api)),
          magicSettingsServiceProvider.overrideWithValue(
            MagicSettingsService(api),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TeacherEmploymentFields(key: key, requireRate: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Центральный'));
    await tester.tap(find.text('Выберите ставку'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('750 ₽').last);
    await tester.pumpAndSettle();

    final value = key.currentState!.validateAndRead();

    expect(value, isNotNull);
    expect(value!.branchIds, ['branch-a']);
    expect(value.disciplineIds, isEmpty);
    expect(value.levels, isEmpty);
    expect(value.categories, isEmpty);
  });
}

class _TeacherFieldsApi extends MagicApiClient {
  _TeacherFieldsApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    final body = switch (path) {
      '/crm/branches' => {
        'items': [
          {'id': 'branch-a', 'name': 'Центральный'},
        ],
      },
      '/crm/disciplines' => {
        'items': [
          {
            'id': 'discipline-a',
            'name': 'Вокал',
            'lifecycleState': 'active',
            'version': 1,
          },
        ],
      },
      '/settings/crm-custom-fields' => {
        'fields': [
          {
            'entity': 'teachers',
            'key': 'levels',
            'label': 'Уровни обучения',
            'type': 'select',
            'options': ['Начальный', 'Средний'],
          },
          {
            'entity': 'teachers',
            'key': 'categories',
            'label': 'Категории',
            'type': 'select',
            'options': ['Дети', 'Взрослые'],
          },
        ],
      },
      _ => throw StateError('Unexpected GET $path'),
    };
    return body as T;
  }
}
