part of 'client_card.dart';

extension _ClientCardAtGlance on _ClientCardState {
  Widget _buildDesktopAtGlance(ColorScheme colors) {
    final note =
        (_workspaceInternalNoteDraft?.body ?? _internalNote?.body ?? '').trim();
    final nextLesson = _nextClientLesson();
    final lessonBalance = _commerceStudent?.lessonBalance;
    final available = lessonBalance == null
        ? 'Нет данных'
        : '${_compactNumber(lessonBalance.available)} занятий';
    final debt = lessonBalance?.debts.fold<BigInt>(
      BigInt.zero,
      (sum, item) => sum + item.amountMinor,
    );
    final financeDetails = [
      if (_balance != null) 'Счёт: ${_balance!.balanceRaw} ₽',
      if (debt != null && debt > BigInt.zero)
        'Задолженность: ${formatPaymentMinor(debt, currencyCode: 'RUB')}'
      else if (lessonBalance != null)
        'Задолженности нет',
    ].join('\n');
    final responsible = _responsibleLabel();
    final contacts = [
      if ((_clientPhone ?? '').trim().isNotEmpty) _clientPhone!.trim(),
      if ((_clientEmail ?? '').trim().isNotEmpty) _clientEmail!.trim(),
      if (responsible != null) 'Ответственный: $responsible',
    ];
    final tiles = <Widget>[
      _ClientAtGlanceTile(
        key: const Key('client-at-glance-note'),
        icon: Icons.sticky_note_2_outlined,
        title: 'Важная заметка',
        value: note.isEmpty ? 'Заметка не заполнена' : note,
        details: note.isEmpty
            ? 'Добавьте рабочий контекст, который должен быть виден сразу.'
            : 'Внутренняя заметка команды',
        actionLabel: note.isEmpty ? 'Добавить' : 'Открыть',
        onTap: () => _selectSection('overview'),
      ),
      _ClientAtGlanceTile(
        key: const Key('client-at-glance-next-lesson'),
        icon: Icons.event_available_outlined,
        title: 'Ближайшее занятие',
        value: nextLesson?.$1 ?? 'Не запланировано',
        details: nextLesson?.$2 ?? 'Откройте расписание для новой записи.',
        actionLabel: 'К занятиям',
        onTap: () => _selectSection('lessons'),
      ),
      if (_isStudent)
        _ClientAtGlanceTile(
          key: const Key('client-at-glance-finance'),
          icon: Icons.account_balance_wallet_outlined,
          title: 'Абонемент и баланс',
          value: available,
          details: financeDetails.isEmpty
              ? 'Финансовая сводка ещё загружается.'
              : financeDetails,
          actionLabel: 'К оплатам',
          onTap: () => _selectSection(
            _explicitFinanceAccess == false ? 'lessons' : 'payments',
          ),
        )
      else
        _ClientAtGlanceTile(
          key: const Key('client-at-glance-stage'),
          icon: Icons.trending_up_rounded,
          title: 'Работа с обращением',
          value: _leadData['status_name']?.toString().trim().isNotEmpty == true
              ? _leadData['status_name'].toString()
              : 'Текущий этап в карточке',
          details: 'Пробные занятия, задачи и история обращения.',
          actionLabel: 'К прогрессу',
          onTap: () => _selectSection('progress'),
        ),
      _ClientAtGlanceTile(
        key: const Key('client-at-glance-contacts'),
        icon: Icons.contact_phone_outlined,
        title: 'Контакты и ответственный',
        value: contacts.isEmpty ? 'Контакты не заполнены' : contacts.first,
        details: contacts.length > 1
            ? contacts.skip(1).join('\n')
            : 'Семья и связанные пользователи — в разделе контактов.',
        actionLabel: 'К контактам',
        onTap: () => _selectSection('contacts'),
      ),
    ];
    return Container(
      key: const Key('client-at-glance'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Главное по клиенту',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Рабочая сводка и переходы к полным данным без поиска по карточке.',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpace.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900
                  ? 4
                  : constraints.maxWidth >= 520
                  ? 2
                  : 1;
              const gap = AppSpace.md;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final tile in tiles) SizedBox(width: width, child: tile),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  (String, String)? _nextClientLesson() {
    final candidates = <(DateTime, String)>[];
    for (final lesson in _lessons) {
      if ({'cancelled', 'canceled'}.contains(lesson.status) ||
          lesson.lifecycleState == 'archived') {
        continue;
      }
      final at = DateTime.tryParse(lesson.scheduledAt ?? '');
      if (at == null || at.isBefore(DateTime.now())) continue;
      final details = [
        lesson.teacherName ?? lesson.teachers?['first_name']?.toString(),
        lesson.branchName ?? lesson.branches?['name']?.toString(),
        lesson.roomName ?? lesson.rooms?['name']?.toString(),
      ].whereType<String>().where((item) => item.trim().isNotEmpty).join(' · ');
      candidates.add((at, details));
    }
    for (final raw in _list(_leadCard?['trials'])) {
      final at = DateTime.tryParse(
        (raw['scheduled_at'] ?? raw['scheduledAt'] ?? '').toString(),
      );
      if (at == null || at.isBefore(DateTime.now())) continue;
      final details = [
        raw['teacher_name'] ?? raw['teacherName'],
        raw['branch_name'] ?? raw['branchName'],
        raw['room_name'] ?? raw['roomName'],
      ].whereType<String>().where((item) => item.trim().isNotEmpty).join(' · ');
      candidates.add((at, details));
    }
    if (candidates.isEmpty) return null;
    candidates.sort((left, right) => left.$1.compareTo(right.$1));
    final next = candidates.first;
    return (
      DateFormat('EEE, d MMM · HH:mm', 'ru').format(next.$1.toLocal()),
      next.$2.isEmpty ? 'Детали занятия откроются в расписании.' : next.$2,
    );
  }

  String _compactNumber(num value) => value == value.truncate()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
}

class _ClientAtGlanceTile extends StatelessWidget {
  const _ClientAtGlanceTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.details,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final String details;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Container(
          height: 160,
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: AppColor.gold),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  details,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                actionLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColor.gold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
