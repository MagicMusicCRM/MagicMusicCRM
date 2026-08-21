import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';

class _FakeApiClient extends MagicApiClient {
  _FakeApiClient()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/students/33333333-3333-3333-3333-333333333333/commerce') {
      return <String, dynamic>{
            'projection': 'admin_scoped',
            'student': {
              'studentId': '33333333-3333-3333-3333-333333333333',
              'accounts': const [],
              'subscriptions': const [],
              'movements': const [],
              'technicalHistory': const [],
              'lessonBalance': {
                'activeSubscriptionCount': 0,
                'total': 0,
                'used': 0,
                'reserved': 0,
                'paid': 0,
                'available': 0,
                'debts': const [],
                'nextPaymentAt': null,
                'expiresAt': null,
              },
            },
          }
          as T;
    }
    return <String, dynamic>{'items': const []} as T;
  }
}

Widget _host(Map<String, dynamic> lesson) {
  return ProviderScope(
    overrides: [magicApiClientProvider.overrideWithValue(_FakeApiClient())],
    child: MaterialApp(
      home: Scaffold(body: CreateLessonDialog(lesson: lesson)),
    ),
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('editing a lesson older than 30 days opens the date picker', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final oldLessonDate = DateTime.now().toUtc().subtract(
      const Duration(days: 31),
    );
    // This is the smallest fixture adapted from v4's editable lesson:
    // only the existing edit-path fields needed to open the date picker.
    final lesson = <String, dynamic>{
      'id': '66666666-6666-6666-6666-666666666666',
      'version': 7,
      'student_id': '33333333-3333-3333-3333-333333333333',
      'student_name': 'Иван Прилежный',
      'scheduled_at': oldLessonDate.toIso8601String(),
      'duration_minutes': 60,
    };

    await tester.pumpWidget(_host(lesson));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lesson-date-field')));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
  });
}
