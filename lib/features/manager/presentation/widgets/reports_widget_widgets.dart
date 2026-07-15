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

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

/// Returns the first non-null value found under any of [keys] in [map].
/// Used to read analytics responses defensively across camelCase / snake_case.
Object? _pick(Map<String, dynamic>? map, List<String> keys) {
  if (map == null) return null;
  for (final k in keys) {
    final v = map[k];
    if (v != null) return v;
  }
  return null;
}

/// Reads a list of maps from [source] under the first matching key in [keys].
/// Tolerates the response itself being a bare list. Returns [] when missing.
List<Map<String, dynamic>> _readList(
  Map<String, dynamic>? source,
  List<String> keys,
) {
  if (source == null) return const [];
  for (final k in keys) {
    final v = source[k];
    if (v is List) {
      return v.whereType<Map<String, dynamic>>().toList();
    }
  }
  return const [];
}

/// Formats a month label from an ISO date / month string, defensively.
String _financeMonthLabel(Object? raw) {
  final text = raw?.toString() ?? '';
  final parsed = DateTime.tryParse(text);
  if (parsed != null) {
    return DateFormat('LLL yyyy', 'ru').format(parsed);
  }
  return text.isEmpty ? '—' : text;
}

class _MonthData {
  final String month;
  int lessons = 0;
  int completed = 0;
  int newStudents = 0;
  double revenue = 0;
  _MonthData({required this.month});

  factory _MonthData.fromReport(Map<String, dynamic> row) {
    final parsed = DateTime.tryParse(row['month_start']?.toString() ?? '');
    return _MonthData(
        month: parsed == null ? '—' : _shortMonthName(parsed.month),
      )
      ..lessons = int.tryParse('${row['lessons'] ?? 0}') ?? 0
      ..completed = int.tryParse('${row['completed'] ?? 0}') ?? 0
      ..newStudents = int.tryParse('${row['new_students'] ?? 0}') ?? 0
      ..revenue = double.tryParse('${row['revenue'] ?? 0}') ?? 0;
  }

  static String _shortMonthName(int month) {
    const names = [
      'янв',
      'фев',
      'мар',
      'апр',
      'май',
      'июн',
      'июл',
      'авг',
      'сен',
      'окт',
      'ноя',
      'дек',
    ];
    return names[(month - 1).clamp(0, names.length - 1)];
  }
}

class _KpiCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.outlineVariant.withAlpha(90)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared chrome for the KVA-198 analytics cards. Renders a titled v7 surface
/// (matching the card styling used elsewhere in this file) and resolves the
/// loading / error / empty / content states so each builder only supplies its
/// populated body.
class _AnalyticsCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isLoading;
  final bool isError;
  final bool isEmpty;
  final Widget child;

  const _AnalyticsCard({
    required this.title,
    required this.icon,
    required this.isLoading,
    required this.isError,
    required this.isEmpty,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    Widget body;
    if (isLoading) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpace.xl),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: AppColor.gold,
            ),
          ),
        ),
      );
    } else if (isError) {
      body = _AnalyticsCardHint(
        icon: Icons.cloud_off_rounded,
        text: 'Не удалось загрузить',
        color: colors.onSurfaceVariant,
      );
    } else if (isEmpty) {
      body = _AnalyticsCardHint(
        icon: Icons.inbox_outlined,
        text: 'Нет данных за период',
        color: colors.onSurfaceVariant,
      );
    } else {
      body = child;
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.outlineVariant.withAlpha(90)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppColor.gold),
                const SizedBox(width: AppSpace.sm),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            body,
          ],
        ),
      ),
    );
  }
}

class _AnalyticsCardHint extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _AnalyticsCardHint({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 26, color: color),
            const SizedBox(height: AppSpace.sm),
            Text(text, style: TextStyle(color: color, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// A labelled stat row (label on the left, value on the right) used by the
/// data-quality and responsible cards.
class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _StatRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: valueColor ?? colors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _SmallStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _ActivityLogTab extends ConsumerStatefulWidget {
  const _ActivityLogTab();

  @override
  ConsumerState<_ActivityLogTab> createState() => _ActivityLogTabState();
}

class _ActivityLogTabState extends ConsumerState<_ActivityLogTab> {
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  bool _loading = true;
  Object? _loadError;
  String _period = 'week';
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

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _loadActivity();
    });
  }

  Future<void> _loadActivity() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final bounds = _activityBounds(_period);
      final items = await ref
          .read(magicCrmServiceProvider)
          .listActivityLog(
            q: _searchCtrl.text,
            entityType: _entityType == 'all' ? null : _entityType,
            from: bounds.$1,
            to: bounds.$2,
            limit: 100,
          );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e;
          _loading = false;
        });
      }
    }
  }

  void _setFilter(void Function() update) {
    setState(update);
    _loadActivity();
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
                label: 'Период',
                value: _period,
                icon: Icons.event_rounded,
                options: const [
                  ('week', '7 дней'),
                  ('month', 'Месяц'),
                  ('quarter', 'Квартал'),
                ],
                onChanged: (value) => _setFilter(() => _period = value),
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
                    _loadActivity();
                  },
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Сбросить'),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColor.gold),
                )
              : _loadError != null
              ? _ReportsError(error: _loadError, onRetry: _loadActivity)
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
                  onRefresh: _loadActivity,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) =>
                        _ActivityLogTile(item: _items[index]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _ActivityLogTile extends StatelessWidget {
  final Map<String, dynamic> item;

  const _ActivityLogTile({required this.item});

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
                        _ReportTag(label: actor, color: AppTheme.secondaryGold),
                      if (role != null && role.isNotEmpty)
                        _ReportTag(
                          label: _activityRoleLabel(role),
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
          ],
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

(String?, String?) _activityBounds(String period) {
  final now = DateTime.now();
  final todayEnd = DateTime(
    now.year,
    now.month,
    now.day,
  ).add(const Duration(days: 1));
  final from = switch (period) {
    'month' => DateTime(now.year, now.month),
    'quarter' => DateTime(now.year, now.month - 2),
    _ => DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 6)),
  };
  return (from.toUtc().toIso8601String(), todayEnd.toUtc().toIso8601String());
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
