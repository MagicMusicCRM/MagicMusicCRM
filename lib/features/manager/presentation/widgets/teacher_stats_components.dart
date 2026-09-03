part of 'teacher_stats_view.dart';

extension _TeacherStatsViewSections on TeacherStatsView {
  Widget _unitRow(BuildContext context, Map<String, dynamic> unit) {
    final meta = _unitMeta(unit);
    return InkWell(
      onTap: _state.canManageTeacherRates
          ? () => _editUnit(context, unit, meta.isGroup)
          : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _unitSelection(meta),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primaryGold.withAlpha(24),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(meta.typeLabel, style: const TextStyle(fontSize: 11)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    unit['unitName']?.toString() ?? 'Не указано',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (meta.days.isNotEmpty)
                    Text(
                      '${meta.days} · ${controller.integer(unit['completedLessons'])} зан. · '
                      '${controller.integer(unit['payableLessons'])} оплач.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  if (meta.settled > 0) _settledText(context, meta.settled),
                  if (unit['compensationLabel'] != null)
                    Text(
                      unit['compensationLabel'].toString(),
                      style: const TextStyle(fontSize: 12),
                    ),
                  Text(
                    TeacherStatsCompensationSource.label(
                      unit['compensationSource'],
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'По расписанию: ${controller.hours(unit['scheduledHoursTotal'])}',
                  style: const TextStyle(fontSize: 12.5),
                ),
                Text(
                  'Зачтено преподавателю: ${controller.hours(unit['hoursTotal'])}',
                  style: const TextStyle(fontSize: 12.5),
                ),
                Text(
                  'Стандартная ставка: ${controller.rateLabel(unit['rate'])}',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  'Начислено: ${controller.rub(unit['accruedTotal'])}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            _unitActionIcon(meta),
          ],
        ),
      ),
    );
  }

  _TeacherStatsUnitMeta _unitMeta(Map<String, dynamic> unit) {
    final isGroup =
        unit['unitType'] == 'group' || unit['unitType'] == 'group_trial';
    final lessonIds = controller.selectableLessonIdsFor(unit);
    final days = (unit['days'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((day) {
          final date = DateTime.tryParse(day['date']?.toString() ?? '');
          final label = date == null
              ? day['date'].toString()
              : controller.dayLabel(date);
          return '$label (${controller.hours(day['hours'])})';
        })
        .join(', ');
    return _TeacherStatsUnitMeta(
      isGroup: isGroup,
      lessonIds: lessonIds,
      unitKey: lessonIds.isEmpty ? null : lessonIds.first,
      settled: controller.integer(unit['settledLessons']),
      days: days,
      typeLabel: switch (unit['unitType']) {
        'group' => 'Группа',
        'group_trial' => 'Групп. пробный',
        'individual_trial' => 'Индив. пробный',
        _ => 'Индивид.',
      },
    );
  }

  Widget _unitSelection(_TeacherStatsUnitMeta meta) {
    if (!_state.canManageTeacherRates) {
      return const SizedBox(width: 28, height: 28);
    }
    final unitKey = meta.unitKey;
    if (unitKey == null) return const SizedBox(width: 28, height: 28);
    return SizedBox(
      width: 28,
      height: 28,
      child: Checkbox(
        value: _state.selectedUnits.containsKey(unitKey),
        onChanged: _state.applyingRate
            ? null
            : (_) => controller.toggleUnit(unitKey, meta.lessonIds),
      ),
    );
  }

  Widget _unitActionIcon(_TeacherStatsUnitMeta meta) {
    if (meta.settled > 0 && !_state.canManageTeacherRates) {
      return const Row(
        children: [
          SizedBox(width: 4),
          Tooltip(
            message: 'Расчёт зафиксирован и не меняется задним числом',
            child: Icon(Icons.lock_outline_rounded, size: 14),
          ),
        ],
      );
    }
    if (meta.isGroup && _state.canManageTeacherRates) {
      return const Row(
        children: [SizedBox(width: 4), Icon(Icons.edit_rounded, size: 14)],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _settledText(BuildContext context, int settled) {
    final text = _state.canManageTeacherRates
        ? 'Зафиксировано расчётов: $settled · директор может исправить массово'
        : 'Зафиксировано расчётов: $settled · исправление через карточку занятия';
    return Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 11.5,
      ),
    );
  }

  Future<void> _editUnit(
    BuildContext context,
    Map<String, dynamic> unit,
    bool isGroup,
  ) async {
    if (!_state.canManageTeacherRates) return;
    if (isGroup) return _editGroup(context, unit);
    await _editLessons(context, unit);
  }

  Future<void> _editGroup(
    BuildContext context,
    Map<String, dynamic> unit,
  ) async {
    final groupId = unit['groupId']?.toString();
    if (groupId == null || groupId.isEmpty) return;
    final change = await showTeacherStatsGroupRateDialog(
      context: context,
      groupName: unit['unitName']?.toString() ?? 'Группа',
      currentRate: unit['rate'] as num?,
    );
    if (change == null || !context.mounted) return;
    try {
      await controller.updateGroupRate(groupId, change.teacherRate);
    } catch (error) {
      if (context.mounted) {
        _snack(
          context,
          userErrorMessage(error, fallback: 'Не удалось сохранить изменение.'),
        );
      }
    }
  }

  Future<void> _editLessons(
    BuildContext context,
    Map<String, dynamic> unit,
  ) async {
    final lessonIds = controller.editableLessonIdsFor(unit);
    if (lessonIds.isEmpty) {
      _snack(
        context,
        'Расчёт занятия уже зафиксирован. Исправление выполняется через корректировку расчёта в карточке занятия.',
      );
      return;
    }
    final description = _state.canManageTeacherRates
        ? 'Ставка применится к ${lessonIds.length} занятиям этого периода. '
              'Зафиксированные расчёты будут исправлены с сохранением прежних фактов в аудите.'
        : 'Ставка применится к ${lessonIds.length} незакрытым занятиям этого периода. '
              'Зафиксированные расчёты не изменяются.';
    final change = await showTeacherStatsRateDialog(
      context: context,
      title: unit['unitName']?.toString() ?? 'Занятия',
      description: description,
      lessonIds: lessonIds,
      initialRate: unit['rate'] as num?,
    );
    if (change == null || !context.mounted) return;
    try {
      await controller.applyRate(change);
    } catch (error) {
      if (context.mounted) {
        _snack(
          context,
          userErrorMessage(error, fallback: 'Не удалось сохранить ставку.'),
        );
      }
    }
  }

  Widget _totals(Map<String, dynamic> totals) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primaryGold.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primaryGold.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Итого', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          _moneySummary(totals),
        ],
      ),
    );
  }

  Widget _moneySummary(Map<String, dynamic> value) {
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: [
        Text(
          '${controller.integer(value['completedLessons'])} занятий · '
          '${controller.integer(value['payableLessons'])} оплачиваемых',
        ),
        Text('По расписанию: ${controller.hours(value['scheduledHoursTotal'])}'),
        Text('Зачтено преподавателю: ${controller.hours(value['hoursTotal'])}'),
        Text('начислено ${controller.rub(value['accruedTotal'])}'),
      ],
    );
  }

  Widget _rateBadge(BuildContext context, Map<String, dynamic> item) {
    final rate = controller.number(item['currentRate']);
    final label = rate == 0
        ? 'Входит в оклад'
        : '${controller.rateLabel(rate)}/астр.ч.';
    final salary = item['salary'];
    final suffix = salary == null ? '' : ' · оклад ${controller.rub(salary)}';
    return Text(
      '$label$suffix',
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 12,
      ),
    );
  }

  void _snack(BuildContext context, String message, {bool danger = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: danger ? AppColor.danger : null,
      ),
    );
  }
}

class _TeacherStatsUnitMeta {
  const _TeacherStatsUnitMeta({
    required this.isGroup,
    required this.lessonIds,
    required this.unitKey,
    required this.settled,
    required this.days,
    required this.typeLabel,
  });

  final bool isGroup;
  final List<String> lessonIds;
  final String? unitKey;
  final int settled;
  final String days;
  final String typeLabel;
}
