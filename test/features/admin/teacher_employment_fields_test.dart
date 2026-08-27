import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_employment_fields.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_employment_reference_gateway.dart';

void main() {
  testWidgets(
    'shared teacher fields return branches disciplines configured options and rate',
    (tester) async {
      final gateway = _FakeTeacherEmploymentReferenceGateway();
      final key = GlobalKey<TeacherEmploymentFieldsState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TeacherEmploymentFields(
                key: key,
                gateway: gateway,
                requireRate: true,
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
    final gateway = _FakeTeacherEmploymentReferenceGateway();
    final key = GlobalKey<TeacherEmploymentFieldsState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TeacherEmploymentFields(
              key: key,
              gateway: gateway,
              requireRate: true,
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

  testWidgets('selected fallback options remain when settings has no option', (
    tester,
  ) async {
    final key = GlobalKey<TeacherEmploymentFieldsState>();
    final gateway = _FakeTeacherEmploymentReferenceGateway(
      customOptionsByKey: const {},
    );
    const initial = TeacherEmploymentInitial(
      branches: [
        {'id': 'branch-a', 'name': 'Центральный'},
      ],
      levels: {'Сохранённый уровень'},
      categories: {'Сохранённая категория'},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TeacherEmploymentFields(
              key: key,
              gateway: gateway,
              initial: initial,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Центральный'), findsOneWidget);
    await tester.tap(find.text('Уровни'));
    await tester.pump();
    expect(find.text('Сохранённый уровень'), findsOneWidget);
    await tester.tap(find.text('Категории'));
    await tester.pump();
    expect(find.text('Сохранённая категория'), findsOneWidget);

    final value = key.currentState!.validateAndRead();
    expect(value?.levels, ['Сохранённый уровень']);
    expect(value?.categories, ['Сохранённая категория']);
  });

  testWidgets('settings failure keeps branch and discipline selection usable', (
    tester,
  ) async {
    final key = GlobalKey<TeacherEmploymentFieldsState>();
    final gateway = _FakeTeacherEmploymentReferenceGateway(
      customOptionsError: StateError('settings unavailable'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TeacherEmploymentFields(key: key, gateway: gateway),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Центральный'), findsOneWidget);
    expect(find.text('Вокал'), findsOneWidget);
    expect(
      find.text('Не удалось загрузить настройки преподавателя.'),
      findsNothing,
    );
  });

  testWidgets('branch failure shows the canonical Russian terminal error', (
    tester,
  ) async {
    final key = GlobalKey<TeacherEmploymentFieldsState>();
    final gateway = _FakeTeacherEmploymentReferenceGateway(
      branchError: StateError('branches unavailable'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TeacherEmploymentFields(key: key, gateway: gateway),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Не удалось загрузить настройки преподавателя.'),
      findsOneWidget,
    );
    expect(find.text('Повторить'), findsOneWidget);
    expect(key.currentState!.validateAndRead(), isNull);
  });

  testWidgets('late discipline load cannot overwrite a newer fields owner', (
    tester,
  ) async {
    final staleDisciplines =
        Completer<List<TeacherEmploymentReferenceOption>>();
    final firstKey = GlobalKey<TeacherEmploymentFieldsState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TeacherEmploymentFields(
              key: firstKey,
              gateway: _FakeTeacherEmploymentReferenceGateway(
                disciplineFuture: staleDisciplines.future,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.text('Центральный'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TeacherEmploymentFields(
              key: GlobalKey<TeacherEmploymentFieldsState>(),
              gateway: _FakeTeacherEmploymentReferenceGateway(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    staleDisciplines.complete(const [
      TeacherEmploymentReferenceOption(
        id: 'discipline-stale',
        name: 'Устаревшая дисциплина',
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Вокал'), findsOneWidget);
    expect(find.text('Устаревшая дисциплина'), findsNothing);
  });
}

class _FakeTeacherEmploymentReferenceGateway
    implements TeacherEmploymentReferenceGateway {
  _FakeTeacherEmploymentReferenceGateway({
    this.branchError,
    this.customOptionsError,
    this.customOptionsByKey,
    this.disciplineFuture,
  });

  final Object? branchError;
  final Object? customOptionsError;
  final Map<String, List<String>>? customOptionsByKey;
  final Future<List<TeacherEmploymentReferenceOption>>? disciplineFuture;

  @override
  Future<List<TeacherEmploymentReferenceOption>> loadBranches() async {
    if (branchError case final error?) throw error;
    return const [
      TeacherEmploymentReferenceOption(id: 'branch-a', name: 'Центральный'),
    ];
  }

  @override
  Future<List<TeacherEmploymentReferenceOption>> loadDisciplines() {
    return disciplineFuture ??
        Future.value(const [
          TeacherEmploymentReferenceOption(id: 'discipline-a', name: 'Вокал'),
        ]);
  }

  @override
  Future<List<String>> loadTeacherCustomOptions(String key) async {
    if (customOptionsError case final error?) throw error;
    final configured = customOptionsByKey;
    if (configured != null) return configured[key] ?? const [];
    return switch (key) {
      'levels' => const ['Начальный', 'Средний'],
      'categories' => const ['Дети', 'Взрослые'],
      _ => const [],
    };
  }
}
