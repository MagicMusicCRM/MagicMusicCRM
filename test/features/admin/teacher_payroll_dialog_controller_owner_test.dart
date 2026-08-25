import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_payroll_dialog_controller_owner.dart';

class _TrackingController extends TextEditingController {
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

void main() {
  testWidgets('owns controllers until the dialog route unmounts', (
    tester,
  ) async {
    final controller = _TrackingController();

    await tester.pumpWidget(
      MaterialApp(
        home: TeacherPayrollDialogControllerOwner(
          controllers: [controller],
          builder: (_) => const SizedBox(),
        ),
      ),
    );
    expect(controller.disposed, isFalse);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    expect(controller.disposed, isTrue);
  });
}
