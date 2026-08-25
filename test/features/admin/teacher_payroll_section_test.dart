import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_payroll_controller.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_payroll_section.dart';

class _IdleApi extends MagicApiClient {
  _IdleApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());
}

void main() {
  testWidgets(
    'section exposes a bounded loading state before payroll arrives',
    (tester) async {
      final controller = TeacherPayrollController(
        service: MagicCrmService(_IdleApi()),
        teacherId: 'teacher-a',
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TeacherPayrollSection(
              controller: controller,
              canManageHistory: false,
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
    },
  );
}
