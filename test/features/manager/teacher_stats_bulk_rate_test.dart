import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/teacher_stats_widget.dart';

/// Faked at the API-client seam, NOT by implementing MagicCrmService: its
/// methods live on extensions, and an extension call resolves on the static
/// type — a `implements MagicCrmService` fake would be bypassed entirely and
/// the real code would run against a null client.
class _FakeApiClient extends MagicApiClient {
  _FakeApiClient()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

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
      } as T;
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

Widget _host(_FakeApiClient api) {
  return ProviderScope(
    overrides: [magicApiClientProvider.overrideWithValue(api)],
    child: const MaterialApp(home: Scaffold(body: TeacherStatsWidget())),
  );
}

void main() {
  // The report row is a wide Row (badge, name, days, hours × rate, accrued) and
  // the filter bar is wider still. The default 800x600 test viewport overflows
  // them, and the layout assertions drown the real ones.
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first;
    view.physicalSize = const Size(1800, 1600);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('offers a tick box for trials but not for groups', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_FakeApiClient()));
    await tester.pumpAndSettle();

    expect(find.text('Пробное — Анна'), findsOneWidget);
    expect(find.text('Гитара-1'), findsOneWidget);
    // Only the trial is selectable: a group's rate knob is the GROUP rate, and
    // a per-lesson override would silently shadow it.
    expect(find.byType(Checkbox), findsOneWidget);
  });

  testWidgets('applies "входит в оклад" to the ticked units in one call', (
    tester,
  ) async {
    final api = _FakeApiClient();
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    expect(find.textContaining('Выбрано: 1'), findsOneWidget);
    expect(find.textContaining('занятий: 2'), findsOneWidget);

    await tester.tap(find.text('Проставить ставку'));
    await tester.pumpAndSettle();

    // The rate is a dropdown: open it, then pick the preset.
    await tester.tap(find.text('Ставка педагога (по умолчанию)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Входит в оклад').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Применить'));
    await tester.pumpAndSettle();

    // One request for the whole batch — the old code PATCHed per lesson and
    // could leave the month half-repriced.
    expect(api.bulkRateCalls, 1);
    expect(api.lastPatchBody?['lessonIds'], ['lesson-1', 'lesson-2']);
    // 0 must arrive as 0 — «входит в оклад», not "no rate given".
    expect(api.lastPatchBody?['teacherRate'], 0);
  });
}
