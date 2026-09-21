import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/app_dropdown.dart';
import 'package:magic_music_crm/core/widgets/magic_page_state.dart';
import 'package:magic_music_crm/core/widgets/magic_picker.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_data_source.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_models.dart';

enum _ResultsPeriodPreset { week, month, year }

class SharedTaskResultsPanel extends StatefulWidget {
  const SharedTaskResultsPanel({
    super.key,
    required this.dataSource,
    required this.onBack,
    required this.onOpenEntity,
    this.embedded = false,
    this.filterRange,
    this.branchId,
    this.reloadToken = 0,
  });

  final SharedTasksDataSource dataSource;
  final VoidCallback onBack;
  final ValueChanged<EntityLink> onOpenEntity;
  final bool embedded;
  final DateTimeRange? filterRange;
  final String? branchId;
  final int reloadToken;

  @override
  State<SharedTaskResultsPanel> createState() => _SharedTaskResultsPanelState();
}

class _SharedTaskResultsPanelState extends State<SharedTaskResultsPanel> {
  final _search = TextEditingController();
  late DateTimeRange _range;
  List<Map<String, dynamic>> _items = const [];
  Map<String, dynamic> _summary = const {
    'closed': 0,
    'overdue': 0,
    'withoutResult': 0,
  };
  List<SharedTaskAudienceOption> _options = const [];
  Object? _error;
  bool _loading = true;
  bool _includeUndated = false;
  String? _branchId;
  String? _closedBy;
  String? _resultCode;
  bool? _late;
  _ResultsPeriodPreset? _periodPreset = _ResultsPeriodPreset.month;
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _range =
        widget.filterRange ??
        DateTimeRange(
          start: DateTime(today.year, today.month, 1),
          end: DateTime(today.year, today.month, today.day),
        );
    _branchId = widget.branchId;
    _loadOptions();
    _load();
  }

  @override
  void didUpdateWidget(covariant SharedTaskResultsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextRange = widget.filterRange;
    final rangeChanged =
        nextRange != null &&
        (nextRange.start != _range.start || nextRange.end != _range.end);
    if (rangeChanged ||
        oldWidget.branchId != widget.branchId ||
        oldWidget.reloadToken != widget.reloadToken) {
      if (nextRange != null) _range = nextRange;
      _branchId = widget.branchId;
      _periodPreset = null;
      _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      final options = await widget.dataSource.audienceOptions();
      if (mounted) setState(() => _options = options);
    } catch (_) {
      // Results remain usable without directory filters.
    }
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.dataSource.results(
        from: _moscowDayStartUtc(_range.start),
        to: _moscowDayStartUtc(_range.end.add(const Duration(days: 1))),
        branchId: _branchId,
        closedBy: _closedBy,
        resultCode: _resultCode,
        q: _search.text,
        late: _late,
        includeUndated: _includeUndated,
      );
      if (!mounted || version != _loadVersion) return;
      final rawItems = response['items'];
      final rawSummary = response['summary'];
      setState(() {
        _items = rawItems is List
            ? rawItems.whereType<Map<String, dynamic>>().toList()
            : const [];
        _summary = rawSummary is Map<String, dynamic>
            ? rawSummary
            : const {'closed': 0, 'overdue': 0, 'withoutResult': 0};
        _loading = false;
      });
    } catch (error) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _pickRange() async {
    final selected = await showMagicDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 366)),
      initialDateRange: _range,
      helpText: 'Период закрытия задач',
      saveText: 'Применить',
    );
    if (selected == null || !mounted) return;
    setState(() {
      _range = selected;
      _periodPreset = null;
    });
    await _load();
  }

  Future<void> _applyPeriodPreset(_ResultsPeriodPreset preset) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = switch (preset) {
      _ResultsPeriodPreset.week => today.subtract(
        Duration(days: today.weekday - DateTime.monday),
      ),
      _ResultsPeriodPreset.month => DateTime(today.year, today.month),
      _ResultsPeriodPreset.year => DateTime(today.year),
    };
    setState(() {
      _periodPreset = preset;
      _range = DateTimeRange(start: start, end: today);
    });
    await _load();
  }

  List<SharedTaskAudienceOption> get _branches =>
      _options.where((option) => option.type == 'branch').toList();

  List<SharedTaskAudienceOption> get _staff =>
      _options.where((option) => option.type == 'user').toList();

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        _filters(),
        _summaryRow(),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: _body()),
      ],
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const Key('shared-task-results-back'),
          tooltip: 'Назад к задачам',
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Результаты выполнения задач'),
        actions: [
          IconButton(
            tooltip: 'Обновить результаты',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: AppSpace.sm),
        ],
      ),
      body: body,
    );
  }

  Widget _filters() {
    final rangeLabel =
        '${DateFormat('dd.MM.yyyy').format(_range.start)} — '
        '${DateFormat('dd.MM.yyyy').format(_range.end)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Wrap(
        spacing: AppSpace.sm,
        runSpacing: AppSpace.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 260,
            child: TextField(
              key: const Key('shared-task-results-search'),
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                isDense: true,
                labelText: 'Поручение, клиент, сотрудник',
                suffixIcon: IconButton(
                  tooltip: 'Найти',
                  onPressed: _load,
                  icon: const Icon(Icons.search_rounded),
                ),
              ),
            ),
          ),
          if (!widget.embedded) ...[
            OutlinedButton.icon(
              key: const Key('shared-task-results-range'),
              onPressed: _pickRange,
              icon: const Icon(Icons.date_range_rounded),
              label: const Text('Указать период'),
            ),
            for (final preset in _ResultsPeriodPreset.values)
              FilterChip(
                key: ValueKey('shared-task-results-period-${preset.name}'),
                selected: _periodPreset == preset,
                label: Text(switch (preset) {
                  _ResultsPeriodPreset.week => 'Неделя',
                  _ResultsPeriodPreset.month => 'Месяц',
                  _ResultsPeriodPreset.year => 'Год',
                }),
                onSelected: (_) => _applyPeriodPreset(preset),
              ),
            Text(rangeLabel, style: Theme.of(context).textTheme.bodySmall),
          ],
          _resultFilter(),
          if (!widget.embedded)
            _optionFilter(
              key: const Key('shared-task-results-branch'),
              value: _branchId,
              label: 'Все филиалы',
              options: _branches,
              onChanged: (value) {
                setState(() => _branchId = value);
                _load();
              },
            ),
          _optionFilter(
            key: const Key('shared-task-results-closer'),
            value: _closedBy,
            label: 'Все сотрудники',
            options: _staff,
            onChanged: (value) {
              setState(() => _closedBy = value);
              _load();
            },
          ),
          AppDropdownButton<bool?>(
            key: const Key('shared-task-results-late'),
            value: _late,
            items: const [
              DropdownMenuItem(value: null, child: Text('Все сроки')),
              DropdownMenuItem(value: true, child: Text('Просроченные')),
              DropdownMenuItem(value: false, child: Text('В срок')),
            ],
            onChanged: (value) {
              setState(() => _late = value);
              _load();
            },
          ),
          FilterChip(
            key: const Key('shared-task-results-history'),
            label: const Text('Включить старые без даты'),
            selected: _includeUndated,
            onSelected: (selected) {
              setState(() => _includeUndated = selected);
              _load();
            },
          ),
        ],
      ),
    );
  }

  Widget _resultFilter() => AppDropdownButton<String?>(
    key: const Key('shared-task-results-result'),
    value: _resultCode,
    items: [
      const DropdownMenuItem(value: null, child: Text('Все результаты')),
      for (final option in sharedTaskResultOptions)
        DropdownMenuItem(value: option.code, child: Text(option.label)),
      const DropdownMenuItem(
        value: '__missing__',
        child: Text('Без результата (история)'),
      ),
    ],
    onChanged: (value) {
      setState(() => _resultCode = value);
      _load();
    },
  );

  Widget _optionFilter({
    required Key key,
    required String? value,
    required String label,
    required List<SharedTaskAudienceOption> options,
    required ValueChanged<String?> onChanged,
  }) => AppDropdownButton<String?>(
    key: key,
    value: value,
    items: [
      DropdownMenuItem(value: null, child: Text(label)),
      for (final option in options)
        DropdownMenuItem(value: option.id, child: Text(option.label)),
    ],
    onChanged: onChanged,
  );

  Widget _summaryRow() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: AppSpace.sm,
        runSpacing: AppSpace.sm,
        children: [
          _SummaryChip(
            label: 'Закрыто',
            value: _summary['closed'],
            icon: Icons.task_alt_rounded,
          ),
          _SummaryChip(
            label: 'С опозданием',
            value: _summary['overdue'],
            icon: Icons.schedule_rounded,
          ),
          _SummaryChip(
            label: 'История без результата',
            value: _summary['withoutResult'],
            icon: Icons.history_rounded,
          ),
        ],
      ),
    ),
  );

  Widget _body() {
    if (_error != null && _items.isEmpty) {
      return MagicPageState(
        kind: MagicPageStateKind.error,
        title: 'Не удалось загрузить результаты',
        message: 'Фильтры сохранены. Повторите запрос.',
        actionLabel: 'Повторить',
        onAction: _load,
      );
    }
    if (!_loading && _items.isEmpty) {
      return const MagicPageState(
        kind: MagicPageStateKind.empty,
        title: 'Нет закрытых задач',
        message: 'Измените период или фильтры.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        key: const Key('shared-task-results-list'),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
        itemBuilder: (context, index) => _TaskResultCard(
          item: _items[index],
          onOpenEntity: widget.onOpenEntity,
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final Object? value;
  final IconData icon;

  @override
  Widget build(BuildContext context) =>
      Chip(avatar: Icon(icon, size: 18), label: Text('$label: ${value ?? 0}'));
}

class _TaskResultCard extends StatelessWidget {
  const _TaskResultCard({required this.item, required this.onOpenEntity});

  final Map<String, dynamic> item;
  final ValueChanged<EntityLink> onOpenEntity;

  @override
  Widget build(BuildContext context) {
    final client = item['client'];
    final result = item['result'];
    final closer = item['closedBy'];
    final audiences = (item['audiences'] as List? ?? const [])
        .whereType<Map>()
        .map((entry) => entry.map((key, value) => MapEntry('$key', value)))
        .toList();
    final comment = result is Map
        ? result['comment']?.toString().trim() ?? ''
        : '';
    final resultLabel = result is Map
        ? result['label']?.toString().trim() ?? ''
        : '';
    final wasOverdue = item['wasOverdue'] == true;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    item['title']?.toString() ?? 'Задача',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (wasOverdue)
                  const Chip(
                    avatar: Icon(Icons.schedule_rounded, size: 17),
                    label: Text('Закрыта с опозданием'),
                  ),
              ],
            ),
            if (item['body']?.toString().trim().isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(item['body'].toString()),
            ],
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.xl,
              runSpacing: AppSpace.sm,
              children: [
                _AudienceField(
                  label: 'Адресаты',
                  audiences: audiences,
                  onOpenEntity: onOpenEntity,
                  taskId: item['taskId']?.toString() ?? '',
                ),
                _LinkedPersonField(
                  label: 'Закрыл',
                  value: closer is Map
                      ? closer['label']?.toString() ?? 'Сотрудник'
                      : 'Нет данных',
                  link: closer is Map ? _personLink(closer) : null,
                  buttonKey: Key('shared-task-result-closer-${item['taskId']}'),
                  onOpenEntity: onOpenEntity,
                ),
                _Field(
                  label: 'Плановый срок',
                  value: _formatDate(
                    item['plannedStartAt'],
                    allDay: item['plannedAllDay'] == true,
                  ),
                ),
                _Field(label: 'Закрыта', value: _formatDate(item['closedAt'])),
                _Field(
                  label: 'Результат',
                  value: resultLabel.isEmpty
                      ? 'Историческое закрытие: результат не зафиксирован'
                      : resultLabel,
                ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            TextButton.icon(
              key: Key('shared-task-result-task-${item['taskId']}'),
              onPressed: () => onOpenEntity(
                EntityLink.typed(
                  entityType: EntityLinkType.task,
                  entityId: item['taskId'].toString(),
                  presentation: EntityPresentationReference(
                    primary: item['title']?.toString() ?? 'Задача',
                  ),
                ),
              ),
              icon: const Icon(Icons.assignment_outlined),
              label: const Text('Открыть поручение'),
            ),
            if (client is Map && client['id'] != null) ...[
              TextButton.icon(
                key: Key('shared-task-result-client-${item['taskId']}'),
                onPressed: () => onOpenEntity(
                  EntityLink.typed(
                    entityType: EntityLinkType.client,
                    entityId: client['id'].toString(),
                    variant: client['type']?.toString(),
                    presentation: EntityPresentationReference(
                      primary:
                          client['label']?.toString().trim().isNotEmpty == true
                          ? client['label'].toString()
                          : 'Клиент',
                    ),
                  ),
                ),
                icon: const Icon(Icons.person_outline_rounded),
                label: Text(client['label']?.toString() ?? 'Открыть клиента'),
              ),
            ],
            const SizedBox(height: AppSpace.sm),
            Text(
              'Полный комментарий',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 2),
            SelectableText(
              comment.isEmpty ? 'Комментарий не указан.' : comment,
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkedPersonField extends StatelessWidget {
  const _LinkedPersonField({
    required this.label,
    required this.value,
    required this.link,
    required this.buttonKey,
    required this.onOpenEntity,
  });

  final String label;
  final String value;
  final EntityLink? link;
  final Key buttonKey;
  final ValueChanged<EntityLink> onOpenEntity;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 210,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        if (link == null)
          Text(value)
        else
          TextButton.icon(
            key: buttonKey,
            onPressed: () => onOpenEntity(link!),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.badge_outlined, size: 18),
            label: Text(value),
          ),
      ],
    ),
  );
}

class _AudienceField extends StatelessWidget {
  const _AudienceField({
    required this.label,
    required this.audiences,
    required this.onOpenEntity,
    required this.taskId,
  });

  final String label;
  final List<Map<String, dynamic>> audiences;
  final ValueChanged<EntityLink> onOpenEntity;
  final String taskId;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 260,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        if (audiences.isEmpty)
          const Text('Не указаны')
        else
          Wrap(
            spacing: 4,
            runSpacing: 2,
            children: [
              for (var index = 0; index < audiences.length; index++)
                Builder(
                  builder: (context) {
                    final audience = audiences[index];
                    final value = audience['label']?.toString().trim();
                    final link = _personLink(audience);
                    if (link == null) return Text(value ?? 'Не указано');
                    return TextButton(
                      key: Key('shared-task-result-audience-$taskId-$index'),
                      onPressed: () => onOpenEntity(link),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        value?.isNotEmpty == true ? value! : 'Сотрудник',
                      ),
                    );
                  },
                ),
            ],
          ),
      ],
    ),
  );
}

EntityLink? _personLink(Map<dynamic, dynamic> value) {
  final entityType = value['entityType']?.toString();
  final entityId = value['entityId']?.toString().trim();
  if (entityId == null || entityId.isEmpty) return null;
  final label = value['label']?.toString().trim();
  if (entityType == 'staff') {
    return EntityLink.typed(
      entityType: EntityLinkType.user,
      entityId: entityId,
      variant: 'staff',
      presentation: EntityPresentationReference(
        primary: label?.isNotEmpty == true ? label! : 'Сотрудник',
      ),
    );
  }
  if (entityType == 'teacher') {
    return EntityLink.typed(
      entityType: EntityLinkType.teacher,
      entityId: entityId,
      variant: 'personnel_teacher',
      presentation: EntityPresentationReference(
        primary: label?.isNotEmpty == true ? label! : 'Преподаватель',
      ),
    );
  }
  return null;
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 210,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        Text(value),
      ],
    ),
  );
}

String _formatDate(Object? value, {bool allDay = false}) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  if (parsed == null) return 'Нет данных';
  return DateFormat(
    allDay ? 'dd.MM.yyyy' : 'dd.MM.yyyy HH:mm',
  ).format(parsed.toLocal());
}

String _moscowDayStartUtc(DateTime date) => DateTime.utc(
  date.year,
  date.month,
  date.day,
).subtract(const Duration(hours: 3)).toIso8601String();
