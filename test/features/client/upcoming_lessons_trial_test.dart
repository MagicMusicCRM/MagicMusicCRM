import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/features/client/presentation/widgets/upcoming_lessons_list.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru', null));

  testWidgets('клиент видит явную метку пробного урока', (tester) async {
    final scheduledAt = DateTime.now()
        .toUtc()
        .add(const Duration(days: 1))
        .toIso8601String();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          upcomingLessonsRichProvider.overrideWith(
            (ref) async => [
              {
                'id': 'trial-a',
                'scheduled_at': scheduledAt,
                'duration_minutes': 60,
                'is_trial': true,
                'status': 'scheduled',
                'teacher_first_name': 'Ирина',
                'teacher_last_name': 'Петрова',
                'branch_name': 'Сокол',
                'room_name': 'Класс фортепиано 7',
              },
            ],
          ),
          pastLessonsRichProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: Scaffold(body: UpcomingLessonsList())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Пробный урок'), findsOneWidget);
    expect(find.textContaining('Ирина Петрова'), findsOneWidget);
    expect(find.textContaining('Сокол'), findsOneWidget);
  });
}
