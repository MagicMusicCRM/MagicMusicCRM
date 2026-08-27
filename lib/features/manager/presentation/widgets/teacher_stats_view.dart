import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/teacher_stats_controller.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/teacher_stats_models.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/teacher_stats_rate_dialogs.dart';

part 'teacher_stats_components.dart';

class TeacherStatsView extends StatelessWidget {
  const TeacherStatsView({super.key, required this.controller});

  final TeacherStatsController controller;
  TeacherStatsState get _state => controller.state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: const EdgeInsets.all(12), child: _filters(context)),
        if (_state.selectedUnits.isNotEmpty) _selectionBar(context),
        Expanded(child: _body(context)),
      ],
    );
  }

  Widget _filters(BuildContext context) {
    final query = _state.query;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!_state.usesExternalRange) ...[
          OutlinedButton.icon(
            onPressed: () => _pickPeriod(context),
            icon: const Icon(Icons.date_range_rounded, size: 18),
            label: Text(
              '${controller.dayLabel(query.from)} - '
              '${controller.dayLabel(query.to.subtract(const Duration(days: 1)))}',
            ),
          ),
          _dropdown(
            width: 180,
            key: ValueKey('branch-${query.branchId}'),
            label: 'Филиал',
            value: query.branchId,
            options: {
              null: 'Все филиалы',
              for (final branch in _state.branches)
                branch['id']?.toString():
                    branch['name']?.toString() ?? 'Филиал',
            },
            onChanged: (value) =>
                controller.setQuery(query.copyWith(branchId: value)),
          ),
        ],
        _dropdown(
          width: 200,
          key: ValueKey('teacher-${query.teacherId}'),
          label: 'Педагог',
          value: query.teacherId,
          options: {
            null: 'Все педагоги',
            for (final teacher in _state.teachers)
              teacher['id']?.toString(): _teacherName(teacher),
          },
          onChanged: (value) =>
              controller.setQuery(query.copyWith(teacherId: value)),
        ),
        _dropdown(
          width: 180,
          key: ValueKey('unit-${query.unitType}'),
          label: 'Уч. единицы',
          value: query.unitType,
          options: const {
            null: 'Все',
            'individual': 'Индивидуальные',
            'group': 'Групповые',
            'trial': 'Пробные',
            'individual_trial': 'Индивидуальные',
            'group_trial': 'Групповые',
          },
          onChanged: (value) =>
              controller.setQuery(query.copyWith(unitType: value)),
        ),
        _dropdown(
          width: 180,
          key: ValueKey('status-${query.status}'),
          label: 'Статус преподавателя',
          value: query.status,
          options: const {
            null: 'Любой',
            'active': 'Работает',
            'inactive': 'Не работает',
          },
          onChanged: (value) =>
              controller.setQuery(query.copyWith(status: value)),
        ),
        _dropdown(
          width: 180,
          key: ValueKey('disc-${query.discipline}'),
          label: 'Дисциплина',
          value: query.discipline,
          options: {
            null: 'Все',
            for (final discipline in _state.disciplines)
              discipline['name']?.toString():
                  discipline['name']?.toString() ?? 'Не указано',
          },
          onChanged: (value) =>
              controller.setQuery(query.copyWith(discipline: value)),
        ),
        _dropdown(
          width: 160,
          key: ValueKey('cat-${query.category}'),
          label: 'Категория',
          value: query.category,
          options: {
            null: 'Все',
            for (final category in _state.categoryOptions) category: category,
          },
          onChanged: (value) =>
              controller.setQuery(query.copyWith(category: value)),
        ),
        IconButton(
          tooltip: 'Обновить',
          onPressed: controller.loadReport,
          icon: const Icon(Icons.refresh_rounded),
        ),
        FilledButton.icon(
          onPressed: _state.exporting ? null : () => _export(context),
          icon: _state.exporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.file_download_outlined, size: 18),
          label: const Text('Экспорт'),
        ),
      ],
    );
  }

  Widget _dropdown({
    required double width,
    required Key key,
    required String label,
    required String? value,
    required Map<String?, String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String?>(
        key: key,
        menuMaxHeight: 256,
        isExpanded: true,
        initialValue: value,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: [
          for (final option in options.entries)
            DropdownMenuItem(
              value: option.key,
              child: Text(option.value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }

  String _teacherName(Map<String, dynamic> teacher) {
    final value = '${teacher['first_name'] ?? ''} ${teacher['last_name'] ?? ''}'
        .trim();
    return value.isEmpty ? 'Без имени' : value;
  }

  Future<void> _pickPeriod(BuildContext context) async {
    final query = _state.query;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDateRange: DateTimeRange(
        start: query.from,
        end: query.to.subtract(const Duration(days: 1)),
      ),
    );
    if (picked != null) {
      await controller.setQuery(
        query.copyWith(
          from: picked.start,
          to: picked.end.add(const Duration(days: 1)),
        ),
      );
    }
  }

  Future<void> _export(BuildContext context) async {
    try {
      final result = await controller.export();
      if (!context.mounted) return;
      final stamp = DateUtils.dateOnly(_state.query.from);
      final filename =
          'teacher-stats-${stamp.year.toString().padLeft(4, '0')}-'
          '${stamp.month.toString().padLeft(2, '0')}-'
          '${stamp.day.toString().padLeft(2, '0')}.csv';
      _snack(
        context,
        result.opened
            ? 'Файл открыт: $filename'
            : 'Файл сохранён: ${result.path}',
      );
    } catch (error) {
      if (context.mounted) {
        _snack(
          context,
          userErrorMessage(error, fallback: 'Не удалось выгрузить отчёт.'),
        );
      }
    }
  }

  Widget _selectionBar(BuildContext context) {
    final lessons = _state.selectedUnits.values.fold<int>(
      0,
      (sum, ids) => sum + ids.length,
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primaryGold.withAlpha(24),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primaryGold.withAlpha(60)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Выбрано: ${_state.selectedUnits.length} · занятий: $lessons',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: _state.applyingRate ? null : controller.clearSelection,
            child: const Text('Снять'),
          ),
          const SizedBox(width: 4),
          FilledButton.icon(
            onPressed: _state.applyingRate
                ? null
                : () => _applySelected(context),
            icon: _state.applyingRate
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.payments_outlined, size: 18),
            label: const Text('Проставить ставку'),
          ),
        ],
      ),
    );
  }

  Future<void> _applySelected(BuildContext context) async {
    final lessonIds = [for (final ids in _state.selectedUnits.values) ...ids];
    final change = await showTeacherStatsRateDialog(
      context: context,
      title: 'Ставка выбранным',
      description:
          'Применится к ${_state.selectedUnits.length} юнитам '
          '(${lessonIds.length} занятий) за выбранный период.',
      lessonIds: lessonIds,
    );
    if (change == null || !context.mounted) return;
    try {
      await controller.applyRate(change);
      if (context.mounted) {
        _snack(context, 'Обновлено занятий: ${_state.lastUpdatedCount}');
      }
    } catch (error) {
      if (context.mounted) {
        _snack(
          context,
          userErrorMessage(error, fallback: 'Не удалось применить ставку.'),
          danger: true,
        );
      }
    }
  }

  Widget _body(BuildContext context) {
    if (_state.loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryGold),
      );
    }
    if (_state.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Не удалось загрузить отчёт'),
            const SizedBox(height: 4),
            Text(
              'Проверьте подключение и повторите загрузку.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: controller.loadReport,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }
    final items = (_state.report['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (items.isEmpty) {
      return const Center(child: Text('Нет проведённых занятий за период'));
    }
    final totals = _state.report['totals'] as Map<String, dynamic>? ?? const {};
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [
        if (_state.query.branchId != null &&
            _state.report['movementsScope'] == 'teacher_period_all_branches')
          _movementScopeNote(context),
        for (final item in items) _teacherCard(context, item),
        const SizedBox(height: 8),
        _totals(totals),
      ],
    );
  }

  Widget _movementScopeNote(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Занятия отфильтрованы по филиалу. Выплаты, доплаты и '
              'вычеты показаны по преподавателю за период по всем филиалам.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _teacherCard(BuildContext context, Map<String, dynamic> item) {
    final units = (item['units'] as List? ?? const [])
        .whereType<Map<String, dynamic>>();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item['teacherName']?.toString() ?? 'Без имени',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _rateBadge(context, item),
              ],
            ),
            const SizedBox(height: 6),
            _moneySummary(item, includeOptional: true),
            const SizedBox(height: 8),
            for (final unit in units) _unitRow(context, unit),
          ],
        ),
      ),
    );
  }
}
