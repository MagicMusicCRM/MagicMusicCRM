import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card_data_controller.dart';

import 'card_fake_api.dart';

class _DelayedFinanceApi extends FakeCardApiClient {
  _DelayedFinanceApi()
    : super(student: {'id': 'student-1', 'firstName': 'Иван'});
  final finance = <Completer<Map<String, dynamic>>>[];
  int commerceReads = 0;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path.endsWith('/commerce')) {
      commerceReads++;
      final result = Completer<Map<String, dynamic>>();
      finance.add(result);
      return await result.future as T;
    }
    return super.get<T>(
      path,
      queryParameters: queryParameters,
      authenticated: authenticated,
    );
  }
}

Map<String, dynamic> projection(int total) => {
  'projection': 'admin_scoped',
  'student': {
    'studentId': 'student-1',
    'lessonBalance': {
      'activeSubscriptionCount': 0,
      'total': '$total',
      'used': '0',
      'reserved': '0',
      'paid': '0',
      'available': '0',
      'debts': <dynamic>[],
    },
  },
};

void main() {
  late _DelayedFinanceApi api;
  late ClientCardDataController data;
  var role = 'admin';
  setUp(() {
    role = 'admin';
    api = _DelayedFinanceApi();
    data = ClientCardDataController(
      crm: MagicCrmService(api),
      resolveRole: () async => role,
    );
  });
  tearDown(() => data.dispose());

  Future<void> open() async {
    final pending = data.loadStudent('student-1');
    await Future<void>.delayed(Duration.zero);
    api.finance.removeAt(0).complete(projection(1));
    await pending;
  }

  test(
    'late full read preserves newer finance and identity snapshot',
    () async {
      await open();
      final full = data.loadStudent('student-1', preserveContent: true);
      await Future<void>.delayed(Duration.zero);
      final partial = data.refreshCommerce('student-1');
      await Future<void>.delayed(Duration.zero);
      api.finance[1].complete(projection(3));
      await partial;
      api.finance[0].complete(projection(2));
      await full;
      expect(data.student!.commerce!.lessonBalance.total, 3);
      expect(data.student!.student['first_name'], 'Иван');
    },
  );

  test('late partial read cannot overwrite newer full read', () async {
    await open();
    final partial = data.refreshCommerce('student-1');
    await Future<void>.delayed(Duration.zero);
    final full = data.loadStudent('student-1', preserveContent: true);
    await Future<void>.delayed(Duration.zero);
    api.finance[1].complete(projection(3));
    await full;
    api.finance[0].complete(projection(2));
    await partial;
    expect(data.student!.commerce!.lessonBalance.total, 3);
  });

  test(
    'finance refresh replaces only finance and respects changed role',
    () async {
      await open();
      final snapshot = data.student!;
      final pending = data.refreshCommerce('student-1');
      await Future<void>.delayed(Duration.zero);
      api.finance.removeAt(0).complete(projection(2));
      await pending;
      expect(identical(data.student!.student, snapshot.student), isTrue);
      expect(identical(data.student!.lessons, snapshot.lessons), isTrue);
      expect(identical(data.student!.funnel, snapshot.funnel), isTrue);
      role = 'teacher';
      await data.refreshCommerce('student-1');
      expect(api.commerceReads, 2);
      expect(data.student!.commerce, isNull);
    },
  );

  test('older finance response is rejected', () async {
    await open();
    final old = data.refreshCommerce('student-1');
    final fresh = data.refreshCommerce('student-1');
    await Future<void>.delayed(Duration.zero);
    api.finance[1].complete(projection(3));
    await fresh;
    api.finance[0].complete(projection(2));
    await old;
    expect(data.student!.commerce!.lessonBalance.total, 3);
  });
}
