import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_attendance_dialog.dart';
import 'package:magic_music_crm/features/auth/data/models/release_gate_models.dart';
import 'package:magic_music_crm/features/auth/providers/release_gate_provider.dart';

/// KVA-237: the v7 attendance sheet uses the 5 HolliHop-статусов (kind) in a
/// dropdown. This locks that a kind change drives the PATCH body
/// (`items[{studentId, kind, status, passReason}]` + `notifyClient`).
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
                'kind': 'attended',
                'passReason': '',
              },
              {
                'studentId': 's2',
                'studentName': 'Борис Петров',
                'status': 'present',
                'kind': 'attended',
                'passReason': '',
              },
            ],
          }
          as T;
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
    return <String, dynamic>{'lessonId': 'lesson-1', 'students': <dynamic>[]}
        as T;
  }
}

void main() {
  testWidgets('KVA-237: kind dropdown drives the attendance PATCH body', (
    tester,
  ) async {
    final fake = _FakeAttendanceClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          magicApiClientProvider.overrideWithValue(fake),
          releaseGateStatusProvider.overrideWith(
            (ref) async => const ReleaseGateStatus(
              role: 'admin',
              profileComplete: true,
              legalAccepted: true,
              deletionPending: false,
            ),
          ),
        ],
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

    // Loaded: both students with the kind dropdown (2 селекта «Занятие»)
    // and a notes field per student + чекбокс уведомления.
    expect(find.text('Анна Иванова'), findsOneWidget);
    expect(find.text('Борис Петров'), findsOneWidget);
    expect(find.text('Занятие'), findsNWidgets(2));
    expect(find.text('Уведомить об изменениях'), findsOneWidget);

    // Первому ученику ставим «Неоплачиваемый пропуск» через дропдаун.
    await tester.tap(find.text('Занятие').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Неоплачиваемый пропуск').last);
    await tester.pumpAndSettle();

    // Включаем «Уведомить об изменениях».
    await tester.tap(find.text('Уведомить об изменениях'));
    await tester.pumpAndSettle();

    // Save → PATCH: s1 unpaid_miss/absent, s2 attended/present, notifyClient.
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    final items = (fake.lastPatchBody?['items'] as List)
        .cast<Map<String, dynamic>>();
    final s1 = items.firstWhere((e) => e['studentId'] == 's1');
    final s2 = items.firstWhere((e) => e['studentId'] == 's2');
    expect(s1['kind'], 'unpaid_miss');
    expect(s1['status'], 'absent');
    expect(s2['kind'], 'attended');
    expect(s2['status'], 'present');
    expect(fake.lastPatchBody?['notifyClient'], true);
  });

  testWidgets('KVA-237: partially paid kind sends charge share', (
    tester,
  ) async {
    final fake = _FakeAttendanceClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          magicApiClientProvider.overrideWithValue(fake),
          releaseGateStatusProvider.overrideWith(
            (ref) async => const ReleaseGateStatus(
              role: 'admin',
              profileComplete: true,
              legalAccepted: true,
              deletionPending: false,
            ),
          ),
        ],
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

    await tester.tap(find.text('Занятие').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Частично оплачиваемое').last);
    await tester.pumpAndSettle();

    // Слайдер доли появился; сохраняем с дефолтной долей.
    expect(find.byType(Slider), findsOneWidget);
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    final items = (fake.lastPatchBody?['items'] as List)
        .cast<Map<String, dynamic>>();
    final s1 = items.firstWhere((e) => e['studentId'] == 's1');
    expect(s1['kind'], 'partially_paid');
    expect(s1['status'], 'present');
    expect(s1['chargeShare'], isNotNull);
    expect(fake.lastPatchBody?.containsKey('notifyClient'), false);
  });
}
