part of 'client_card.dart';

extension _ClientCardTabsB on _ClientCardState {
  // ── Tab: Комментарии ─────────────────────────────────────────────────────
  Widget _buildCommentsTab(ColorScheme cs) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.xl,
              AppSpace.lg,
              AppSpace.xl,
              AppSpace.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Комментарии'),
                _CommentsList(
                  // For a converted client both halves are loaded, merged,
                  // de-duped by id and origin-badged; single-side cards pass one
                  // ref and render exactly as before (no origin chip).
                  refs: _halfRefs,
                  showOrigin: _isConverted,
                  refreshKey: _commentsRefreshKey,
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.xl,
            AppSpace.sm,
            AppSpace.xl,
            AppSpace.lg,
          ),
          child: _buildCommentInput(cs),
        ),
      ],
    );
  }

  // ── Tab: Семья ───────────────────────────────────────────────────────────
  Widget _buildFamilyTab(ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.lg,
        AppSpace.xl,
        AppSpace.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _sectionTitle('Семья')),
              _buildFamilyAddButton(cs),
            ],
          ),
          _familySection(
            cs,
            loading: _loadingFamily,
            family: _family,
            busy: _familyBusy,
            onRemove: _removeFamilyMember,
          ),
        ],
      ),
    );
  }

  Widget _buildFamilyAddButton(ColorScheme cs) {
    return TextButton.icon(
      onPressed: _familyBusy ? null : _openAddFamilyMemberSheet,
      style: TextButton.styleFrom(
        foregroundColor: AppColor.gold,
        backgroundColor: AppColor.goldSoft,
        disabledForegroundColor: AppColor.gold.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          side: const BorderSide(color: AppColor.goldLine),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
      icon: const Icon(Icons.add_rounded, size: 16),
      label: const Text('Добавить'),
    );
  }

  // ── Tab: История ─────────────────────────────────────────────────────────
  Widget _buildHistoryTab(ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.lg,
        AppSpace.xl,
        AppSpace.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('История статусов'),
          _statusHistorySection(
            cs,
            loading: _loadingHistory,
            history: _statusHistory,
          ),
        ],
      ),
    );
  }

  // ══ STUDENT (entityType == 'student') ════════════════════════════════════
  // Ported from student_detail_screen.dart, adapted to the compact dialog and
  // the unified comments tab. Lead methods above are untouched.

  /// Resolves the student display name with a fallback to the linked profile,
  /// matching student_detail_screen.
  ({String name, String phone, String email}) _studentContact() {
    final s = _student ?? const <String, dynamic>{};
    final profile = s['profiles'] as Map<String, dynamic>?;
    final sfName = s['first_name']?.toString() ?? '';
    final slName = s['last_name']?.toString() ?? '';
    var name = '$sfName $slName'.trim();
    if (name.isEmpty && profile != null) {
      name = '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'
          .trim();
    }
    final phone =
        (s['phone']?.toString().trim().isNotEmpty == true
                ? s['phone']
                : profile?['phone'])
            ?.toString() ??
        '—';
    final email =
        (s['email']?.toString().trim().isNotEmpty == true
                ? s['email']
                : profile?['email'])
            ?.toString() ??
        '—';
    return (
      name: name.isEmpty ? 'Без имени' : name,
      phone: phone,
      email: email,
    );
  }

  String? _nonEmpty(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty || text == '—' ? null : text;
  }

  String? get _clientFirstName => _isStudent
      ? _nonEmpty(_student?['first_name'])
      : _nonEmpty(_leadData['name'] ?? _leadData['first_name']);

  String? get _clientLastName => _isStudent
      ? _nonEmpty(_student?['last_name'])
      : _nonEmpty(_leadData['last_name']);

  String? get _clientPhone => _isStudent
      ? _nonEmpty(_student?['phone'])
      : _nonEmpty(_leadData['phone']);

  String? get _clientEmail => _isStudent
      ? _nonEmpty(_student?['email'])
      : _nonEmpty(_leadData['email']);

  String? get _clientBranchId {
    final studentCustom = _student?['custom_data'];
    if (_isStudent && studentCustom is Map) {
      return _nonEmpty(studentCustom['branchId'] ?? studentCustom['branch_id']);
    }
    return _nonEmpty(_leadData['branch_id']);
  }

  void _updateClientCore(String key, dynamic value) {
    _emitState(() {
      if (_mode.hasLeadHalf) {
        switch (key) {
          case 'firstName':
            _leadData['name'] = value;
            _leadData['first_name'] = value;
          case 'lastName':
            _leadData['last_name'] = value;
          case 'phone':
            _leadData['phone'] = value;
          case 'email':
            _leadData['email'] = value;
          case 'branchId':
            _leadData['branch_id'] = value;
        }
      }
      if (_mode.hasStudentHalf && _student != null) {
        switch (key) {
          case 'firstName':
            _student!['first_name'] = value;
          case 'lastName':
            _student!['last_name'] = value;
          case 'phone':
            _student!['phone'] = value;
          case 'email':
            _student!['email'] = value;
          case 'branchId':
            final cd = Map<String, dynamic>.from(
              _student!['custom_data'] ?? {},
            );
            if (value == null || value == '') {
              cd.remove('branchId');
            } else {
              cd['branchId'] = value;
            }
            _student!['custom_data'] = cd;
        }
      }
      _edited = true;
    });
  }

  // Parse the balance defensively (it can arrive as a string) and color it:
  // red < 0, green > 0, neutral at exactly 0. (Ported from student_detail.)
  num? get _studentBalanceNum => _balance?.balance;

  /// «Остаток: 7 астр.ч. / 14 000 ₽» — денежная часть считается по цене пакета
  /// пропорционально оставшимся часам; без пакета показываем только часы.
  // ── Личный счёт (KVA-235, формат HolliHop: вкладки Приход/Расход) ────────
  Widget _buildLedgerSection(ColorScheme cs) {
    _ledgerFuture ??= ref
        .read(magicCrmServiceProvider)
        .getStudentLedger(_studentId);
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey('ledger-$_ledgerRefreshKey'),
      future: _ledgerFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpace.sm),
            child: LinearProgressIndicator(color: AppColor.gold),
          );
        }
        if (snap.hasError) {
          return Text(
            'Личный счёт недоступен',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          );
        }
        final data = snap.data ?? const {};
        num toNum(Object? v) =>
            v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;
        final income = toNum(data['income_total']);
        final outcome = toNum(data['outcome_total']);
        final items = _list(data['items']);
        final visible = items
            .where(
              (r) => _ledgerTab == 0
                  ? toNum(r['amount']) > 0
                  : toNum(r['amount']) < 0,
            )
            .take(8)
            .toList();
        String rub(num v) => '${v.round()} ₽';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Личный счёт: ${rub(income)} − ${rub(outcome)} = '
                    '${rub(income - outcome)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _openTopUpDialog,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColor.gold,
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  child: const Text('Добавить'),
                ),
                TextButton(
                  onPressed: _openRefundDialog,
                  style: TextButton.styleFrom(
                    foregroundColor: cs.error,
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  child: const Text('Возврат'),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              children: [
                for (final (index, label) in const [
                  (0, 'Приход'),
                  (1, 'Расход'),
                ])
                  ChoiceChip(
                    label: Text(label, style: const TextStyle(fontSize: 12)),
                    selected: _ledgerTab == index,
                    selectedColor: AppColor.goldSoft,
                    onSelected: (_) => _emitState(() => _ledgerTab = index),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            if (visible.isEmpty)
              Text(
                'Операций нет',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              )
            else
              ...visible.map((r) {
                final amount = toNum(r['amount']);
                final dt = DateTime.tryParse(
                  r['occurred_at']?.toString() ?? '',
                )?.toLocal();
                final isVoid = r['status']?.toString() == 'void';
                final meta = [
                  if (dt != null) DateFormat('dd.MM.yy', 'ru').format(dt),
                  // Колонки из эталона HolliHop: филиал, способ, № счёта,
                  // статус, кто добавил.
                  r['branch_name'],
                  r['method'],
                  if ((r['invoice_number']?.toString() ?? '').isNotEmpty)
                    '№ ${r['invoice_number']}',
                  _ledgerStatusLabel(r['status']),
                  r['author_name'],
                ].where((v) => v != null && '$v'.isNotEmpty).join(' · ');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 78,
                        child: Text(
                          '${amount > 0 ? '+' : ''}${amount.round()} ₽',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            // Отменённая строка видна, но перечёркнута: она уже
                            // не деньги, а прятать её нельзя.
                            decoration: isVoid
                                ? TextDecoration.lineThrough
                                : null,
                            color: isVoid
                                ? cs.onSurfaceVariant
                                : (amount > 0 ? AppTheme.success : cs.error),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r['description']?.toString().trim().isNotEmpty ==
                                      true
                                  ? r['description'].toString()
                                  : _ledgerKindLabel(r['kind']),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5),
                            ),
                            if (meta.isNotEmpty)
                              Text(
                                meta,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Действия по строке — только у операций, которые завёл
                      // человек. Платёж и списание за занятие правят там, где
                      // они возникли, а не тут.
                      if (r['editable'] == true && !isVoid)
                        _LedgerRowActions(
                          onEdit: () => _editAdjustment(r),
                          onVoid: () => _voidAdjustment(r),
                        ),
                    ],
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  /// Правка записи личного счёта. Сумма и знак пересобираются сервером от вида
  /// операции, поэтому здесь только величина — «возврат» останется расходом.
  Future<void> _editAdjustment(Map<String, dynamic> row) async {
    // Диалог показывает величину без знака: знак — это вид операции, и
    // пересобирает его сервер.
    final rawAmount = num.tryParse(row['amount']?.toString() ?? '') ?? 0;
    final amountCtrl = TextEditingController(
      text: rawAmount.abs().round().toString(),
    );
    final descriptionCtrl = TextEditingController(
      text: row['description']?.toString() ?? '',
    );
    final invoiceCtrl = TextEditingController(
      text: row['invoice_number']?.toString() ?? '',
    );
    var status = row['status']?.toString() == 'pending' ? 'pending' : 'paid';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Правка операции'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Сумма, ₽'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descriptionCtrl,
                  decoration: const InputDecoration(labelText: 'Комментарий'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: invoiceCtrl,
                  decoration: const InputDecoration(labelText: '№ Счёта'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Статус'),
                  items: const [
                    DropdownMenuItem(value: 'paid', child: Text('Оплачен')),
                    DropdownMenuItem(
                      value: 'pending',
                      child: Text('Не оплачен'),
                    ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => status = value ?? 'paid'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    final amount = num.tryParse(amountCtrl.text.trim().replaceAll(',', '.'));
    amountCtrl.dispose();
    final description = descriptionCtrl.text;
    descriptionCtrl.dispose();
    final invoice = invoiceCtrl.text;
    invoiceCtrl.dispose();
    if (saved != true || !mounted) return;

    try {
      await ref
          .read(magicCrmServiceProvider)
          .updateAdjustment(
            studentId: _studentId,
            adjustmentId: row['id'].toString(),
            amount: amount,
            description: description,
            invoiceNumber: invoice,
            status: status,
          );
      if (!mounted) return;
      _refreshLedger();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось сохранить: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  /// Отмена операции. Спрашиваем подтверждение: это деньги на счёте клиента.
  Future<void> _voidAdjustment(Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отменить операцию?'),
        content: const Text(
          'Операция перестанет учитываться в балансе, но останется в истории '
          'с пометкой об отмене.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Нет'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Отменить операцию'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref
          .read(magicCrmServiceProvider)
          .voidAdjustment(
            studentId: _studentId,
            adjustmentId: row['id'].toString(),
          );
      if (!mounted) return;
      _refreshLedger();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось отменить: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  void _refreshLedger() {
    _emitState(() {
      _ledgerFuture = null;
      _ledgerRefreshKey++;
    });
    _fetchStudentData();
  }

  Future<void> _openTopUpDialog() async {
    if (_student == null) return;
    final added = await TopUpDialog.show(context, _student!);
    if (added == true) _refreshLedger();
  }

  Future<void> _openRefundDialog() async {
    final cs = Theme.of(context).colorScheme;
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final confirmed = await showMagicSheet<bool>(
      context,
      title: 'Возврат средств',
      subtitle: 'Сумма спишется с личного счёта клиента',
      icon: Icons.undo_rounded,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: amountCtrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _inputDecoration(cs, label: 'Сумма (₽)', isDense: true),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: descCtrl,
            decoration: _inputDecoration(
              cs,
              label: 'Комментарий',
              hint: 'Например: возврат за отменённые занятия',
              isDense: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            backgroundColor: cs.error,
            foregroundColor: cs.onError,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
          child: const Text('Вернуть'),
        ),
      ],
    );
    final amount = num.tryParse(amountCtrl.text.trim().replaceAll(',', '.'));
    final description = descCtrl.text.trim();
    amountCtrl.dispose();
    descCtrl.dispose();
    if (confirmed != true) return;
    if (amount == null || amount <= 0) {
      if (mounted) {
        MagicToast.show(
          context,
          'Введите корректную сумму',
          type: MagicToastType.danger,
        );
      }
      return;
    }
    try {
      await ref
          .read(magicCrmServiceProvider)
          .createAdjustment(
            studentId: _studentId,
            kind: 'refund',
            amount: amount,
            description: description.isEmpty ? null : description,
          );
      _dirty = true;
      _refreshLedger();
      if (mounted) {
        MagicToast.show(
          context,
          'Возврат оформлен',
          type: MagicToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        MagicToast.show(
          context,
          'Ошибка возврата',
          detail: '$e',
          type: MagicToastType.danger,
        );
      }
    }
  }

  /// Возраст «N лет». Считает **сервер** (`age.ts`): дата рождения, если она
  /// есть, иначе вписанное руками число. Здесь только подпись — правило одно
  /// для лида и ученика, и две копии разъехались бы.
  String? _ageLabel() {
    Map<String, dynamic>? source;
    if (_mode.hasStudentHalf && _student != null && _student!['age'] != null) {
      source = _student;
    }
    source ??= _leadData['age'] != null ? _leadData : null;
    if (source == null) return null;

    final years = (source['age'] as num?)?.toInt();
    if (years == null) return null;
    // Младенцу «0 лет» — не ответ. Сервер отдаёт месяцы только для
    // посчитанного из даты рождения возраста, у вписанного руками их нет.
    final months = (source['age_months'] as num?)?.toInt();
    if (years == 0 && months != null) return _monthsLabel(months);
    return '$years ${_pluralRu(years, 'год', 'года', 'лет')}';
  }

  String _monthsLabel(int months) =>
      '$months ${_pluralRu(months, 'месяц', 'месяца', 'месяцев')}';

  /// Русское склонение по числу: 1 год / 2 года / 5 лет, с оговоркой на 11–14.
  String _pluralRu(int n, String one, String few, String many) {
    final mod100 = n % 100;
    final mod10 = n % 10;
    if (mod100 >= 11 && mod100 <= 14) return many;
    if (mod10 == 1) return one;
    if (mod10 >= 2 && mod10 <= 4) return few;
    return many;
  }

  /// Дата обращения. Берём разрешённое сервером `appeal_at` (исходная дата из
  /// HolliHop → иначе момент, когда запись появилась в приложении), а на
  /// `created_at` откатываемся только ради старых ответов без этого поля.
  String? _appealAtLabel(Map<String, dynamic> data) {
    final raw = data['appeal_at'] ?? data['created_at'];
    final dt = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (dt == null) return null;
    return DateFormat('dd.MM.yyyy HH:mm', 'ru').format(dt);
  }

  /// Пояснение к дате: важно отличать настоящую дату из HolliHop от той, что
  /// приложение поставило само, — иначе «01.03.2023» и «сегодня» выглядят
  /// одинаково достоверно.
  String? _appealAtSourceLabel(Map<String, dynamic> data) {
    return switch (data['appeal_at_source']?.toString()) {
      'hollihop' => 'из HolliHop',
      'app' => 'дата появления в приложении',
      _ => null,
    };
  }

  String? _leadCreatedAtLabel() => _appealAtLabel(_leadData);

  Color _studentBalanceColor(ColorScheme cs) {
    final b = _studentBalanceNum;
    if (b == null || b == 0) return cs.onSurfaceVariant;
    return b < 0 ? AppTheme.danger : AppTheme.success;
  }

  // Pill badge for the header («Ученик» / «Лид→Ученик»).
  Widget _buildStudentHeader(ColorScheme cs, StatusRecord curStatus) {
    final contact = _studentContact();
    final converted = _isConverted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.lg,
        AppSpace.md,
        AppSpace.md,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColor.goldSoft,
              borderRadius: BorderRadius.circular(AppRadius.icon),
              border: Border.all(color: AppColor.goldLine),
            ),
            child: Icon(
              converted ? Icons.swap_horiz_rounded : Icons.school_outlined,
              size: 22,
              color: AppColor.gold,
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      _headerBadge(converted ? 'Лид→Ученик' : 'Ученик'),
                      // For a converted client surface BOTH halves: the lead
                      // status (origin) and the student balance.
                      if (converted) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: curStatus.$3,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            curStatus.$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                      if (_balance != null) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Баланс: ${_balance!.balanceRaw} ₽',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: _studentBalanceColor(cs),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _handleClose,
            icon: const Icon(Icons.close_rounded),
            iconSize: 20,
            color: cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
