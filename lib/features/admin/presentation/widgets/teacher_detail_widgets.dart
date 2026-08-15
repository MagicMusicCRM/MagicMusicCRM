part of 'teacher_detail_dialog.dart';

/// KVA-238: диалог «Доплата / Вычет».
class _BonusDeductionDialog extends ConsumerStatefulWidget {
  final String teacherId;
  final int expectedVersion;

  const _BonusDeductionDialog({
    required this.teacherId,
    required this.expectedVersion,
  });

  @override
  ConsumerState<_BonusDeductionDialog> createState() =>
      _BonusDeductionDialogState();
}

class _BonusDeductionDialogState extends ConsumerState<_BonusDeductionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _commentController = TextEditingController();
  String _kind = 'bonus';
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(magicCrmServiceProvider)
          .createTeacherPayout(
            teacherId: widget.teacherId,
            kind: _kind,
            amount: num.parse(
              _amountController.text.trim().replaceAll(',', '.'),
            ),
            expectedVersion: widget.expectedVersion,
            reasonText: _commentController.text,
            comment: _commentController.text,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userErrorMessage(e, fallback: 'Не удалось сохранить изменение.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
                  final text = value?.trim().replaceAll(',', '.') ?? '';
                  final parsed = num.tryParse(text);
                  if (parsed == null || parsed <= 0) {
                    return 'Введите сумму больше нуля';
                  }
                  return null;
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
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}

class _TeacherMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool wide;

  const _TeacherMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: wide ? 220 : 118,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(54)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

List<Map<String, dynamic>> _asMapList(dynamic value) {
  if (value is! List) return const [];
  return value.whereType<Map<String, dynamic>>().toList();
}

DateTime? _parseDate(dynamic value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  final iso = DateTime.tryParse(text);
  if (iso != null) return iso;
  // Легаси-формат HolliHop: DD.MM.YYYY.
  final match = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})$').firstMatch(text);
  if (match == null) return null;
  return DateTime(
    int.parse(match.group(3)!),
    int.parse(match.group(2)!),
    int.parse(match.group(1)!),
  );
}

String _branchesText(dynamic value) {
  if (value is! List) return '';
  return value
      .map((branch) {
        if (branch is Map) {
          return (branch['name'] ?? branch['branch_name'] ?? '').toString();
        }
        return branch.toString();
      })
      .where((name) => name.trim().isNotEmpty)
      .join(', ');
}

String _roleLabel(String role) {
  return switch (role) {
    'admin' => 'Администратор',
    'manager' => 'Управляющий',
    'director' => 'Директор',
    'teacher' => 'Преподаватель',
    'system_admin' => 'Администратор системы',
    _ => role.isEmpty ? 'Нет' : role,
  };
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

num _asNum(dynamic value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? 0;
}
