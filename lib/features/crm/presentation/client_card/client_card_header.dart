part of 'client_card.dart';

extension _ClientCardHeader on _ClientCardState {
  Widget _buildEditableClientName() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(
        child: Text(
          [
                _isStudent &&
                        _clientFirstName == null &&
                        _clientLastName == null
                    ? _studentContact().name
                    : _clientFirstName,
                _clientLastName,
                _storedCustomField('middleName'),
              ]
              .whereType<String>()
              .where((part) => part.trim().isNotEmpty)
              .join(' '),
          key: const Key('client-header-name'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ),
      if (_canWriteClient)
        IconButton(
          key: const Key('client-edit-name'),
          tooltip: 'Изменить ФИО',
          onPressed: _editClientName,
          icon: const Icon(Icons.edit_outlined, color: AppColor.gold, size: 21),
          visualDensity: VisualDensity.compact,
        ),
    ],
  );

  Future<void> _editClientName() async {
    if (!_canWriteClient) return;
    final entity = _isStudent ? 'students' : 'leads';
    final middleField = _customFieldSchema
        .where(
          (f) =>
              f.entity == entity &&
              f.key == 'middleName' &&
              f.placements.contains('edit'),
        )
        .firstOrNull;
    final result =
        await showMagicDialog<({String first, String last, String? middle})>(
          context: context,
          builder: (_) => _ClientNameEditor(
            first: _clientFirstName ?? '',
            last: _clientLastName ?? '',
            middle: _storedCustomField('middleName') ?? '',
            editMiddle: middleField != null,
            requireMiddle: middleField?.required ?? false,
          ),
        );
    if (!mounted || result == null || !_canWriteClient) return;
    _updateClientCore('firstName', result.first);
    _updateClientCore('lastName', result.last.isEmpty ? null : result.last);
    if (middleField != null) {
      _updateCustomDataForEntity(
        entity,
        'middleName',
        result.middle?.isEmpty == true ? null : result.middle,
      );
    }
    // A separate editor committed these values; update any mounted form fields.
    _emitState(() => _editorEpoch++);
  }

  /// В чёрном ли списке клиент — по любой из половин карточки. Сервер отдаёт
  /// флаг на каждой (см. blacklist.ts); достаточно одной, чтобы это был бан.
  bool get _isBlacklisted =>
      _student?['blacklisted'] == true || _leadData['blacklisted'] == true;

  String? get _blacklistReason {
    final fromStudent = _student?['blacklist_reason']?.toString();
    if (fromStudent != null && fromStudent.trim().isNotEmpty) {
      return fromStudent;
    }
    final fromLead = _leadData['blacklist_reason']?.toString();
    if (fromLead != null && fromLead.trim().isNotEmpty) return fromLead;
    return null;
  }

  /// Красная плашка над карточкой забаненного клиента.
  ///
  /// ✔ Решение владельца 17.07: «карточка клиента помечается красным цветом
  /// предупреждения». Плашкой, а не одной лишь подкраской заголовка: то, что
  /// человеку закрыты чаты, должно быть видно раньше, чем сотрудник начнёт
  /// гадать, почему клиент молчит.
  Widget _buildBlacklistBanner(ColorScheme cs) {
    final reason = _blacklistReason;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        0,
        AppSpace.xl,
        AppSpace.md,
      ),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.55)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.block_rounded, size: 18, color: AppTheme.danger),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Клиент в чёрном списке',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.danger,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  reason ?? 'Причина не указана',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Text(
                  'Писать в чаты школы и администрации он не может.',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs, StatusRecord curStatus) {
    final banned = _isBlacklisted;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpace.xl,
        widget.routed ? 8 : AppSpace.lg,
        AppSpace.md,
        widget.routed ? 6 : AppSpace.md,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: banned
                  ? AppTheme.danger.withValues(alpha: 0.12)
                  : AppColor.goldSoft,
              borderRadius: BorderRadius.circular(AppRadius.icon),
              border: Border.all(
                color: banned
                    ? AppTheme.danger.withValues(alpha: 0.55)
                    : AppColor.goldLine,
              ),
            ),
            child: Icon(
              banned ? Icons.block_rounded : Icons.person_outline_rounded,
              size: 22,
              color: banned ? AppTheme.danger : AppColor.gold,
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildEditableClientName(),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: curStatus.$3,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          [
                            'Клиент · Лид · ${curStatus.$2}',
                            ?_ageLabel(),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!widget.routed)
            IconButton(
              tooltip: 'Закрыть форму',
              onPressed: _handleClose,
              icon: const Icon(Icons.close_rounded),
              iconSize: 20,
              color: cs.onSurfaceVariant,
            ),
        ],
      ),
    );
  }

  Widget _buildTabBar(
    ColorScheme cs,
    List<(IconData, String, String)> tabs, {
    required int selectedIndex,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.lg,
        vertical: AppSpace.sm,
      ),
      child: MagicDesktopScrollbar(
        axis: Axis.horizontal,
        builder: (context, controller) => SingleChildScrollView(
          controller: controller,
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpace.sm),
                _buildTabChip(cs, i, tabs, selectedIndex: selectedIndex),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabChip(
    ColorScheme cs,
    int index,
    List<(IconData, String, String)> tabs, {
    required int selectedIndex,
  }) {
    final selected = selectedIndex == index;
    final (icon, label, section) = tabs[index];
    return Material(
      color: selected ? AppColor.goldSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: InkWell(
        key: Key('client-section-tab-$section'),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        onTap: () => _selectSection(section),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(
              color: selected ? AppColor.goldLine : cs.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? AppColor.gold : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColor.gold : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionBar(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.md,
        AppSpace.xl,
        AppSpace.lg,
      ),
      // Wrap so the action buttons reflow onto a second line on narrow
      // (mobile) dialog widths instead of overflowing on the right.
      child: Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ClientArchiveButton(
              entityType: 'lead',
              entityId: _leadId,
              allowed: clientRoleCanArchive(_currentActorRole() ?? ''),
              onArchived: () => _closeCard(true),
            ),
            // «Прикрепить к ученику» (§1 спеки) остаётся отдельной lifecycle-
            // командой; выдачей абонемента владеет профильная секция.
            // Раньше связать можно было только пару, которую нашёл автоподбор
            // дублей — если он молчал, привязать было нельзя вовсе.
            if (!_isConverted && !_hasLinkedStudent)
              OutlinedButton.icon(
                onPressed: _saving || _converting ? null : _linkExistingStudent,
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.onSurface,
                  side: BorderSide(color: cs.outlineVariant),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                ),
                icon: const Icon(Icons.link_rounded, size: 18),
                label: const Text('Прикрепить к ученику'),
              ),
            // #6: вместо записи на пробное из карточки — переход в расписание
            // (на ближайшее занятие клиента, иначе на сегодня).
            OutlinedButton.icon(
              onPressed: _saving || _converting ? null : _openScheduleFromCard,
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.onSurface,
                side: BorderSide(color: cs.outlineVariant),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
              ),
              icon: const Icon(Icons.calendar_month_rounded, size: 18),
              label: const Text('Открыть в расписании'),
            ),
            TextButton(
              onPressed: _saving || _converting ? null : _handleClose,
              style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
              child: Text(widget.routed ? 'Назад' : 'Закрыть'),
            ),
            _buildAutoSaveControl(cs, enabled: !_converting),
          ],
        ),
      ),
    );
  }
}

class _ClientNameEditor extends StatefulWidget {
  const _ClientNameEditor({
    required this.first,
    required this.last,
    required this.middle,
    required this.editMiddle,
    required this.requireMiddle,
  });
  final String first, last, middle;
  final bool editMiddle, requireMiddle;
  @override
  State<_ClientNameEditor> createState() => _ClientNameEditorState();
}

class _ClientNameEditorState extends State<_ClientNameEditor> {
  final _form = GlobalKey<FormState>();
  late final _first = TextEditingController(text: widget.first);
  late final _last = TextEditingController(text: widget.last);
  late final _middle = TextEditingController(text: widget.middle);

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _middle.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(context, (
      first: _first.text.trim(),
      last: _last.text.trim(),
      middle: widget.editMiddle ? _middle.text.trim() : null,
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Изменить ФИО'),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('client-name-last'),
              controller: _last,
              decoration: const InputDecoration(labelText: 'Фамилия'),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('client-name-first'),
              controller: _first,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Имя *'),
              textCapitalization: TextCapitalization.words,
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Введите имя' : null,
              textInputAction: widget.editMiddle
                  ? TextInputAction.next
                  : TextInputAction.done,
              onFieldSubmitted: widget.editMiddle ? null : (_) => _submit(),
            ),
            if (widget.editMiddle) ...[
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('client-name-middle'),
                controller: _middle,
                decoration: InputDecoration(
                  labelText: widget.requireMiddle ? 'Отчество *' : 'Отчество',
                ),
                textCapitalization: TextCapitalization.words,
                validator: (value) =>
                    widget.requireMiddle &&
                        (value == null || value.trim().isEmpty)
                    ? 'Введите отчество'
                    : null,
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        key: const Key('client-name-apply'),
        onPressed: _submit,
        child: const Text('Применить'),
      ),
    ],
  );
}
