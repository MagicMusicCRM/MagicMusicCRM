import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/teacher_stats_widget.dart';

/// Faked at the API-client seam, NOT by implementing MagicCrmService: its
/// methods live on extensions, and an extension call resolves on the static
/// type — a `implements MagicCrmService` fake would be bypassed entirely and
/// the real code would run against a null client.
class _FakeApiClient extends MagicApiClient {
  _FakeApiClient({this.locked = false})
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final bool locked;

  Map<String, dynamic>? lastPatchBody;
  int bulkRateCalls = 0;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/reports/teacher-stats') {
      return <String, dynamic>{
            'items': [
              {
                'teacherId': 'teacher-a',
                'teacherName': 'Иван Педагог',
                'hoursTotal': 3,
                'accruedTotal': 2300,
                'paidTotal': 0,
                'units': [
                  {
                    'unitType': 'trial',
                    'groupId': null,
                    'unitName': 'Пробное — Анна',
                    'rate': 700,
                    'days': <dynamic>[],
                    'lessonIds': ['lesson-1', 'lesson-2'],
                    'editableLessonIds': locked
                        ? <String>[]
                        : ['lesson-1', 'lesson-2'],
                    'settledLessons': locked ? 2 : 0,
                    'hoursTotal': 2,
                    'accruedTotal': 1400,
                  },
                  {
                    'unitType': 'group',
                    'groupId': 'group-a',
                    'unitName': 'Гитара-1',
                    'rate': 900,
                    'days': <dynamic>[],
                    'lessonIds': ['lesson-3'],
                    'hoursTotal': 1,
                    'accruedTotal': 900,
                  },
                ],
              },
            ],
            'totals': {'hoursTotal': 3, 'accruedTotal': 2300, 'paidTotal': 0},
          }
          as T;
    }
    // Reference lists (branches, teachers, disciplines).
    return <String, dynamic>{'items': <dynamic>[]} as T;
  }

  @override
  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/lessons/teacher-rate') {
      bulkRateCalls += 1;
      lastPatchBody = data as Map<String, dynamic>?;
      final ids = lastPatchBody?['lessonIds'] as List? ?? const [];
      return <String, dynamic>{'updated': ids.length} as T;
    }
    return <String, dynamic>{} as T;
  }
}

Widget _host(_FakeApiClient api, {String role = 'manager'}) {
  return ProviderScope(
    overrides: [
      magicApiClientProvider.overrideWithValue(api),
      capabilitySnapshotProvider.overrideWith(
        (ref) async => CapabilitySnapshot(
          accountId: '$role-1',
          role: role,
          accessVersion: 1,
          capabilities: const {'commerce.teacher_payroll.write'},
          scopes: const {'schedule': 'allBranches'},
        ),
      ),
    ],
    child: const MaterialApp(home: Scaffold(body: TeacherStatsWidget())),
  );
}

void main() {
  // The report row is a wide Row (badge, name, days, hours × rate, accrued) and
  // the filter bar is wider still. The default 800x600 test viewport overflows
  // them, and the layout assertions drown the real ones.
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1800, 1600);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('manager keeps the payroll report read-only', (tester) async {
    final api = _FakeApiClient();
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();

    expect(find.text('Пробное — Анна'), findsOneWidget);
    expect(find.text('Гитара-1'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byIcon(Icons.edit_rounded), findsNothing);

    await tester.tap(find.text('Гитара-1'));
    await tester.pumpAndSettle();
    expect(find.text('Ставка по данной группе'), findsNothing);
    expect(api.bulkRateCalls, 0);
  });

  testWidgets('applies "входит в оклад" to the ticked units in one call', (
    tester,
  ) async {
    final api = _FakeApiClient();
    await tester.pumpWidget(_host(api, role: 'director'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Выбрано: 1'), findsOneWidget);
    expect(find.textContaining('занятий: 2'), findsOneWidget);

    await tester.tap(find.text('Проставить ставку'));
    await tester.pumpAndSettle();

    // The rate is a dropdown: open it, then pick the preset.
    await tester.tap(find.text('Ставка педагога (по умолчанию)').last);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -200));
    await tester.pumpAndSettle();
    final salaried = find.text('Входит в оклад').last;
    await tester.tap(salaried);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Причина изменения *'),
      'Исправление ставки',
    );

    await tester.tap(find.text('Применить'));
    await tester.pumpAndSettle();

    // One request for the whole batch — the old code PATCHed per lesson and
    // could leave the month half-repriced.
    expect(api.bulkRateCalls, 1);
    expect(api.lastPatchBody?['lessonIds'], ['lesson-1', 'lesson-2']);
    // 0 must arrive as 0 — «входит в оклад», not "no rate given".
    expect(api.lastPatchBody?['teacherRate'], 0);
    expect(api.lastPatchBody?['reasonText'], 'Исправление ставки');
  });

  testWidgets('locks settled compensation instead of offering a fake reprice', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_FakeApiClient(locked: true)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Зафиксировано расчётов: 2'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('director can select settled units for a mass correction', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_FakeApiClient(locked: true), role: 'director'),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('директор может исправить массово'),
      findsOneWidget,
    );
    // Both the individual and group rows are intentionally available to the
    // Director: this action is an explicit per-lesson correction.
    expect(find.byType(Checkbox), findsNWidgets(2));
    expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
  });

  testWidgets('director can open the group-rate control', (tester) async {
    await tester.pumpWidget(_host(_FakeApiClient(), role: 'director'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Гитара-1'));
    await tester.pumpAndSettle();

    expect(find.text('Ставка по данной группе'), findsOneWidget);
  });
}
