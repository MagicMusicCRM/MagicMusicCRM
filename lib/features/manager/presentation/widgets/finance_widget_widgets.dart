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
  // NOTE: "Абонемент" is intentionally NOT a payment type here. A subscription
  // is a real entity (lessons + validity) issued from a package via the student
  // card → «Выдать абонемент» (issueSubscription), which atomically creates the
  // payment AND the app.subscriptions row the client's «Абонемент» window reads.
  // A plain payment cannot represent a subscription, so we only offer ad-hoc
  // payment categories here.
  String _type = 'extra_lesson';
  List<Map<String, dynamic>> _students = [];
  String? _selectedStudentId;
  String? _selectedStudentName;

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

  static String _studentName(Map<String, dynamic> student) {
    final name = '${student['first_name'] ?? ''} ${student['last_name'] ?? ''}'
        .trim();
    return name.isEmpty ? 'Без имени' : name;
  }

  Future<void> _pickStudent() async {
    SearchableSelect.show(
      context: context,
      title: 'Ученик',
      hintText: 'Имя, телефон, email…',
      selectedId: _selectedStudentId,
      isNullable: false,
      items: [
        for (final student in _students)
          SearchableSelectItem(
            id: student['id'].toString(),
            label: _studentName(student),
            subtitle: student['phone']?.toString(),
          ),
      ],
      onSearch: (query) async {
        final response = await ref
            .read(magicCrmServiceProvider)
            .searchStudents(q: query, limit: 30);
        final items = response['items'];
        if (items is! List) return const <SearchableSelectItem>[];
        return [
          for (final row in items.whereType<Map<String, dynamic>>())
            SearchableSelectItem(
              id: row['id'].toString(),
              label: _studentName(row),
              subtitle: row['phone']?.toString(),
            ),
        ];
      },
      onSelected: (item) => setState(() {
        _selectedStudentId = item?.id;
        _selectedStudentName = item?.label;
      }),
    );
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
          // Searchable, not a dropdown: the pre-loaded page is capped at 100
          // students, so a longer roster simply could not be paid for. Typing
          // hits the server, which also matches phone and custom fields.
          InkWell(
            onTap: _pickStudent,
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Ученик'),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedStudentName ?? 'Выберите ученика',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _selectedStudentName == null
                          ? TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            )
                          : null,
                    ),
                  ),
                  const Icon(Icons.search_rounded, size: 18),
                ],
              ),
            ),
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
            decoration: const InputDecoration(
              labelText: 'Тип',
              helperText:
                  'Абонемент выдаётся в карточке ученика → «Выдать абонемент»',
              helperMaxLines: 2,
            ),
            items: [
              DropdownMenuItem(
                value: 'extra_lesson',
                child: Text('Доп. занятие'),
              ),
              DropdownMenuItem(value: 'other', child: Text('Прочее')),
            ],
            onChanged: (v) => setState(() => _type = v ?? 'extra_lesson'),
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

/// v7 finance export bar (P5-7, KVA-198) — two flat-gold buttons that download
/// the authenticated `GET /analytics/finance/monthly.{csv,xlsx}` exports for the
/// period currently selected in [FinanceWidget] and open the saved file.
///
/// Both buttons share the single [exporting] flag (one download at a time) and
/// show an inline spinner on the button that triggered the download — the actual
/// fetch runs off the UI thread in [_FinanceWidgetState._exportFinance].
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
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
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
