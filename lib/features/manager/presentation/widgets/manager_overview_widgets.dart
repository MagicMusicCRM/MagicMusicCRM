part of 'manager_overview_widget.dart';

class _DashboardHeader extends StatelessWidget {
  final String periodLabel;
  final bool loading;

  const _DashboardHeader({required this.periodLabel, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Сводка',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                periodLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: loading ? 1 : 0,
          child: const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ],
    );
  }
}

class _DashboardFilters extends StatelessWidget {
  final _DashboardPeriod period;
  final String? branchId;
  final List<Map<String, dynamic>> branches;
  final bool branchesLoading;
  final ValueChanged<_DashboardPeriod> onPeriodChanged;
  final ValueChanged<String?> onBranchChanged;

  const _DashboardFilters({
    required this.period,
    required this.branchId,
    required this.branches,
    required this.branchesLoading,
    required this.onPeriodChanged,
    required this.onBranchChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<_DashboardPeriod>(
          segments: _DashboardPeriod.values
              .map(
                (period) =>
                    ButtonSegment(value: period, label: Text(period.label)),
              )
              .toList(),
          selected: {period},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onPeriodChanged(selection.first),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280, minWidth: 220),
          child: DropdownButtonFormField<String>(
            menuMaxHeight: 256,
            key: ValueKey(branchId ?? 'all-branches'),
            initialValue: branchId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Филиал',
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
            hint: Text(branchesLoading ? 'Загрузка...' : 'Все филиалы'),
            items: branches
                .map(
                  (branch) => DropdownMenuItem<String>(
                    value: branch['id']?.toString(),
                    child: Text(
                      branch['name']?.toString() ?? 'Без названия',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: branchesLoading ? null : onBranchChanged,
          ),
        ),
        if (branchId != null)
          TextButton.icon(
            onPressed: () => onBranchChanged(null),
            icon: const Icon(Icons.close_rounded, size: 18),
            label: const Text('Все филиалы'),
          ),
      ],
    );
  }
}

class _AttentionPanel extends StatelessWidget {
  final num overdueTasks;
  final num scheduleIssues;
  final num? debtStudents;

  /// null — у роли нет доступа к общешкольным финансам (KVA-239): строка
  /// «Ожидаемые платежи» скрывается.
  final num? expectedPayments;
  final VoidCallback? onTasksTap;
  final VoidCallback? onScheduleTap;
  final VoidCallback? onDebtsTap;

  const _AttentionPanel({
    required this.overdueTasks,
    required this.scheduleIssues,
    required this.debtStudents,
    required this.expectedPayments,
    required this.onTasksTap,
    required this.onScheduleTap,
    required this.onDebtsTap,
  });

  @override
  Widget build(BuildContext context) {
    final rows = [
      _AttentionRowData(
        icon: Icons.timer_off_rounded,
        label: 'Просроченные задачи',
        value: _count(overdueTasks),
        accent: overdueTasks > 0 ? AppTheme.danger : AppTheme.success,
        onTap: onTasksTap,
      ),
      _AttentionRowData(
        icon: Icons.warning_amber_rounded,
        label: 'Конфликты расписания',
        value: _count(scheduleIssues),
        accent: scheduleIssues > 0 ? AppTheme.danger : AppTheme.success,
        onTap: onScheduleTap,
      ),
      if (debtStudents != null)
        _AttentionRowData(
          icon: Icons.priority_high_rounded,
          label: 'Ученики с долгом',
          value: _count(debtStudents!),
          accent: debtStudents! > 0 ? AppTheme.warning : AppTheme.success,
          onTap: onDebtsTap,
        ),
      if (expectedPayments != null)
        _AttentionRowData(
          icon: Icons.event_available_rounded,
          label: 'Ожидаемые платежи',
          value: _money(expectedPayments),
          accent: AppTheme.secondaryGold,
          onTap: onDebtsTap,
        ),
    ];

    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColor.borderSoft),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Требует внимания',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final rowWidth = constraints.maxWidth >= 780
                    ? (constraints.maxWidth - 10) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: rows
                      .map(
                        (row) => SizedBox(
                          width: rowWidth,
                          child: _AttentionRow(data: row),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  final _AttentionRowData data;

  const _AttentionRow({required this.data});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColor.borderSoft),
          ),
          child: Row(
            children: [
              Icon(data.icon, color: data.accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                data.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: data.accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color accent;
  final String sourceLabel;
  final VoidCallback? onTap;

  const _KpiTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    required this.sourceLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 86,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColor.borderSoft),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withAlpha(28),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: accent,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sourceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardError extends StatelessWidget {
  final VoidCallback onRetry;

  const _DashboardError({required this.onRetry});

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
              size: 48,
            ),
            const SizedBox(height: 8),
            const Text(
              'Не удалось загрузить обзор',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Проверьте подключение и повторите загрузку.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}

class _KpiSpec {
  final String key;
  final String label;
  final IconData icon;
  final Color accent;
  final String sourceLabel;
  final String Function(Object? value) format;
  final VoidCallback? onTap;

  const _KpiSpec({
    required this.key,
    required this.label,
    required this.icon,
    required this.accent,
    required this.sourceLabel,
    required this.format,
    required this.onTap,
  });
}

class _AttentionRowData {
  final IconData icon;
  final String label;
  final String value;
  final Color accent;
  final VoidCallback? onTap;

  const _AttentionRowData({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    required this.onTap,
  });
}

num _asNum(Object? value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? 0;
}

String _count(Object? value) {
  return NumberFormat.decimalPattern('ru').format(_asNum(value).round());
}

String _money(Object? value) {
  return formatPaymentMajor(value ?? 0);
}

String _sourceLabel(Object? source, String fallback) {
  final raw = source?.toString() ?? '';
  if (raw.contains('finance')) return 'Финансы';
  if (raw.contains('expected-payments')) return 'Платежи';
  if (raw.contains('student-balances')) return 'Балансы';
  if (raw.contains('leads')) return 'Лиды';
  if (raw.contains('tasks')) return 'Задачи';
  if (raw.contains('schedule')) return 'Расписание';
  if (raw.contains('activity')) return 'Активность';
  return fallback;
}
