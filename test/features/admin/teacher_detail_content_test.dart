import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_detail_content.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  const teacher = <String, dynamic>{
    'students_count': 2,
    'lessons_count': 8,
    'is_app_account': true,
    'app_role': 'teacher',
    'password_configured': true,
  };

  testWidgets(
    'content credential metric is visible only to privileged actors',
    (tester) async {
      await tester.pumpWidget(
        _host(
          const TeacherDetailSummary(
            teacher: teacher,
            canManageCredentials: false,
          ),
        ),
      );
      expect(find.text('Пароль'), findsNothing);

      await tester.pumpWidget(
        _host(
          const TeacherDetailSummary(
            teacher: teacher,
            canManageCredentials: true,
          ),
        ),
      );
      expect(find.text('Пароль'), findsOneWidget);
      expect(find.text('Настроен'), findsOneWidget);
    },
  );
}
