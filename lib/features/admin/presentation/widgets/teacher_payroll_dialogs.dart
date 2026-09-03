import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_employment_fields.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_payroll_dialog_controller_owner.dart';

Future<String?> showTeacherEmploymentChangeReasonDialog(
  BuildContext context, {
  required TeacherEmploymentValue employment,
  required TeacherEmploymentInitial initial,
}) async {
  final money = NumberFormat('#,##0', 'ru');
  final controller = TextEditingController();
  String? errorText;
  final changes = <String>[
    if (employment.salaryChanged)
      'Оклад: ${money.format(initial.salary ?? 0)} → '
          '${money.format(employment.salary ?? 0)} ₽',
    if (employment.rateChanged)
      'Ставка: ${money.format(initial.rate ?? 0)} → '
          '${money.format(employment.rate ?? 0)} ₽/ч',
  ];
  final reason = await showMagicDialog<String>(
    context: context,
    builder: (dialogContext) => TeacherPayrollDialogControllerOwner(
      controllers: [controller],
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Подтвердите финансовые условия'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(changes.join('\n')),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Причина изменения',
                    hintText: 'Например: новые условия с 1 сентября',
                    errorText: errorText,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isEmpty) {
                  setDialogState(() => errorText = 'Укажите причину');
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              child: const Text('Подтвердить и сохранить'),
            ),
          ],
        ),
      ),
    ),
  );
  return reason;
}
