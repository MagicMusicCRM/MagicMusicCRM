import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_employment_fields.dart';

class TeacherPayoutDraft {
  const TeacherPayoutDraft({
    required this.kind,
    required this.amount,
    required this.reasonText,
  });

  final String kind;
  final num amount;
  final String reasonText;
}

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
  final reason = await showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
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
  );
  controller.dispose();
  return reason;
}

Future<String?> showTeacherPayrollDeleteDialog(
  BuildContext context, {
  required bool rate,
}) async {
  final controller = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(rate ? 'Удалить запись ставки?' : 'Удалить выплату?'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 500,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Причина удаления *'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            if (controller.text.trim().isEmpty) return;
            Navigator.pop(dialogContext, true);
          },
          child: const Text('Удалить'),
        ),
      ],
    ),
  );
  final reason = controller.text.trim();
  controller.dispose();
  return confirmed == true ? reason : null;
}

Future<TeacherPayoutDraft?> showTeacherBonusDeductionDialog(
  BuildContext context,
) {
  return showDialog<TeacherPayoutDraft>(
    context: context,
    builder: (_) => const _TeacherBonusDeductionDialog(),
  );
}

class _TeacherBonusDeductionDialog extends StatefulWidget {
  const _TeacherBonusDeductionDialog();

  @override
  State<_TeacherBonusDeductionDialog> createState() =>
      _TeacherBonusDeductionDialogState();
}

class _TeacherBonusDeductionDialogState
    extends State<_TeacherBonusDeductionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _commentController = TextEditingController();
  String _kind = 'bonus';

  @override
  void dispose() {
    _amountController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      TeacherPayoutDraft(
        kind: _kind,
        amount: num.parse(_amountController.text.trim().replaceAll(',', '.')),
        reasonText: _commentController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Доплата / Вычет'),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'bonus', label: Text('Доплата')),
                  ButtonSegment(value: 'deduction', label: Text('Вычет')),
                ],
                selected: {_kind},
                onSelectionChanged: (selection) =>
                    setState(() => _kind = selection.first),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Сумма, ₽ *'),
                validator: (value) {
                  final parsed = num.tryParse(
                    value?.trim().replaceAll(',', '.') ?? '',
                  );
                  return parsed == null || parsed <= 0
                      ? 'Введите сумму больше нуля'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _commentController,
                decoration: const InputDecoration(labelText: 'Причина *'),
                maxLength: 500,
                validator: (value) =>
                    value?.trim().isEmpty == true ? 'Укажите причину' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Сохранить')),
      ],
    );
  }
}
