import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_detail_access_flow.dart';

class _AccessApi extends MagicApiClient {
  _AccessApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  Object? provisionBody;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    expect(path, '/crm/teachers/teacher-a/access');
    return {'email': 'current@example.com', 'password': 'current-password'}
        as T;
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    expect(path, '/crm/teachers/teacher-a/access');
    provisionBody = data;
    return {
          'id': 'teacher-a',
          'email': 'updated@example.com',
          'isAppAccount': true,
        }
        as T;
  }
}

void main() {
  test('loads current credentials before an access update', () async {
    final api = _AccessApi();
    String? seenEmail;
    String? seenPassword;

    final updated = await TeacherDetailAccessFlow.run(
      service: MagicCrmService(api),
      teacherId: 'teacher-a',
      currentEmail: 'legacy@example.com',
      accessExists: true,
      onLoadError: (error) => fail(error.toString()),
      showDialog:
          ({required initialEmail, currentPassword, required onSubmit}) async {
            seenEmail = initialEmail;
            seenPassword = currentPassword;
            await onSubmit('updated@example.com', 'new-password');
            return true;
          },
    );

    expect(seenEmail, 'current@example.com');
    expect(seenPassword, 'current-password');
    expect(api.provisionBody, {
      'email': 'updated@example.com',
      'password': 'new-password',
    });
    expect(updated?['email'], 'updated@example.com');
  });
}
