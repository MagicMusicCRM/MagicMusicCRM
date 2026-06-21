import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';
import 'package:go_router/go_router.dart';

/// v7 «Расход» category options — Russian label ↔ backend key.
///
/// Backend keys (P5-5) are the canonical `app.expenses.category` values; the
/// labels are what the user picks in the «Добавить расход» sheet.
const List<({String key, String label})> _kExpenseCategories = [
  (key: 'rent', label: 'Аренда'),
  (key: 'salary', label: 'Зарплата'),
  (key: 'utilities', label: 'Коммуналка'),
  (key: 'marketing', label: 'Маркетинг'),
  (key: 'equipment', label: 'Оборудование'),
  (key: 'supplies', label: 'Расходники'),
  (key: 'tax', label: 'Налоги'),
  (key: 'other', label: 'Прочее'),
];

String _expenseCategoryLabel(String? key) {
  for (final c in _kExpenseCategories) {
    if (c.key == key) return c.label;
  }
  return 'Прочее';
}

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

  // ── Expenses (v7 «Расход» flow, P5-6) ──────────────────────────────────────
  List<Map<String, dynamic>> _expenses = [];
  bool _expensesLoading = true;
  double _expensesTotal = 0;
  bool _savingExpense = false;

  @override
  void initState() {
    super.initState();
    _loadPayments();
    _loadExpenses();
  }

  DateTime _periodStart() {
    final now = DateTime.now();
    switch (_period) {
      case 'week':
        return now.subtract(const Duration(days: 7));
      case 'year':
        return DateTime(now.year, 1, 1);
      default:
        return DateTime(now.year, now.month, 1);
    }
  }

  Future<void> _loadPayments() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final from = _periodStart();

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

  Future<void> _loadExpenses() async {
    if (mounted) setState(() => _expensesLoading = true);
    try {
      final res = await ref
          .read(magicCrmServiceProvider)
          .listExpenses(from: _periodStart().toIso8601String(), limit: 50);
      final items = (res['items'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      final total = (res['total'] as num?)?.toDouble() ?? 0;
      if (!mounted) return;
      setState(() {
        _expenses = items;
        _expensesTotal = total;
        _expensesLoading = false;
      });
    } catch (_) {
      // Expenses are a secondary panel — never block the payments view if the
      // aggregate fails; just show an empty state and let the user retry.
      if (!mounted) return;
      setState(() {
        _expenses = [];
        _expensesTotal = 0;
        _expensesLoading = false;
      });
    }
  }

  Future<void> _addExpense() async {
    if (_savingExpense) return;
    final result = await showMagicSheet<Map<String, dynamic>>(
      context,
      title: 'Добавить расход',
      subtitle: 'Сумма, категория и комментарий',
      icon: Icons.receipt_long_rounded,
      builder: (_) => const _ExpenseSheetForm(),
    );
    if (result == null || !mounted) return;

    setState(() => _savingExpense = true);
    try {
      await ref
          .read(magicCrmServiceProvider)
          .createExpense(
            amount: result['amount'] as num,
            category: result['category'] as String,
            description: result['description'] as String?,
            branchId: result['branchId'] as String?,
          );
      if (mounted) {
        MagicToast.show(
          context,
          'Расход добавлен',
          type: MagicToastType.success,
        );
      }
      await _loadExpenses();
    } catch (e) {
      if (mounted) {
        MagicToast.show(
          context,
          'Не удалось добавить расход',
          detail: '$e',
          type: MagicToastType.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _savingExpense = false);
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
                    _loadExpenses();
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
          _ExpensesPanel(
            loading: _expensesLoading,
            saving: _savingExpense,
            total: _expensesTotal,
            expenses: _expenses,
            onAdd: _addExpense,
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
                        // Show when the payment actually happened
                        // (payment_date), not when the row was inserted, so
                        // late-entered payments don't appear in the wrong period.
                        final rawDate = p['payment_date'] ?? p['created_at'];
                        final dt = rawDate != null
                            ? DateTime.tryParse(rawDate.toString())
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
                                    final id = student['id']?.toString();
                                    if (id == null || id.isEmpty) return;
                                    await context.push('/student/$id');
                                    _loadPayments();
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

/// v7 «Расходы» panel — total + the most recent expenses, with the flat-gold
/// «+ Расход» action that opens the [showMagicSheet]-based add flow.
///
/// Theme-aware: surfaces/text read from [ColorScheme]; brand accents (gold) and
/// the negative amount color (danger) come from the v7 [AppColor] tokens.
class _ExpensesPanel extends StatelessWidget {
  const _ExpensesPanel({
    required this.loading,
    required this.saving,
    required this.total,
    required this.expenses,
    required this.onAdd,
  });

  final bool loading;
  final bool saving;
  final double total;
  final List<Map<String, dynamic>> expenses;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fmt = NumberFormat('#,##0', 'ru');
    // Surface a few recent rows; the full ledger lives on its own screen.
    final recent = expenses.take(3).toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.outlineVariant.withAlpha(90)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Расходы за период',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: SkeletonBox(width: 120, height: 24),
                      )
                    else
                      Text(
                        '${fmt.format(total)} ₽',
                        style: const TextStyle(
                          color: AppColor.danger,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                ),
              ),
              _AddExpenseButton(saving: saving, onPressed: onAdd),
            ],
          ),
          if (loading) ...[
            const SizedBox(height: 12),
            for (var i = 0; i < 2; i++)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: SkeletonBox(height: 14, radius: AppRadius.sm),
              ),
          ] else if (recent.isEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Нет расходов за период',
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            for (final e in recent) _ExpenseRow(expense: e, fmt: fmt),
          ],
        ],
      ),
    );
  }
}

/// Flat gold «+ Расход» button (AppColor.gold fill, AppColor.onGold text, no
/// shadow — per the Magic Music primary-button rule).
class _AddExpenseButton extends StatelessWidget {
  const _AddExpenseButton({required this.saving, required this.onPressed});

  final bool saving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: saving ? null : onPressed,
      icon: saving
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColor.onGold,
              ),
            )
          : const Icon(Icons.add_rounded, size: 18),
      label: const Text('Расход'),
      style: FilledButton.styleFrom(
        backgroundColor: AppColor.gold,
        foregroundColor: AppColor.onGold,
        disabledBackgroundColor: AppColor.gold.withAlpha(120),
        disabledForegroundColor: AppColor.onGold.withAlpha(160),
        elevation: 0,
        shadowColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// One recent-expense row inside [_ExpensesPanel].
class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({required this.expense, required this.fmt});

  final Map<String, dynamic> expense;
  final NumberFormat fmt;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final amount = (expense['amount'] as num?)?.toDouble() ?? 0;
    final category = _expenseCategoryLabel(expense['category'] as String?);
    final description = (expense['description'] ?? '').toString().trim();
    final rawDate = expense['createdAt'];
    final dt = rawDate != null ? DateTime.tryParse(rawDate.toString()) : null;
    final dateStr = dt != null
        ? DateFormat('d MMM', 'ru').format(dt.toLocal())
        : '';
    final meta = [
      if (dateStr.isNotEmpty) dateStr,
      if (description.isNotEmpty) description,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColor.danger.withAlpha(25),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              size: 17,
              color: AppColor.danger,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (meta.isNotEmpty)
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '− ${fmt.format(amount)} ₽',
            style: const TextStyle(
              color: AppColor.danger,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

/// Body of the v7 «Добавить расход» sheet: amount (required > 0), category
/// dropdown, optional description, and a flat-gold «Сохранить» that pops the
/// sheet with the payload for [_FinanceWidgetState._addExpense].
class _ExpenseSheetForm extends StatefulWidget {
  const _ExpenseSheetForm();

  @override
  State<_ExpenseSheetForm> createState() => _ExpenseSheetFormState();
}

class _ExpenseSheetFormState extends State<_ExpenseSheetForm> {
  final _amountCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  String _category = _kExpenseCategories.first.key;

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _amountCtrl.removeListener(_onChanged);
    _amountCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  double? get _amount {
    final raw = _amountCtrl.text.trim().replaceAll(',', '.');
    return double.tryParse(raw);
  }

  bool get _canSubmit => (_amount ?? 0) > 0;

  void _submit() {
    if (!_canSubmit) return;
    final description = _descriptionCtrl.text.trim();
    Navigator.pop(context, {
      'amount': _amount,
      'category': _category,
      'description': description.isEmpty ? null : description,
      'branchId': null,
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Сумма (₽)',
          style: TextStyle(
            color: colors.onSurfaceVariant,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _amountCtrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          decoration: InputDecoration(
            hintText: '0',
            filled: true,
            fillColor: colors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
              borderSide: const BorderSide(color: AppColor.gold, width: 1.4),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Text(
          'Категория',
          style: TextStyle(
            color: colors.onSurfaceVariant,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: _category,
          dropdownColor: colors.surface,
          decoration: InputDecoration(
            filled: true,
            fillColor: colors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
              borderSide: const BorderSide(color: AppColor.gold, width: 1.4),
            ),
          ),
          items: [
            for (final c in _kExpenseCategories)
              DropdownMenuItem(value: c.key, child: Text(c.label)),
          ],
          onChanged: (v) =>
              setState(() => _category = v ?? _kExpenseCategories.first.key),
        ),
        const SizedBox(height: AppSpace.md),
        Text(
          'Комментарий (необязательно)',
          style: TextStyle(
            color: colors.onSurfaceVariant,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _descriptionCtrl,
          minLines: 1,
          maxLines: 3,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: 'Например: оплата интернета',
            filled: true,
            fillColor: colors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
              borderSide: const BorderSide(color: AppColor.gold, width: 1.4),
            ),
          ),
        ),
        if (!_canSubmit) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Укажите сумму больше нуля',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpace.lg),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _canSubmit ? _submit : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppColor.gold,
              foregroundColor: AppColor.onGold,
              disabledBackgroundColor: AppColor.gold.withAlpha(120),
              disabledForegroundColor: AppColor.onGold.withAlpha(160),
              elevation: 0,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('Сохранить'),
          ),
        ),
      ],
    );
  }
}
