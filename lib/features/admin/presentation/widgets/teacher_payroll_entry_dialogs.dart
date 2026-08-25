import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/widgets/teacher_rate_selector.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_payroll_dialog_controller_owner.dart';

class TeacherRateEdit {
  const TeacherRateEdit({
    required this.rate,
    required this.effectiveFrom,
    required this.reasonText,
  });

  final num rate;
  final DateTime effectiveFrom;
  final String reasonText;
}

class TeacherPayoutEdit {
  const TeacherPayoutEdit({
    required this.kind,
    required this.amount,
    required this.paidAt,
    required this.comment,
    required this.reasonText,
  });

  final String kind;
  final num amount;
  final DateTime paidAt;
  final String comment;
  final String reasonText;
}

Future<TeacherRateEdit?> showTeacherRateEditDialog(
  BuildContext context,
  Map<String, dynamic> row,
) async {
  num? rate = _number(row['rate']);
  var effectiveFrom =
      DateTime.tryParse(row['effectiveFrom']?.toString() ?? '') ??
      DateTime.now();
  final reasonController = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => TeacherPayrollDialogControllerOwner(
      controllers: [reasonController],
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Исправить ставку'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TeacherRateSelector(
                  initialRate: rate,
                  required: true,
                  onChanged: (value) => rate = value,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: effectiveFrom,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setDialogState(() => effectiveFrom = picked);
                    }
                  },
                  icon: const Icon(Icons.event_rounded, size: 18),
                  label: Text(
                    'Действует с ${DateFormat('dd.MM.yyyy').format(effectiveFrom)}',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Причина исправления *',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                if (rate == null || reasonController.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    ),
  );
  final reason = reasonController.text.trim();
  if (confirmed != true || rate == null) return null;
  return TeacherRateEdit(
    rate: rate!,
    effectiveFrom: effectiveFrom,
    reasonText: reason,
  );
}

Future<TeacherPayoutEdit?> showTeacherPayoutEditDialog(
  BuildContext context,
  Map<String, dynamic> row,
) async {
  var kind = row['kind']?.toString() ?? 'payout';
  var paidAt =
      DateTime.tryParse(row['paidAt']?.toString() ?? '')?.toLocal() ??
      DateTime.now();
  final amountController = TextEditingController(
    text: _number(row['amount']).toString(),
  );
  final commentController = TextEditingController(
    text: row['comment']?.toString() ?? '',
  );
  final reasonController = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => TeacherPayrollDialogControllerOwner(
      controllers: [amountController, commentController, reasonController],
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Исправить выплату'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  menuMaxHeight: 256,
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'Тип'),
                  items: const [
                    DropdownMenuItem(value: 'payout', child: Text('Выплата')),
                    DropdownMenuItem(value: 'bonus', child: Text('Доплата')),
                    DropdownMenuItem(value: 'deduction', child: Text('Вычет')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => kind = value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Сумма, ₽ *'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: paidAt,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setDialogState(() => paidAt = picked);
                  },
                  icon: const Icon(Icons.event_rounded, size: 18),
                  label: Text(DateFormat('dd.MM.yyyy').format(paidAt)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: commentController,
                  maxLength: 1000,
                  decoration: const InputDecoration(labelText: 'Комментарий'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Причина исправления *',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                final amount = num.tryParse(
                  amountController.text.trim().replaceAll(',', '.'),
                );
                if (amount == null ||
                    amount <= 0 ||
                    reasonController.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    ),
  );
  final amount = num.tryParse(
    amountController.text.trim().replaceAll(',', '.'),
  );
  final result = confirmed == true && amount != null && amount > 0
      ? TeacherPayoutEdit(
          kind: kind,
          amount: amount,
          paidAt: paidAt,
          comment: commentController.text.trim(),
          reasonText: reasonController.text.trim(),
        )
      : null;
  return result;
}

num _number(dynamic value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? 0;
}
