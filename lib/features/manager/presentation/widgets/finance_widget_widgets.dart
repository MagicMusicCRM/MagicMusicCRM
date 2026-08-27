import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/magic_desktop_scrollbar.dart';
import 'package:magic_music_crm/core/widgets/magic_shimmer.dart';

import 'finance_state.dart';

typedef FinanceVoidAction = Future<void> Function();
typedef FinanceValueAction<T> = Future<void> Function(T value);

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
  for (final category in _kExpenseCategories) {
    if (category.key == key) return category.label;
  }
  return 'Прочее';
}

Widget _financeTotals({
  required BoxConstraints constraints,
  required FinanceState state,
  required ColorScheme colors,
  required NumberFormat format,
}) {
  final range = state.customRange;
  return SizedBox(
    width: constraints.maxWidth >= 760 ? 300 : constraints.maxWidth,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Итого поступлений',
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
        ),
        Text(
          '${format.format(state.total)} ₽',
          style: const TextStyle(
            color: AppTheme.success,
            fontSize: 26,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (range != null && !state.usesExternalRange)
          Text(
            '${DateFormat('d MMM yyyy', 'ru').format(range.start)} - '
            '${DateFormat('d MMM yyyy', 'ru').format(range.end)}',
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11),
          ),
        if (state.totalCount > state.payments.length)
          Text(
            'Всего платежей: ${state.totalCount} · '
            'показаны первые ${state.payments.length}',
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11),
          ),
      ],
    ),
  );
}

List<Widget> _financeRangeControls({
  required FinanceState state,
  required ColorScheme colors,
  required FinanceVoidAction onPickRange,
  required FinanceVoidAction onClearRange,
  required FinanceValueAction<String> onPeriodChanged,
}) {
  final range = state.customRange;
  return [
    if (!state.usesExternalRange)
      IconButton(
        tooltip: 'Выбрать диапазон',
        onPressed: onPickRange,
        icon: Icon(
          Icons.calendar_today_rounded,
          size: 20,
          color: range != null ? AppTheme.success : colors.onSurfaceVariant,
        ),
      ),
    if (range != null && !state.usesExternalRange)
      IconButton(
        tooltip: 'Сбросить диапазон',
        onPressed: onClearRange,
        icon: Icon(
          Icons.close_rounded,
          size: 20,
          color: colors.onSurfaceVariant,
        ),
      ),
    if (!state.usesExternalRange)
      _PeriodSelector(
        period: state.period,
        colors: colors,
        onChanged: onPeriodChanged,
      ),
  ];
}

class FinanceView extends StatefulWidget {
  const FinanceView({
    super.key,
    required this.state,
    required this.onPickRange,
    required this.onClearRange,
    required this.onPeriodChanged,
    required this.onExportCsv,
    required this.onExportXlsx,
    required this.onAddExpense,
    required this.onEditExpense,
    required this.onDeleteExpense,
    required this.onRetryPayments,
    required this.onRefreshPayments,
    required this.onOpenStudent,
  });

  final FinanceState state;
  final FinanceVoidAction onPickRange;
  final FinanceVoidAction onClearRange;
  final FinanceValueAction<String> onPeriodChanged;
  final FinanceVoidAction onExportCsv;
  final FinanceVoidAction onExportXlsx;
  final FinanceVoidAction onAddExpense;
  final FinanceValueAction<Map<String, dynamic>> onEditExpense;
  final FinanceValueAction<Map<String, dynamic>> onDeleteExpense;
  final FinanceVoidAction onRetryPayments;
  final FinanceVoidAction onRefreshPayments;
  final Future<void> Function(String id, String name) onOpenStudent;

  @override
  State<FinanceView> createState() => _FinanceViewState();
}

class _FinanceViewState extends State<FinanceView> {
  final _paymentsScrollController = ScrollController();

  @override
  void dispose() {
    _paymentsScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _FinanceSummary(
            state: state,
            onPickRange: widget.onPickRange,
            onClearRange: widget.onClearRange,
            onPeriodChanged: widget.onPeriodChanged,
          ),
          _ExportBar(
            exporting: state.exporting,
            onExportCsv: widget.onExportCsv,
            onExportXlsx: widget.onExportXlsx,
          ),
          _ExpensesPanel(
            loading: state.expensesLoading,
            saving: state.savingExpense,
            total: state.expensesTotal,
            expenses: state.expenses,
            onAdd: widget.onAddExpense,
            onEdit: widget.onEditExpense,
            onDelete: widget.onDeleteExpense,
          ),
          Expanded(
            child: _PaymentsPanel(
              state: state,
              scrollController: _paymentsScrollController,
              onRetry: widget.onRetryPayments,
              onRefresh: widget.onRefreshPayments,
              onOpenStudent: widget.onOpenStudent,
            ),
          ),
        ],
      ),
    );
  }
}

class _FinanceSummary extends StatelessWidget {
  const _FinanceSummary({
    required this.state,
    required this.onPickRange,
    required this.onClearRange,
    required this.onPeriodChanged,
  });

  final FinanceState state;
  final FinanceVoidAction onPickRange;
  final FinanceVoidAction onClearRange;
  final FinanceValueAction<String> onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fmt = NumberFormat('#,##0', 'ru');
    return Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant.withAlpha(90)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _financeTotals(
              constraints: constraints,
              state: state,
              colors: colors,
              format: fmt,
            ),
            const Text(
              'Новая оплата проводится в карточке ученика',
              style: TextStyle(color: AppColor.text2, fontSize: 12),
            ),
            ..._financeRangeControls(
              state: state,
              colors: colors,
              onPickRange: onPickRange,
              onClearRange: onClearRange,
              onPeriodChanged: onPeriodChanged,
            ),
            if (state.branchId != null)
              SizedBox(
                width: constraints.maxWidth,
                child: Text(
                  'Филиал применён к расходам; платежи показаны по всей школе.',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({
    required this.period,
    required this.colors,
    required this.onChanged,
  });

  final String period;
  final ColorScheme colors;
  final FinanceValueAction<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'week', label: Text('Нед.')),
        ButtonSegment(value: 'month', label: Text('Мес.')),
        ButtonSegment(value: 'year', label: Text('Год')),
      ],
      selected: {period},
      onSelectionChanged: (selection) => onChanged(selection.first),
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
        side: WidgetStateProperty.all(BorderSide(color: colors.outlineVariant)),
      ),
    );
  }
}

class _PaymentsPanel extends StatelessWidget {
  const _PaymentsPanel({
    required this.state,
    required this.scrollController,
    required this.onRetry,
    required this.onRefresh,
    required this.onOpenStudent,
  });

  final FinanceState state;
  final ScrollController scrollController;
  final FinanceVoidAction onRetry;
  final FinanceVoidAction onRefresh;
  final Future<void> Function(String id, String name) onOpenStudent;

  @override
  Widget build(BuildContext context) {
    if (state.loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.success),
      );
    }
    if (state.loadError != null) {
      return _FinanceError(error: state.loadError, onRetry: onRetry);
    }
    if (state.payments.isEmpty) {
      return Center(
        child: Text(
          'Нет платежей за период',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return MagicDesktopScrollbar(
      axis: Axis.vertical,
      controller: scrollController,
      builder: (context, controller) => RefreshIndicator(
        color: AppTheme.success,
        onRefresh: onRefresh,
        child: ListView.builder(
          controller: controller,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          itemCount: state.payments.length,
          itemBuilder: (context, index) => _PaymentTile(
            payment: state.payments[index],
            onOpenStudent: onOpenStudent,
          ),
        ),
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.payment, required this.onOpenStudent});

  final Payment payment;
  final Future<void> Function(String id, String name) onOpenStudent;

  String _typeLabel() => switch (payment.type) {
    'extra_lesson' => 'Доп. занятие',
    'other' => 'Прочее',
    _ => 'Абонемент',
  };

  @override
  Widget build(BuildContext context) {
    final name = payment.hasStudent
        ? payment.studentName
        : 'Неизвестный ученик';
    final rawDate = payment.paymentDate ?? payment.createdAt;
    final date = rawDate == null ? null : DateTime.tryParse(rawDate);
    final dateLabel = date == null
        ? ''
        : DateFormat('d MMM yyyy, HH:mm', 'ru').format(date.toLocal());
    final subtitle = [
      _typeLabel(),
      if (dateLabel.isNotEmpty) dateLabel,
      if (payment.note.isNotEmpty) payment.note,
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: payment.hasStudent ? () => _openStudent(name) : null,
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppTheme.success.withAlpha(25),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.payments_rounded, color: AppTheme.success),
        ),
        title: Text(
          name.isEmpty ? 'Без имени' : name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        trailing: Text(
          '${NumberFormat('#,##0', 'ru').format(payment.amount)} ₽',
          style: const TextStyle(
            color: AppTheme.success,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Future<void> _openStudent(String name) async {
    final id = payment.studentEntityId;
    if (id == null || id.isEmpty) return;
    await onOpenStudent(id, name);
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
              userErrorMessage(
                error,
                fallback: 'Не удалось загрузить платежи.',
              ),
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

class _ExportBar extends StatelessWidget {
  const _ExportBar({
    required this.exporting,
    required this.onExportCsv,
    required this.onExportXlsx,
  });

  final bool exporting;
  final VoidCallback onExportCsv;
  final VoidCallback onExportXlsx;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Row(
        children: [
          Expanded(
            child: _ExportButton(
              icon: Icons.description_rounded,
              label: 'Экспорт CSV',
              busy: exporting,
              onPressed: onExportCsv,
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: _ExportButton(
              icon: Icons.table_chart_rounded,
              label: 'Экспорт XLSX',
              busy: exporting,
              onPressed: onExportXlsx,
            ),
          ),
        ],
      ),
    );
  }
}

/// Flat-gold export button (no shadow — Magic Music primary-button rule). When
/// [busy] it disables and swaps the leading icon for a small spinner.
class _ExportButton extends StatelessWidget {
  const _ExportButton({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: busy ? null : onPressed,
      icon: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColor.onGold,
              ),
            )
          : Icon(icon, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: FilledButton.styleFrom(
        backgroundColor: AppColor.gold,
        foregroundColor: AppColor.onGold,
        disabledBackgroundColor: AppColor.gold.withAlpha(120),
        disabledForegroundColor: AppColor.onGold.withAlpha(160),
        elevation: 0,
        shadowColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// v7 «Расходы» panel — total + the loaded expense history, with the flat-gold
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
    required this.onEdit,
    required this.onDelete,
  });

  final bool loading;
  final bool saving;
  final double total;
  final List<Map<String, dynamic>> expenses;
  final VoidCallback onAdd;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final ValueChanged<Map<String, dynamic>> onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fmt = NumberFormat('#,##0', 'ru');

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
          ] else if (expenses.isEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Нет расходов за период',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
            ),
          ] else ...[
            const SizedBox(height: 10),
            SizedBox(
              height: expenses.length <= 3 ? expenses.length * 52 : 196,
              child: ListView.builder(
                key: const ValueKey('expense-history-list'),
                itemCount: expenses.length,
                itemBuilder: (context, index) {
                  final expense = expenses[index];
                  return _ExpenseRow(
                    expense: expense,
                    fmt: fmt,
                    saving: saving,
                    onEdit: () => onEdit(expense),
                    onDelete: () => onDelete(expense),
                  );
                },
              ),
            ),
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

/// One expense-history row inside [_ExpensesPanel].
class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({
    required this.expense,
    required this.fmt,
    required this.saving,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> expense;
  final NumberFormat fmt;
  final bool saving;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

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
          const SizedBox(width: 2),
          PopupMenuButton<String>(
            key: ValueKey('expense-actions-${expense['id']}'),
            enabled: !saving,
            tooltip: 'Действия с расходом',
            onSelected: (value) {
              if (value == 'edit') onEdit();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.edit_rounded),
                  title: Text('Изменить'),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.delete_outline_rounded),
                  title: Text('Удалить'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Body of the v7 «Добавить расход» sheet: amount (required > 0), category
/// dropdown, optional description, and a flat-gold «Сохранить» that pops the
/// sheet with the payload consumed by the finance composition shell.
class ExpenseSheetForm extends StatefulWidget {
  const ExpenseSheetForm({super.key, this.initialExpense});

  final Map<String, dynamic>? initialExpense;

  @override
  State<ExpenseSheetForm> createState() => _ExpenseSheetFormState();
}

class _ExpenseSheetFormState extends State<ExpenseSheetForm> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _descriptionCtrl;
  late String _category;

  @override
  void initState() {
    super.initState();
    final expense = widget.initialExpense;
    final amount = (expense?['amount'] as num?)?.toDouble();
    final amountText = amount == null
        ? ''
        : amount == amount.truncateToDouble()
        ? amount.toInt().toString()
        : amount.toString();
    _amountCtrl = TextEditingController(text: amountText);
    _descriptionCtrl = TextEditingController(
      text: expense?['description']?.toString() ?? '',
    );
    final initialCategory = expense?['category']?.toString();
    _category = _kExpenseCategories.any((item) => item.key == initialCategory)
        ? initialCategory!
        : _kExpenseCategories.first.key;
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
      'branchId': widget.initialExpense?['branchId'],
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
          autofocus: widget.initialExpense == null,
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
          menuMaxHeight: 256,
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
            child: Text(
              widget.initialExpense == null
                  ? 'Сохранить'
                  : 'Сохранить изменения',
            ),
          ),
        ),
      ],
    );
  }
}
