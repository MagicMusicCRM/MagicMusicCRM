part of 'reports_widget.dart';

class _ReportsError extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;

  const _ReportsError({required this.error, required this.onRetry});

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
              color: AppColor.danger,
              size: 42,
            ),
            const SizedBox(height: 10),
            Text(
              'Не удалось загрузить отчеты',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              userErrorMessage(error, fallback: 'Не удалось загрузить отчёт.'),
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

class _ActivityLogTab extends ConsumerStatefulWidget {
  const _ActivityLogTab({required this.filter});

  final DashboardFilter filter;

  @override
  ConsumerState<_ActivityLogTab> createState() => _ActivityLogTabState();
}

class _ActivityLogTabState extends ConsumerState<_ActivityLogTab> {
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  bool _loading = true;
  bool _refreshing = false;
  int _loadSequence = 0;
  Object? _loadError;
  String _entityType = 'all';
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _loadActivity();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ActivityLogTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filter != widget.filter) {
      _loadActivity(preserveContent: true);
    }
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _loadActivity(preserveContent: true);
    });
  }

  Future<void> _loadActivity({bool preserveContent = false}) async {
    final sequence = ++_loadSequence;
    setState(() {
      if (preserveContent && _items.isNotEmpty) {
        _refreshing = true;
      } else {
        _loading = true;
      }
      _loadError = null;
    });
    try {
      final filter = widget.filter.apiFilter;
      final items = await ref
          .read(magicCrmServiceProvider)
          .listActivityLog(
            q: _searchCtrl.text,
            entityType: _entityType == 'all' ? null : _entityType,
            branchId: filter['branchId']?.toString(),
            from: filter['from']?.toString(),
            to: filter['to']?.toString(),
            limit: 100,
          );
      if (!mounted || sequence != _loadSequence) return;
      setState(() {
        _items = items;
        _loading = false;
        _refreshing = false;
      });
    } catch (e) {
      if (mounted && sequence == _loadSequence) {
        setState(() {
          if (!preserveContent || _items.isEmpty) _loadError = e;
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  void _setFilter(void Function() update) {
    setState(update);
    _loadActivity(preserveContent: true);
  }

  /// «Активность» used to be a dead-end list. Every row carries the entity it
  /// touched (entity_type + entity_id — already in the payload), so a tap now
  /// opens that client / lesson / profile. `audit_events.entity_type` is a free
  /// string, so unknown kinds are simply non-tappable (see [_activityOpenable]).
  Future<void> _openActivityEntity(Map<String, dynamic> item) async {
    final entityType = item['entity_type']?.toString();
    final entityId = item['entity_id']?.toString();
    if (entityId == null || entityId.trim().isEmpty) return;
    try {
      final transition = const ContextTransitionRegistry().create(
        source: ContextSourceType.audit,
        target: ContextTargetType.changedEntity,
        entityId: entityId,
        sourceState: ContextViewState(
          filters: {
            ...widget.filter.toContextViewState().filters,
            'entityType': _entityType,
            'query': _searchCtrl.text,
          },
        ),
        rawEntityType: entityType,
      );
      await openEntityLink(context, ref, transition.target);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorMessage(e, fallback: 'Не удалось открыть запись.'),
          ),
        ),
      );
    }
  }

  static bool _activityOpenable(Map<String, dynamic> item) {
    const openable = {
      'student',
      'lead',
      'lesson',
      'profile',
      'staff',
      'group',
      'teacher',
    };
    final id = item['entity_id']?.toString();
    return id != null &&
        id.trim().isNotEmpty &&
        openable.contains(item['entity_type']?.toString());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340, minWidth: 240),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Поиск действий',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ),
              _ReportFilterDropdown(
                label: 'Объект',
                value: _entityType,
                icon: Icons.link_rounded,
                options: const [
                  ('all', 'Все объекты'),
                  ('student', 'Ученики'),
                  ('lead', 'Лиды'),
                  ('teacher', 'Учителя'),
                  ('staff', 'Сотрудники'),
                  ('lesson', 'Занятия'),
                  ('task', 'Задачи'),
                ],
                onChanged: (value) => _setFilter(() => _entityType = value),
              ),
              if (_searchCtrl.text.isNotEmpty || _entityType != 'all')
                TextButton.icon(
                  onPressed: () {
                    _searchDebounce?.cancel();
                    setState(() {
                      _searchCtrl.clear();
                      _searchDebounce?.cancel();
                      _entityType = 'all';
                    });
                    _loadActivity(preserveContent: true);
                  },
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Сбросить'),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 2,
          child: _refreshing
              ? const LinearProgressIndicator(minHeight: 2)
              : null,
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColor.gold),
                )
              : _loadError != null
              ? _ReportsError(error: _loadError, onRetry: () => _loadActivity())
              : _items.isEmpty
              ? Center(
                  child: Text(
                    'Нет действий за период',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: AppColor.gold,
                  onRefresh: () => _loadActivity(preserveContent: true),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _ActivityLogTile(
                      item: _items[index],
                      onOpen: _activityOpenable(_items[index])
                          ? () => _openActivityEntity(_items[index])
                          : null,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _ActivityLogTile extends StatelessWidget {
  final Map<String, dynamic> item;
  // Non-null when the row's entity can be opened; a tap then routes to it.
  final VoidCallback? onOpen;

  const _ActivityLogTile({required this.item, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final createdAt = DateTime.tryParse(item['created_at']?.toString() ?? '');
    final dateText = createdAt == null
        ? ''
        : DateFormat('d MMM, HH:mm', 'ru').format(createdAt.toLocal());
    final actor = item['actor_name']?.toString().trim();
    final description = item['description']?.toString().trim();
    final action = item['action']?.toString() ?? '';
    final entityType = item['entity_type']?.toString();
    final historyType = item['history_type']?.toString();
    final role = item['actor_role']?.toString();

    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant.withAlpha(90),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _activityColor(action).withAlpha(28),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _activityIcon(action),
                  color: _activityColor(action),
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            description == null || description.isEmpty
                                ? _activityLabel(action)
                                : description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (dateText.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Text(
                            dateText,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (actor != null && actor.isNotEmpty)
                          _ReportTag(
                            label: actor,
                            color: AppTheme.secondaryGold,
                          ),
                        if (role != null && role.isNotEmpty)
                          _ReportTag(
                            label: _activityRoleLabel(role),
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        if (entityType != null && entityType.isNotEmpty)
                          _ReportTag(
                            label: _activityEntityLabel(entityType),
                            color: AppColor.gold,
                          ),
                        if (historyType != null && historyType.isNotEmpty)
                          _ReportTag(
                            label: _activityHistoryLabel(historyType),
                            color: AppColor.success,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onOpen != null)
                Padding(
                  padding: const EdgeInsets.only(left: 6, top: 2),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportFilterDropdown extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;

  const _ReportFilterDropdown({
    required this.label,
    required this.value,
    required this.icon,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = options.any((option) => option.$1 == value)
        ? value
        : options.first.$1;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220, minWidth: 170),
      child: DropdownButtonFormField<String>(
        menuMaxHeight: 256,
        key: ValueKey('$label-$normalized'),
        initialValue: normalized,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        items: options
            .map(
              (option) => DropdownMenuItem<String>(
                value: option.$1,
                child: Text(option.$2, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

class _ReportTag extends StatelessWidget {
  final String label;
  final Color color;

  const _ReportTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

IconData _activityIcon(String action) {
  if (action.contains('delete')) return Icons.delete_outline_rounded;
  if (action.contains('update') || action.contains('updated')) {
    return Icons.edit_note_rounded;
  }
  if (action.contains('created') || action.contains('create')) {
    return Icons.add_circle_outline_rounded;
  }
  return Icons.history_rounded;
}

Color _activityColor(String action) {
  if (action.contains('delete')) return AppTheme.danger;
  if (action.contains('update') || action.contains('updated')) {
    return AppTheme.secondaryGold;
  }
  if (action.contains('created') || action.contains('create')) {
    return AppTheme.success;
  }
  return AppTheme.primaryGold;
}

String _activityLabel(String action) {
  if (action.contains('student')) return 'Изменение ученика';
  if (action.contains('lead')) return 'Изменение лида';
  if (action.contains('lesson')) return 'Изменение занятия';
  if (action.contains('task')) return 'Изменение задачи';
  if (action.contains('comment')) return 'Комментарий';
  return 'Действие';
}

String _activityEntityLabel(String entityType) {
  return switch (entityType) {
    'student' => 'Ученик',
    'lead' => 'Лид',
    'teacher' => 'Учитель',
    'staff' => 'Сотрудник',
    'lesson' => 'Занятие',
    'task' => 'Задача',
    'comment' => 'Комментарий',
    _ => entityType,
  };
}

String _activityHistoryLabel(String historyType) {
  return switch (historyType) {
    'comment' => 'Комментарий',
    'task' => 'Задача',
    'status' => 'Статус',
    'payment' => 'Платёж',
    'lesson' => 'Занятие',
    _ => historyType,
  };
}

String _activityRoleLabel(String role) {
  return switch (role) {
    'admin' => 'Администратор',
    'system_admin' => 'Администратор системы',
    'manager' => 'Управляющий',
    'director' => 'Директор',
    'teacher' => 'Учитель',
    'client' => 'Клиент',
    _ => role,
  };
}
