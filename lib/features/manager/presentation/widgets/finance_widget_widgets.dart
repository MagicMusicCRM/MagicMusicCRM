part of 'finance_widget.dart';

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
/// sheet with the payload for [_FinanceWidgetState._addExpense].
class _ExpenseSheetForm extends StatefulWidget {
  const _ExpenseSheetForm({this.initialExpense});

  final Map<String, dynamic>? initialExpense;

  @override
  State<_ExpenseSheetForm> createState() => _ExpenseSheetFormState();
}

class _ExpenseSheetFormState extends State<_ExpenseSheetForm> {
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
