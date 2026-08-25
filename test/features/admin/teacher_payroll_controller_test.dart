import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_payroll_controller.dart';

class _PayrollApi extends MagicApiClient {
  _PayrollApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  int version = 3;
  int loads = 0;
  Map<String, dynamic>? payoutBody;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    expect(path, '/crm/teachers/teacher-a/payroll');
    loads += 1;
    return {
          'teacherId': 'teacher-a',
          'version': version,
          'debt': version == 3 ? 6000 : 0,
          'rateHistory': <dynamic>[],
          'payouts': <dynamic>[],
        }
        as T;
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    expect(path, '/crm/teachers/teacher-a/payouts');
    payoutBody = Map<String, dynamic>.from(data! as Map);
    version += 1;
    return {'version': version} as T;
  }
}

void main() {
  test(
    'loads current version and reloads after versioned debt payout',
    () async {
      final api = _PayrollApi();
      final controller = TeacherPayrollController(
        service: MagicCrmService(api),
        teacherId: 'teacher-a',
      );
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.expectedVersion, 3);
      expect(controller.debt, 6000);

      await controller.payAllDebt();

      expect(api.payoutBody, {
        'kind': 'payout',
        'amount': 6000,
        'expectedVersion': 3,
        'reasonText': 'Оплата всей задолженности',
        'comment': 'Оплата всей задолженности',
      });
      expect(api.loads, 2);
      expect(controller.expectedVersion, 4);
      expect(controller.debt, 0);
      expect(controller.error, isNull);
      expect(controller.mutating, isFalse);
    },
  );
}
