import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_attendance_dialog.dart';

/// P2-5: the v7 attendance sheet replaced the Switch rows with present/absent
/// chips. This locks that the chip toggle still drives the LOCKED PATCH body
/// (`items[{studentId, status: 'present'|'absent', passReason}]`).
class _FakeAttendanceClient extends MagicApiClient {
  _FakeAttendanceClient()
      : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  Map<String, dynamic>? lastPatchBody;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path.endsWith('/attendance')) {
      return <String, dynamic>{
        'lessonId': 'lesson-1',
        'students': [
          {
            'studentId': 's1',
            'studentName': 'Анна Иванова',
            'status': 'present',
            'passReason': '',
          },
          {
            'studentId': 's2',
            'studentName': 'Борис Петров',
            'status': 'present',
            'passReason': '',
          },
        ],
      } as T;
    }
    throw UnimplementedError('GET $path');
  }

  @override
  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    lastPatchBody = data as Map<String, dynamic>?;
    return <String, dynamic>{'lessonId': 'lesson-1', 'students': <dynamic>[]} as T;
  }
}

void main() {
  testWidgets('v7 attendance chips drive the locked present/absent PATCH body',
      (tester) async {
    final fake = _FakeAttendanceClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicApiClientProvider.overrideWithValue(fake)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () =>
                      LessonAttendanceDialog.show(ctx, {'id': 'lesson-1'}),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Loaded: both students + binary chips, no reason field yet.
    expect(find.text('Анна Иванова'), findsOneWidget);
    expect(find.text('Борис Петров'), findsOneWidget);
    expect(find.text('Был'), findsNWidgets(2));
    expect(find.text('Н/Б'), findsNWidgets(2));
    expect(find.byType(TextField), findsNothing);

    // Mark the first student absent → reason field appears.
    await tester.tap(find.text('Н/Б').first);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    // Save → PATCH carries s1 absent, s2 present (contract preserved).
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    final items =
        (fake.lastPatchBody?['items'] as List).cast<Map<String, dynamic>>();
    final s1 = items.firstWhere((e) => e['studentId'] == 's1');
    final s2 = items.firstWhere((e) => e['studentId'] == 's2');
    expect(s1['status'], 'absent');
    expect(s2['status'], 'present');
  });
}
