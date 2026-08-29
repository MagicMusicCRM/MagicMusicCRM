import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_payroll_version_loader.dart';

class _PayrollApi extends MagicApiClient {
  _PayrollApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    expect(path, '/crm/teachers/teacher-a/payroll');
    return {'teacherId': 'teacher-a', 'version': 3} as T;
  }
}

void main() {
  test('loads only the payroll version needed by teacher save', () async {
    final loader = TeacherPayrollVersionLoader(
      service: MagicCrmService(_PayrollApi()),
      teacherId: 'teacher-a',
    );

    await loader.load();

    expect(loader.expectedVersion, 3);
    expect(loader.error, isNull);
  });
}
