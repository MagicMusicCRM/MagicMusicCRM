import 'package:magic_music_crm/core/widgets/magic_picker.dart';
import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/models/types.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';
import 'package:magic_music_crm/features/manager/presentation/providers/leads_providers.dart';

/// Reusable labelled dropdown for one lead-board filter facet. Pure.
Widget filterDropdown({
  required double width,
  required String label,
  required String value,
  required List<Map<String, dynamic>> options,
  required ValueChanged<String?> onChanged,
  String valueField = 'id',
}) {
  final normalizedValue = value.isEmpty ? '' : value;
  final seen = <String>{};
  final optionItems = options
      .map((item) {
        final optionValue = item[valueField]?.toString() ?? '';
        final optionLabel =
            item['name']?.toString() ??
            item['label']?.toString() ??
            optionValue;
        return (optionValue, optionLabel);
      })
      .where((item) => item.$1.isNotEmpty && seen.add(item.$1))
      .toList();
  final hasSelected =
      normalizedValue.isEmpty ||
      optionItems.any((item) => item.$1 == normalizedValue);
  return Padding(
    padding: const EdgeInsets.only(right: 8),
    child: SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        menuMaxHeight: 256,
        key: ValueKey('$label:$normalizedValue'),
        initialValue: normalizedValue,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: [
          const DropdownMenuItem(value: '', child: Text('Все')),
          if (!hasSelected)
            DropdownMenuItem(
              value: normalizedValue,
              child: Text(normalizedValue, overflow: TextOverflow.ellipsis),
            ),
          ...optionItems.map(
            (item) => DropdownMenuItem(
              value: item.$1,
              child: Text(item.$2, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: onChanged,
      ),
    ),
  );
}

Widget filterTextField({
  required double width,
  required String label,
  required String value,
  ValueChanged<String>? onChanged,
  ValueChanged<String>? onSubmitted,
}) {
  return Padding(
    padding: const EdgeInsets.only(right: 8),
    child: SizedBox(
      width: width,
      child: TextFormField(
        key: ValueKey('lead-filter-$label:$value'),
        initialValue: value,
        decoration: InputDecoration(labelText: label, isDense: true),
        textInputAction: TextInputAction.done,
        onChanged: onChanged,
        onFieldSubmitted: onSubmitted,
      ),
    ),
  );
}

DateTimeRange? _dateRangeOf(LeadBoardFilters filters) {
  final from = DateTime.tryParse(filters.from)?.toLocal();
  final toExclusive = DateTime.tryParse(filters.to)?.toLocal();
  if (from == null || toExclusive == null || !toExclusive.isAfter(from)) {
    return null;
  }
  return DateTimeRange(
    start: DateTime(from.year, from.month, from.day),
    end: DateTime(
      toExclusive.year,
      toExclusive.month,
      toExclusive.day,
    ).subtract(const Duration(days: 1)),
  );
}

String _shortDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.'
    '${value.month.toString().padLeft(2, '0')}.${value.year}';

Widget filterDateRangeButton({
  required BuildContext context,
  required LeadBoardFilters filters,
  required ValueChanged<LeadBoardFilters> onApply,
}) {
  final range = _dateRangeOf(filters);
  final label = range == null
      ? 'Период обращения'
      : '${_shortDate(range.start)} - ${_shortDate(range.end)}';
  return SizedBox(
    width: 260,
    child: Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const ValueKey('lead-filter-period'),
            icon: const Icon(Icons.date_range_rounded, size: 18),
            label: Text(label, overflow: TextOverflow.ellipsis),
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showMagicDateRangePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime(now.year + 3, 12, 31),
                initialDateRange: range,
              );
              if (picked == null) return;
              final from = DateTime(
                picked.start.year,
                picked.start.month,
                picked.start.day,
              ).toUtc();
              final to = DateTime(
                picked.end.year,
                picked.end.month,
                picked.end.day + 1,
              ).toUtc();
              onApply(
                filters.copyWith(
                  from: from.toIso8601String(),
                  to: to.toIso8601String(),
                ),
              );
            },
          ),
        ),
        if (range != null)
          IconButton(
            key: const ValueKey('lead-filter-period-clear'),
            tooltip: 'Сбросить период',
            onPressed: () => onApply(filters.copyWith(from: '', to: '')),
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
      ],
    ),
  );
}

/// Desktop inline filters panel: quick chips + facet dropdowns, applying live
/// through [onApply]. Extracted from _LeadsWidgetState._buildInlineFilterPanel.
class LeadsInlineFilterPanel extends StatelessWidget {
  final LeadBoardFilters filters;
  final String searchText;
  final List<Map<String, dynamic>> branches;
  final List<Map<String, dynamic>> sources;
  final List<Map<String, dynamic>> responsibles;
  final List<StatusRecord> statuses;
  final List<Map<String, dynamic>> disciplines;
  final List<Map<String, dynamic>> levels;
  final List<Map<String, dynamic>> categories;
  final void Function(LeadBoardFilters) onApply;
  final VoidCallback onCollapse;

  const LeadsInlineFilterPanel({
    super.key,
    required this.filters,
    required this.searchText,
    required this.branches,
    required this.sources,
    required this.responsibles,
    required this.statuses,
    required this.disciplines,
    required this.levels,
    required this.categories,
    required this.onApply,
    required this.onCollapse,
  });

  @override
  Widget build(BuildContext context) {
    Widget quickChip(String value, String chipLabel) => ChoiceChip(
      label: Text(chipLabel),
      selected: filters.quick == value,
      onSelected: (_) => onApply(filters.copyWith(quick: value)),
    );
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColor.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColor.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              quickChip('all', 'Все'),
              quickChip('active', 'В работе'),
              quickChip('deferred', 'Отложенные'),
              quickChip('processed', 'Обработанные'),
              FilterChip(
                label: const Text('Есть задачи'),
                selected: filters.openTasks,
                onSelected: (v) => onApply(filters.copyWith(openTasks: v)),
              ),
              // Лид, ставший учеником, остаётся на доске: он же и лид, и
              // ученик — карточка показывает обе половины. Но когда работаешь
              // с воронкой, он только мешает.
              FilterChip(
                label: const Text('Скрыть ставших учениками'),
                selected: filters.hideConverted,
                onSelected: (v) => onApply(filters.copyWith(hideConverted: v)),
              ),
              filterDropdown(
                width: 200,
                label: 'Филиал',
                value: filters.branchId,
                options: branches,
                onChanged: (v) => onApply(filters.copyWith(branchId: v ?? '')),
              ),
              filterDropdown(
                width: 200,
                label: 'Статус',
                value: filters.statusId,
                options: statuses
                    .map((s) => {'id': s.$1, 'name': s.$2})
                    .toList(),
                onChanged: (v) => onApply(filters.copyWith(statusId: v ?? '')),
              ),
              filterDropdown(
                width: 200,
                label: 'Источник',
                value: filters.source,
                options: sources,
                valueField: 'name',
                onChanged: (v) => onApply(filters.copyWith(source: v ?? '')),
              ),
              filterDropdown(
                width: 220,
                label: 'Ответственный',
                value: filters.assignedTo,
                options: responsibles,
                onChanged: (v) =>
                    onApply(filters.copyWith(assignedTo: v ?? '')),
              ),
              filterDropdown(
                width: 200,
                label: 'Направление',
                value: filters.discipline,
                options: disciplines,
                valueField: 'name',
                onChanged: (v) =>
                    onApply(filters.copyWith(discipline: v ?? '')),
              ),
              filterDropdown(
                width: 200,
                label: 'Уровень',
                value: filters.level,
                options: levels,
                valueField: 'name',
                onChanged: (v) => onApply(filters.copyWith(level: v ?? '')),
              ),
              filterDropdown(
                width: 200,
                label: 'Категория',
                value: filters.category,
                options: categories,
                valueField: 'name',
                onChanged: (v) => onApply(filters.copyWith(category: v ?? '')),
              ),
              filterTextField(
                width: 200,
                label: 'Тип обращения',
                value: filters.requestType,
                onSubmitted: (v) =>
                    onApply(filters.copyWith(requestType: v.trim())),
              ),
              filterTextField(
                width: 200,
                label: 'Цель обучения',
                value: filters.goal,
                onSubmitted: (v) => onApply(filters.copyWith(goal: v.trim())),
              ),
              filterTextField(
                width: 160,
                label: 'Пол',
                value: filters.gender,
                onSubmitted: (v) => onApply(filters.copyWith(gender: v.trim())),
              ),
              filterTextField(
                width: 240,
                label: 'Предпочитаемое расписание',
                value: filters.preferredSchedule,
                onSubmitted: (v) =>
                    onApply(filters.copyWith(preferredSchedule: v.trim())),
              ),
              filterDateRangeButton(
                context: context,
                filters: filters,
                onApply: onApply,
              ),
              filterDropdown(
                width: 200,
                label: 'Сортировка',
                value: filters.sort,
                options: const [
                  {'id': 'newest', 'name': 'Сначала новые'},
                  {'id': 'oldest', 'name': 'Сначала старые'},
                ],
                onChanged: (v) =>
                    onApply(filters.copyWith(sort: v ?? 'newest')),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => onApply(LeadBoardFilters(q: searchText)),
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text('Сбросить'),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => onCollapse(),
                child: const Text('Свернуть'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Right-side slide-out drawer for the secondary lead filters. Edits a local
/// draft and commits through [onApply] on «Применить». Extracted from
/// _LeadsWidgetState._openFiltersDrawer.
Future<void> openLeadsFilterDrawer(
  BuildContext context, {
  required LeadBoardFilters filters,
  required String searchText,
  required List<Map<String, dynamic>> branches,
  required List<Map<String, dynamic>> sources,
  required List<Map<String, dynamic>> responsibles,
  required List<StatusRecord> statuses,
  required List<Map<String, dynamic>> disciplines,
  required List<Map<String, dynamic>> levels,
  required List<Map<String, dynamic>> categories,
  required void Function(LeadBoardFilters) onApply,
}) async {
  // Seed the draft from the live filters, keeping the current search text so
  // applying the drawer never clobbers the inline quick search.
  var draft = filters.copyWith(q: searchText);

  final applied = await showMagicSheet<bool>(
    context,
    title: 'Фильтры',
    builder: (drawerContext) {
      return StatefulBuilder(
        builder: (drawerContext, setDrawerState) {
          void update(LeadBoardFilters next) =>
              setDrawerState(() => draft = next);

          Widget section(String label, Widget child) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColor.text2,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              child,
              const SizedBox(height: AppSpace.lg),
            ],
          );

          Widget quickChip(String value, String chipLabel) => ChoiceChip(
            label: Text(chipLabel),
            selected: draft.quick == value,
            onSelected: (_) => update(draft.copyWith(quick: value)),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              section(
                'Быстрый фильтр',
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    quickChip('all', 'Все'),
                    quickChip('active', 'В работе'),
                    quickChip('deferred', 'Отложенные'),
                    quickChip('processed', 'Обработанные'),
                  ],
                ),
              ),
              section(
                'Задачи',
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilterChip(
                    label: const Text('Есть задачи'),
                    selected: draft.openTasks,
                    onSelected: (selected) =>
                        update(draft.copyWith(openTasks: selected)),
                  ),
                ),
              ),
              section(
                'Конверсия',
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilterChip(
                    label: const Text('Скрыть ставших учениками'),
                    selected: draft.hideConverted,
                    onSelected: (selected) =>
                        update(draft.copyWith(hideConverted: selected)),
                  ),
                ),
              ),
              section(
                'Филиал',
                filterDropdown(
                  width: double.infinity,
                  label: 'Филиал',
                  value: draft.branchId,
                  options: branches,
                  onChanged: (value) =>
                      update(draft.copyWith(branchId: value ?? '')),
                ),
              ),
              section(
                'Статус',
                filterDropdown(
                  width: double.infinity,
                  label: 'Статус',
                  value: draft.statusId,
                  options: statuses
                      .map((s) => {'id': s.$1, 'name': s.$2})
                      .toList(),
                  onChanged: (value) =>
                      update(draft.copyWith(statusId: value ?? '')),
                ),
              ),
              section(
                'Источник',
                filterDropdown(
                  width: double.infinity,
                  label: 'Источник',
                  value: draft.source,
                  options: sources,
                  valueField: 'name',
                  onChanged: (value) =>
                      update(draft.copyWith(source: value ?? '')),
                ),
              ),
              section(
                'Ответственный',
                filterDropdown(
                  width: double.infinity,
                  label: 'Ответственный',
                  value: draft.assignedTo,
                  options: responsibles,
                  onChanged: (value) =>
                      update(draft.copyWith(assignedTo: value ?? '')),
                ),
              ),
              section(
                'Направление',
                filterDropdown(
                  width: double.infinity,
                  label: 'Направление',
                  value: draft.discipline,
                  options: disciplines,
                  valueField: 'name',
                  onChanged: (value) =>
                      update(draft.copyWith(discipline: value ?? '')),
                ),
              ),
              section(
                'Уровень',
                filterDropdown(
                  width: double.infinity,
                  label: 'Уровень',
                  value: draft.level,
                  options: levels,
                  valueField: 'name',
                  onChanged: (value) =>
                      update(draft.copyWith(level: value ?? '')),
                ),
              ),
              section(
                'Категория',
                filterDropdown(
                  width: double.infinity,
                  label: 'Категория',
                  value: draft.category,
                  options: categories,
                  valueField: 'name',
                  onChanged: (value) =>
                      update(draft.copyWith(category: value ?? '')),
                ),
              ),
              section(
                'Тип обращения',
                filterTextField(
                  width: double.infinity,
                  label: 'Тип обращения',
                  value: draft.requestType,
                  onChanged: (value) =>
                      draft = draft.copyWith(requestType: value.trim()),
                ),
              ),
              section(
                'Цель обучения',
                filterTextField(
                  width: double.infinity,
                  label: 'Цель обучения',
                  value: draft.goal,
                  onChanged: (value) =>
                      draft = draft.copyWith(goal: value.trim()),
                ),
              ),
              section(
                'Пол',
                filterTextField(
                  width: double.infinity,
                  label: 'Пол',
                  value: draft.gender,
                  onChanged: (value) =>
                      draft = draft.copyWith(gender: value.trim()),
                ),
              ),
              section(
                'Предпочитаемое расписание',
                filterTextField(
                  width: double.infinity,
                  label: 'Предпочитаемое расписание',
                  value: draft.preferredSchedule,
                  onChanged: (value) =>
                      draft = draft.copyWith(preferredSchedule: value.trim()),
                ),
              ),
              section(
                'Период обращения',
                filterDateRangeButton(
                  context: drawerContext,
                  filters: draft,
                  onApply: update,
                ),
              ),
              section(
                'Сортировка',
                filterDropdown(
                  width: double.infinity,
                  label: 'Сортировка',
                  value: draft.sort,
                  options: const [
                    {'id': 'newest', 'name': 'Сначала новые'},
                    {'id': 'oldest', 'name': 'Сначала старые'},
                  ],
                  onChanged: (value) =>
                      update(draft.copyWith(sort: value ?? 'newest')),
                ),
              ),
            ],
          );
        },
      );
    },
    actions: [
      OutlinedButton(
        onPressed: () {
          // Reset the secondary filters to defaults, but keep the active
          // quick-search text the toolbar field still shows.
          draft = LeadBoardFilters(q: searchText);
          onApply(draft);
          Navigator.of(context).maybePop(false);
        },
        child: const Text('Сбросить'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).maybePop(true),
        style: FilledButton.styleFrom(
          backgroundColor: AppColor.gold,
          foregroundColor: AppColor.onGold,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
        ),
        child: const Text('Применить'),
      ),
    ],
  );

  // Commit the draft only on «Применить»; «Сбросить» already applied above.
  if (applied == true) {
    onApply(draft);
  }
}
