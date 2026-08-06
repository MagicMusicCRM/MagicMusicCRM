import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/teacher/presentation/widgets/teacher_schedule_widget.dart';

class _FakeApiClient extends MagicApiClient {
  _FakeApiClient()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  String? requestedTeacherId;
  Map<String, dynamic>? teacherQuery;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    switch (path) {
      case '/profile/me':
        return <String, dynamic>{
              'userId': 'magic2-user',
              'email': 'magic2@gmail.com',
              'role': 'teacher',
              'emailOtp2faEnabled': false,
            }
            as T;
      case '/crm/teachers':
        teacherQuery = Map<String, dynamic>.from(
          queryParameters ?? const <String, dynamic>{},
        );
        return <String, dynamic>{
              'items': <Map<String, dynamic>>[
                {
                  'id': 'teacher-first',
                  'profileUserId': 'another-user',
                  'firstName': 'Алексей',
                },
                {
                  'id': 'teacher-magic2',
                  'profileUserId': 'magic2-user',
                  'firstName': 'Учитель',
                },
              ],
            }
            as T;
      case '/crm/schedule/matrix':
        requestedTeacherId = queryParameters?['teacherId']?.toString();
        return <String, dynamic>{
              'items': <dynamic>[],
              'groups': <dynamic>[],
              'conflicts': <dynamic>[],
            }
            as T;
      default:
        return <String, dynamic>{'items': <dynamic>[]} as T;
    }
  }
}

void main() {
  testWidgets('loads lessons for the signed-in teacher, not the first row', (
    tester,
  ) async {
    final api = _FakeApiClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicApiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(home: Scaffold(body: TeacherScheduleWidget())),
      ),
    );
    // SfCalendar keeps internal animations alive, so pumpAndSettle can wait
    // forever even after both API calls complete. Pump only until the business
    // request under test has been observed.
    for (
      var attempt = 0;
      attempt < 20 && api.requestedTeacherId == null;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(api.teacherQuery?['q'], 'magic2@gmail.com');
    expect(api.requestedTeacherId, 'teacher-magic2');
  });
}
