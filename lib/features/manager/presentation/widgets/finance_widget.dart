import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/student_detail_dialog.dart';

class FinanceWidget extends ConsumerStatefulWidget {
  const FinanceWidget({super.key});

  @override
  ConsumerState<FinanceWidget> createState() => _FinanceWidgetState();
}

class _FinanceWidgetState extends ConsumerState<FinanceWidget> {
  List<Map<String, dynamic>> _payments = [];
  bool _loading = true;
  Object? _loadError;
  double _total = 0;
  int _totalCount = 0;
  bool _addingPayment = false;
  String _period = 'month';

  @override
  void initState() {
    super.initState();
    _loadPayments();
  }

  Future<void> _loadPayments() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final now = DateTime.now();
      late DateTime from;
      switch (_period) {
        case 'week':
          from = now.subtract(const Duration(days: 7));
          break;
        case 'year':
          from = DateTime(now.year, 1, 1);
          break;
        default:
          from = DateTime(now.year, now.month, 1);
      }

      // Headline total comes from the server aggregate over the FULL period,
      // not a fold over the (capped) page — otherwise «Итого» silently
      // understates revenue once a period exceeds the page size.
      final result = await ref
          .read(magicCrmServiceProvider)
          .listPaymentsWithTotal(from: from.toIso8601String(), limit: 100);

      setState(() {
        _payments = result.items;
        _total = result.totalAmount.toDouble();
        _totalCount = result.totalCount;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  Future<void> _addPayment() async {
    if (_addingPayment) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _PaymentDialog(),
    );
    if (result == null || !mounted) return;
    setState(() => _addingPayment = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(magicCrmServiceProvider)
          .createPayment(
            studentId: result['student_id'].toString(),
            amount: result['amount'] as num,
            paymentDate: DateTime.now().toIso8601String(),
            method: result['type']?.toString(),
          );
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Платёж добавлен'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadPayments();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Не удалось добавить платёж: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _addingPayment = false);
    }
  }

  String _typeLabel(String? t) {
    switch (t) {
      case 'extra_lesson':
        return 'Доп. занятие';
      case 'other':
        return 'Прочее';
      default:
        return 'Абонемент';
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'ru');
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: _addingPayment ? null : _addPayment,
        child: _addingPayment
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.outlineVariant.withAlpha(90)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Итого поступлений',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '${fmt.format(_total)} ₽',
                        style: const TextStyle(
                          color: AppTheme.success,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (_totalCount > _payments.length)
                        Text(
                          'Всего платежей: $_totalCount · '
                          'показаны первые ${_payments.length}',
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'week', label: Text('Нед.')),
                    ButtonSegment(value: 'month', label: Text('Мес.')),
                    ButtonSegment(value: 'year', label: Text('Год')),
                  ],
                  selected: {_period},
                  onSelectionChanged: (s) {
                    setState(() => _period = s.first);
                    _loadPayments();
                  },
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? AppTheme.success.withAlpha(30)
                          : Colors.transparent,
                    ),
                    foregroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? AppTheme.success
                          : colors.onSurfaceVariant,
                    ),
                    side: WidgetStateProperty.all(
                      BorderSide(color: colors.outlineVariant),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(color: AppTheme.success),
                  )
                : _loadError != null
                ? _FinanceError(error: _loadError, onRetry: _loadPayments)
                : _payments.isEmpty
                ? Center(
                    child: Text(
                      'Нет платежей за период',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : RefreshIndicator(
                    color: AppTheme.success,
                    onRefresh: _loadPayments,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      itemCount: _payments.length,
                      itemBuilder: (ctx, i) {
                        final p = _payments[i];
                        final amount =
                            double.tryParse(p['amount'].toString()) ?? 0;
                        final type = _typeLabel(p['type'] as String?);
                        final student = p['students'];
                        final name = student != null
                            ? '${student['first_name'] ?? ''} ${student['last_name'] ?? ''}'
                                  .trim()
                            : 'Неизвестный ученик';
                        final dt = p['created_at'] != null
                            ? DateTime.tryParse(p['created_at'])
                            : null;
                        final dateStr = dt != null
                            ? DateFormat(
                                'd MMM yyyy, HH:mm',
                                'ru',
                              ).format(dt.toLocal())
                            : '';
                        final note = (p['notes'] ?? p['description'] ?? '')
                            .toString()
                            .trim();
                        final subtitle = [
                          type,
                          if (dateStr.isNotEmpty) dateStr,
                          if (note.isNotEmpty) note,
                        ].join(' · ');

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            onTap: student != null
                                ? () async {
                                    final updated =
                                        await StudentDetailDialog.show(
                                          context,
                                          Map<String, dynamic>.from(student),
                                        );
                                    if (updated == true) _loadPayments();
                                  }
                                : null,
                            leading: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: AppTheme.success.withAlpha(25),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.payments_rounded,
                                color: AppTheme.success,
                              ),
                            ),
                            title: Text(
                              name.isEmpty ? 'Без имени' : name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              subtitle,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                            trailing: Text(
                              '${fmt.format(amount)} ₽',
                              style: const TextStyle(
                                color: AppTheme.success,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _FinanceError extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;

  const _FinanceError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppTheme.danger,
              size: 42,
            ),
            const SizedBox(height: 10),
            Text(
              'Не удалось загрузить платежи',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}

class _PaymentDialog extends ConsumerStatefulWidget {
  const _PaymentDialog();

  @override
  ConsumerState<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends ConsumerState<_PaymentDialog> {
  final _amountCtrl = TextEditingController();
  String _type = 'subscription';
  List<Map<String, dynamic>> _students = [];
  String? _selectedStudentId;

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_onAmountChanged);
    _loadStudents();
  }

  void _onAmountChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadStudents() async {
    final data = await ref
        .read(magicCrmServiceProvider)
        .listStudents(limit: 100);
    if (mounted) setState(() => _students = data);
  }

  @override
  void dispose() {
    _amountCtrl.removeListener(_onAmountChanged);
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amount = double.tryParse(_amountCtrl.text.trim());
    final canSubmit =
        _selectedStudentId != null && amount != null && amount > 0;

    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: Text('Новый платёж'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _selectedStudentId,
            dropdownColor: Theme.of(context).colorScheme.surface,
            decoration: const InputDecoration(labelText: 'Ученик'),
            items: _students.map((s) {
              final name = '${s['first_name'] ?? ''} ${s['last_name'] ?? ''}'
                  .trim();
              return DropdownMenuItem(
                value: s['id'] as String,
                child: Text(name.isEmpty ? 'Без имени' : name),
              );
            }).toList(),
            onChanged: (v) => setState(() => _selectedStudentId = v),
          ),
          SizedBox(height: 10),
          TextField(
            controller: _amountCtrl,
            decoration: const InputDecoration(labelText: 'Сумма (₽)'),
            keyboardType: TextInputType.number,
          ),
          SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _type,
            dropdownColor: Theme.of(context).colorScheme.surface,
            decoration: const InputDecoration(labelText: 'Тип'),
            items: [
              DropdownMenuItem(value: 'subscription', child: Text('Абонемент')),
              DropdownMenuItem(
                value: 'extra_lesson',
                child: Text('Доп. занятие'),
              ),
              DropdownMenuItem(value: 'other', child: Text('Прочее')),
            ],
            onChanged: (v) => setState(() => _type = v ?? 'subscription'),
          ),
          if (!canSubmit) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Выберите ученика и укажите сумму больше нуля',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Отмена'),
        ),
        FilledButton(
          onPressed: canSubmit
              ? () {
                  Navigator.pop(context, {
                    'amount': amount,
                    'type': _type,
                    'student_id': _selectedStudentId,
                  });
                }
              : null,
          child: Text('Добавить'),
        ),
      ],
    );
  }
}
