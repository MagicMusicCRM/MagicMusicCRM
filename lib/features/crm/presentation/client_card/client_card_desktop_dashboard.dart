part of 'client_card.dart';

extension _ClientCardDesktopDashboard on _ClientCardState {
  Widget _buildDesktopIdentitySidebar(
    ColorScheme colors,
    StatusRecord currentStatus,
    List<(IconData, String, String)> tabs,
  ) {
    final contact = _isStudent ? _studentContact() : null;
    final name = contact?.name ?? _clientPresentationLabel;
    final phone = _clientPhone ?? 'Телефон не указан';
    final email = _clientEmail ?? 'Почта не указана';
    final navigation = <(IconData, String, String)>[
      (Icons.dashboard_outlined, 'Обзор', 'overview'),
      (Icons.badge_outlined, 'Данные клиента', 'profile'),
      ...tabs.where((tab) => tab.$3 != 'overview'),
    ];

    return Container(
      key: const Key('client-desktop-identity-sidebar'),
      width: 252,
      color: colors.surface,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 92,
              height: 92,
              decoration: const BoxDecoration(
                color: AppColor.surfaceSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isStudent ? Icons.school_outlined : Icons.person_outline,
                color: AppColor.text3,
                size: 46,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              key: const Key('client-desktop-section-jumps'),
              padding: EdgeInsets.zero,
              children: [
                const _ClientSidebarSectionHeader('ОБЩАЯ ИНФОРМАЦИЯ'),
                const SizedBox(height: 9),
                Text(
                  'Статус',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _isStudent ? 'Ученик' : currentStatus.$2,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColor.actionBlue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                for (final item in navigation)
                  _ClientSidebarLink(
                    key: Key('client-section-jump-${item.$3}'),
                    icon: item.$1,
                    label: item.$2,
                    selected: _selectedSection == item.$3,
                    onTap: () => _selectSection(item.$3),
                  ),
                const SizedBox(height: 10),
                const _ClientSidebarSectionHeader('КОНТАКТЫ'),
                const SizedBox(height: 9),
                _ClientSidebarValue(label: 'Телефон', value: phone),
                const SizedBox(height: 9),
                _ClientSidebarValue(label: 'Электронная почта', value: email),
                const SizedBox(height: 9),
                _ClientSidebarValue(
                  label: 'Ответственный',
                  value: _responsibleLabel() ?? 'Не назначен',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopOverviewDashboard(
    ColorScheme colors,
    StatusRecord currentStatus, {
    required bool canReadClientFinance,
    required bool canReadSchedule,
    required bool canReadTasks,
  }) {
    final note =
        (_workspaceInternalNoteDraft?.body ?? _internalNote?.body ?? '').trim();
    final responsible = _responsibleLabel() ?? 'Не назначен';
    final disciplines = _disciplinesForEntity(
      _isStudent ? 'students' : 'leads',
    );
    final activeSubscription = _subscriptions.isEmpty
        ? null
        : _subscriptions.first;
    final nextLesson = _nextClientLesson();
    final branch = _desktopBranchLabel();
    final taskCount = _list(_leadCard?['tasks']).length;

    return Column(
      key: const Key('client-desktop-selected-overview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 78,
          child: _ClientOverviewPanel(
            key: const Key('client-overview-note'),
            colors: colors,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const Icon(
                  Icons.sticky_note_2_outlined,
                  color: AppColor.gold,
                  size: 19,
                ),
                const SizedBox(width: 10),
                const Text(
                  'Важная заметка',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _internalContextLoading
                        ? 'Загрузка…'
                        : _internalContextError != null
                        ? 'Не удалось загрузить заметку'
                        : note.isEmpty
                        ? 'Не заполнена'
                        : note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: note.isEmpty
                          ? colors.onSurfaceVariant
                          : colors.onSurface,
                    ),
                  ),
                ),
                TextButton.icon(
                  key: const Key('client-overview-edit-note'),
                  onPressed: _canWriteClient
                      ? () => _selectSection('profile')
                      : null,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Изменить'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 250,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: _ClientOverviewPanel(
                  key: const Key('client-overview-core'),
                  colors: colors,
                  title: 'ИНФОРМАЦИЯ О КЛИЕНТЕ',
                  action: IconButton(
                    tooltip: 'Редактировать данные клиента',
                    onPressed: () => _selectSection('profile'),
                    icon: const Icon(Icons.edit_outlined, size: 15),
                  ),
                  child: Column(
                    children: [
                      _ClientOverviewDataRow(
                        label: 'Статус',
                        value: _isStudent ? 'Ученик' : currentStatus.$2,
                      ),
                      _ClientOverviewDataRow(label: 'Филиал', value: branch),
                      _ClientOverviewDataRow(
                        label: 'Ответственный',
                        value: responsible,
                      ),
                      _ClientOverviewDataRow(
                        label: 'Направления',
                        value: disciplines.isEmpty
                            ? 'Не указаны'
                            : disciplines.join(', '),
                      ),
                      _ClientOverviewDataRow(
                        label: 'Обращение',
                        value:
                            (_mode.hasStudentHalf && !_mode.hasLeadHalf
                                ? _student == null
                                      ? null
                                      : _appealAtLabel(_student!)
                                : _leadCreatedAtLabel()) ??
                            'Не указано',
                        last: true,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _ClientOverviewPanel(
                  key: const Key('client-overview-subscription'),
                  colors: colors,
                  title: 'РАБОЧИЕ ДАННЫЕ',
                  action: IconButton(
                    tooltip: 'Открыть связанные данные',
                    onPressed: () => _selectSection(
                      _isStudent ? 'subscriptions' : 'progress',
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 15),
                  ),
                  child: Column(
                    key: const Key('client-overview-next-lesson'),
                    children: [
                      _ClientOverviewDataRow(
                        label: _isStudent ? 'Абонемент' : 'Пробные',
                        value: _isStudent
                            ? !canReadClientFinance
                                  ? 'Скрыто правами'
                                  : activeSubscription == null
                                  ? 'Активного нет'
                                  : activeSubscription.packageName ??
                                        activeSubscription.type ??
                                        'Активный'
                            : '${_list(_leadCard?['trials']).length}',
                      ),
                      _ClientOverviewDataRow(
                        label: 'Ближайшее занятие',
                        value: nextLesson?.$1 ?? 'Не запланировано',
                      ),
                      _ClientOverviewDataRow(
                        label: 'Преподаватель / место',
                        value: nextLesson?.$2 ?? 'Не указано',
                      ),
                      _ClientOverviewDataRow(
                        label: 'Задачи',
                        value: taskCount == 0 ? 'Нет открытых' : '$taskCount',
                      ),
                      _ClientOverviewDataRow(
                        label: 'Связи',
                        value: 'Контакты и пользователи',
                        last: true,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 250,
          child: _ClientOverviewPanel(
            key: const Key('client-overview-lessons'),
            colors: colors,
            title: 'ЗАНЯТИЯ (ВСЕГО ${_lessons.length})',
            action: TextButton.icon(
              onPressed: canReadSchedule
                  ? () => _selectSection('lessons')
                  : null,
              icon: const Icon(Icons.calendar_month_outlined, size: 16),
              label: const Text('Расписание'),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isStudent && activeSubscription != null) ...[
                  _buildDesktopSubscriptionBand(
                    colors,
                    activeSubscription,
                    canReadClientFinance,
                  ),
                  const SizedBox(height: 6),
                ],
                Expanded(child: _buildDesktopLessonRows(colors)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _desktopBranchLabel() {
    final direct = _nonEmpty(
      _student?['branch_name'] ?? _leadData['branch_name'],
    );
    if (direct != null) return direct;
    final branchId = _clientBranchId;
    if (branchId == null) return 'Не указан';
    for (final branch in _branches) {
      if (branch['id']?.toString() == branchId) {
        return _nonEmpty(branch['name']) ?? 'Не указан';
      }
    }
    return 'Не указан';
  }

  Widget _buildDesktopSubscriptionBand(
    ColorScheme colors,
    Subscription? subscription,
    bool canReadClientFinance,
  ) {
    if (!canReadClientFinance) {
      return Container(
        padding: const EdgeInsets.all(10),
        color: AppColor.surfaceSoft,
        child: Text(
          'Финансовые данные скрыты правами доступа',
          style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
        ),
      );
    }
    if (subscription == null) {
      return const _ClientEmptyOverview(message: 'Активного абонемента нет');
    }
    final total = subscription.lessonsTotal;
    final left = (total - subscription.lessonsUsed).clamp(0, total);
    final name = subscription.packageName ?? subscription.type ?? 'Абонемент';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      color: AppColor.surfaceSoft,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_compactNumber(left)} из ${_compactNumber(total)} занятий осталось',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 150,
            child: LinearProgressIndicator(
              value: total <= 0 ? 0 : (left / total).clamp(0, 1).toDouble(),
              minHeight: 5,
              color: AppColor.actionBlue,
              backgroundColor: colors.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopLessonRows(ColorScheme colors) {
    final rows = [..._lessons]
      ..sort((left, right) {
        final leftAt = DateTime.tryParse(left.scheduledAt ?? '');
        final rightAt = DateTime.tryParse(right.scheduledAt ?? '');
        if (leftAt == null) return 1;
        if (rightAt == null) return -1;
        return rightAt.compareTo(leftAt);
      });
    final visible = rows.take(3).toList(growable: false);
    if (visible.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: _ClientEmptyOverview(message: 'Занятий пока нет'),
      );
    }
    return Column(
      children: [
        for (var index = 0; index < visible.length; index++) ...[
          _ClientDesktopLessonRow(lesson: visible[index]),
          if (index < visible.length - 1)
            Divider(height: 1, color: colors.outlineVariant),
        ],
      ],
    );
  }
}

class _ClientOverviewPanel extends StatelessWidget {
  const _ClientOverviewPanel({
    super.key,
    required this.colors,
    required this.child,
    this.title,
    this.action,
    this.padding = const EdgeInsets.all(12),
  });

  final ColorScheme colors;
  final String? title;
  final Widget? action;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: title == null
          ? Padding(padding: padding, child: child)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 34,
                  color: AppColor.surfaceSoft,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title!,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.25,
                          ),
                        ),
                      ),
                      ?action,
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(padding: padding, child: child),
                ),
              ],
            ),
    );
  }
}

class _ClientOverviewDataRow extends StatelessWidget {
  const _ClientOverviewDataRow({
    required this.label,
    required this.value,
    this.last = false,
  });

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          border: last
              ? null
              : Border(bottom: BorderSide(color: colors.outlineVariant)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 104,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClientDesktopLessonRow extends StatelessWidget {
  const _ClientDesktopLessonRow({required this.lesson});

  final Lesson lesson;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final scheduled = DateTime.tryParse(lesson.scheduledAt ?? '');
    final teacher =
        lesson.teacherName ??
        lesson.teachers?['first_name']?.toString() ??
        'Преподаватель не указан';
    final place = [
      lesson.branchName ?? lesson.branches?['name']?.toString(),
      lesson.roomName ?? lesson.rooms?['name']?.toString(),
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' · ');
    return SizedBox(
      height: 39,
      child: Row(
        children: [
          SizedBox(
            width: 118,
            child: Text(
              scheduled == null
                  ? 'Дата не указана'
                  : DateFormat(
                      'd MMM, HH:mm',
                      'ru',
                    ).format(scheduled.toLocal()),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              teacher,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              place.isEmpty ? 'Место не указано' : place,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          ),
          _ClientDesktopStatusPill(
            color: lesson.status == 'completed'
                ? AppTheme.success
                : AppColor.gold,
            label: _formatStatus(lesson.status),
          ),
        ],
      ),
    );
  }
}

class _ClientDesktopStatusPill extends StatelessWidget {
  const _ClientDesktopStatusPill({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(AppRadius.chip),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );
}

class _ClientSidebarSectionHeader extends StatelessWidget {
  const _ClientSidebarSectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    color: AppColor.surfaceSoft,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      ),
    ),
  );
}

class _ClientSidebarLink extends StatelessWidget {
  const _ClientSidebarLink({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: Row(
        children: [
          Icon(
            icon,
            size: 13,
            color: selected ? AppColor.actionBlue : AppColor.text3,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: AppColor.actionBlue,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ClientSidebarValue extends StatelessWidget {
  const _ClientSidebarValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 10.5, color: AppColor.text3),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11.5),
      ),
    ],
  );
}

class _ClientEmptyOverview extends StatelessWidget {
  const _ClientEmptyOverview({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      message,
      style: TextStyle(
        fontSize: 12,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
