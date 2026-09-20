import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'card_fake_api.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru', null));
  testWidgets(
    'commerce failure is visible and the finance section can recover',
    (tester) async {
      final api = FakeCardApiClient(
        student: {
          'id': 'student-1',
          'version': 1,
          'firstName': 'Иван',
          'lastName': 'Петров',
          'status': 'active',
        },
      )..commerceFailure = const MagicApiException(message: 'Нет соединения');
      await pumpClientCard(
        tester,
        api: api,
        seed: const {'id': 'student-1'},
        entityType: 'student',
        initialSection: 'payments',
      );
      expect(find.text('Не удалось загрузить финансы'), findsOneWidget);
      api.commerceFailure = null;
      await tester.tap(find.text('Обновить финансы'));
      await tester.pumpAndSettle();
      expect(find.text('Не удалось загрузить финансы'), findsNothing);
    },
  );
}
