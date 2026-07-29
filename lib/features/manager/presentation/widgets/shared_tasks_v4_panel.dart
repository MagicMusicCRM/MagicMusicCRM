import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/magic_profile_admin_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

abstract class SharedTasksDataSource {
  Future<Map<String, dynamic>> list({String? state});

  Future<Map<String, dynamic>> create(
    Map<String, dynamic> data,
    MagicMutationIdentity identity,
  );

  Future<Map<String, dynamic>> update(
    String taskId,
    Map<String, dynamic> data,
    MagicMutationIdentity identity,
  );

  Future<Map<String, dynamic>> close(
    String taskId,
    int expectedVersion,
    MagicMutationIdentity identity,
  );

  Future<List<SharedTaskAudienceOption>> audienceOptions();
}

class SharedTaskAudienceOption {
  const SharedTaskAudienceOption({
    required this.type,
    required this.id,
    required this.label,
  });

  final String type;
  final String id;
  final String label;
}

class _ServiceSharedTasksDataSource implements SharedTasksDataSource {
  _ServiceSharedTasksDataSource(this.ref);

  final WidgetRef ref;

  @override
  Future<Map<String, dynamic>> list({String? state}) {
    return ref.read(magicCrmServiceProvider).listSharedTasks(state: state);
  }

  @override
  Future<Map<String, dynamic>> create(
    Map<String, dynamic> data,
    MagicMutationIdentity identity,
  ) {
    return ref
        .read(magicCrmServiceProvider)
        .createSharedTask(data: data, identity: identity);
  }

  @override
  Future<Map<String, dynamic>> update(
    String taskId,
    Map<String, dynamic> data,
    MagicMutationIdentity identity,
  ) {
    return ref
        .read(magicCrmServiceProvider)
        .updateSharedTask(taskId: taskId, data: data, identity: identity);
  }

  @override
  Future<Map<String, dynamic>> close(
    String taskId,
    int expectedVersion,
    MagicMutationIdentity identity,
  ) {
    return ref
        .read(magicCrmServiceProvider)
        .closeSharedTask(
          taskId: taskId,
          expectedVersion: expectedVersion,
          identity: identity,
        );
  }

  @override
  Future<List<SharedTaskAudienceOption>> audienceOptions() async {
    final result = await Future.wait([
      ref.read(magicProfileAdminServiceProvider).listProfiles(limit: 200),
      ref.read(magicCrmServiceProvider).listBranches(limit: 200),
    ]);
    return [
      ...result[0]
          .where((row) => row['user_id'] != null)
          .map(
            (row) => SharedTaskAudienceOption(
              type: 'user',
              id: row['user_id'].toString(),
              label: _profileLabel(row),
            ),
          ),
      ...result[1].map(
        (row) => SharedTaskAudienceOption(
          type: 'branch',
          id: row['id'].toString(),
          label: row['name']?.toString() ?? 'Филиал',
        ),
      ),
    ];
  }
}

class SharedTasksV4Panel extends ConsumerStatefulWidget {
  const SharedTasksV4Panel({super.key, this.dataSource, this.embedded = false});

  final SharedTasksDataSource? dataSource;
  final bool embedded;

  @override
  ConsumerState<SharedTasksV4Panel> createState() => _SharedTasksV4PanelState();
}

class _SharedTasksV4PanelState extends ConsumerState<SharedTasksV4Panel> {
  late SharedTasksDataSource _dataSource;
  List<Map<String, dynamic>> _items = const [];
  Map<String, dynamic> _counters = const {'open': 0, 'overdue': 0};
  bool _loading = true;
  Object? _error;
  String _filter = 'open';
  Timer? _realtimeDebounce;
  final Set<String> _closing = {};
  final Map<String, Object> _closeErrors = {};
  final Map<String, MagicMutationIdentity> _closeIdentities = {};

  @override
  void initState() {
    super.initState();
    _dataSource = widget.dataSource ?? _ServiceSharedTasksDataSource(ref);
    Future<void>.microtask(_load);
  }

  @override
  void dispose() {
    _realtimeDebounce?.cancel();
    super.dispose();
  }

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final result = await _dataSource.list(
        state: _filter == 'all' || _filter == 'overdue' ? null : _filter,
      );
      final rawItems = result['items'];
      var items = rawItems is List
          ? rawItems.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];
      if (_filter == 'overdue') {
        final now = DateTime.now();
        items = items.where((task) {
          final start = DateTime.tryParse(task['startAt']?.toString() ?? '');
          return task['state'] == 'open' &&
              start != null &&
              start.isBefore(now);
        }).toList();
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _counters = result['counters'] is Map<String, dynamic>
            ? result['counters'] as Map<String, dynamic>
            : const {'open': 0, 'overdue': 0};
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _close(Map<String, dynamic> task) async {
    final id = task['id']?.toString();
    final version = task['version'];
    if (id == null || version is! int || _closing.contains(id)) return;
    final identity = _closeIdentities.putIfAbsent(
      id,
      () => MagicMutationIdentity.create('shared-task-close'),
    );
    setState(() {
      _closing.add(id);
      _closeErrors.remove(id);
    });
    try {
      await _dataSource.close(id, version, identity);
      _closeIdentities.remove(id);
      await _load(showLoading: false);
    } catch (error) {
      if (!mounted) return;
      setState(() => _closeErrors[id] = error);
    } finally {
      if (mounted) setState(() => _closing.remove(id));
    }
  }

  Future<void> _openEditor([Map<String, dynamic>? task]) async {
    List<SharedTaskAudienceOption> options = const [];
    try {
      options = await _dataSource.audienceOptions();
    } catch (_) {
      // allBranches remains available even if directory loading failed.
    }
    if (!mounted) return;
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) =>
          SharedTaskEditor(task: task, audienceOptions: options),
    );
    if (payload == null || !mounted) return;
    final identity = MagicMutationIdentity.create(
      task == null ? 'shared-task-create' : 'shared-task-update',
    );
    try {
      if (task == null) {
        await _dataSource.create(payload, identity);
      } else {
        await _dataSource.update(task['id'].toString(), payload, identity);
      }
      await _load(showLoading: false);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Не удалось сохранить задачу. Повторите.'),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => _openEditor(task),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.dataSource == null) {
      ref.listen(crmRealtimeProvider, (previous, next) {
        final event = next.value;
        if (event?.entity != 'task') return;
        _realtimeDebounce?.cancel();
        _realtimeDebounce = Timer(
          const Duration(milliseconds: 200),
          () => mounted ? _load(showLoading: false) : null,
        );
      });
    }
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 600;
        return Column(
          children: [
            if (_counters['overdue'] case final num overdue when overdue > 0)
              _ReminderBanner(overdue: overdue.toInt()),
            mobile
                ? _MobileTaskFilter(value: _filter, onChanged: _setFilter)
                : _DesktopTaskFilter(
                    value: _filter,
                    counters: _counters,
                    onChanged: _setFilter,
                  ),
            Expanded(child: _body()),
          ],
        );
      },
    );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Общие задачи'),
        actions: [
          IconButton(
            onPressed: () => _openEditor(),
            tooltip: 'Новая общая задача',
            icon: const Icon(Icons.add_task_rounded),
          ),
        ],
      ),
      body: content,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Новая задача'),
      ),
    );
  }

  void _setFilter(String value) {
    if (value == _filter) return;
    setState(() => _filter = value);
    _load();
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Не удалось загрузить общие задачи'),
            const SizedBox(height: AppSpace.md),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('Нет общих задач'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
        itemBuilder: (context, index) {
          final task = _items[index];
          final id = task['id']?.toString() ?? '';
          return _SharedTaskCard(
            task: task,
            closing: _closing.contains(id),
            closeError: _closeErrors[id],
            onClose: () => _close(task),
            onEdit: () => _openEditor(task),
          );
        },
      ),
    );
  }
}

class _ReminderBanner extends StatelessWidget {
  const _ReminderBanner({required this.overdue});

  final int overdue;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('shared-task-reminder-panel'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColor.warning.withValues(alpha: .12),
        border: Border.all(color: AppColor.warning.withValues(alpha: .45)),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.notifications_active_outlined,
            color: AppColor.warning,
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: Text('Просроченных общих задач: $overdue')),
        ],
      ),
    );
  }
}

class _MobileTaskFilter extends StatelessWidget {
  const _MobileTaskFilter({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('shared-task-mobile-filter'),
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: value,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Задачи',
                ),
                items: const [
                  DropdownMenuItem(value: 'open', child: Text('Открытые')),
                  DropdownMenuItem(
                    value: 'overdue',
                    child: Text('Просроченные'),
                  ),
                  DropdownMenuItem(value: 'closed', child: Text('Закрытые')),
                  DropdownMenuItem(value: 'all', child: Text('Все')),
                ],
                onChanged: (next) {
                  if (next != null) onChanged(next);
                },
              ),
            ),
            IconButton(
              tooltip: 'Расширенные фильтры',
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (context) => _AdvancedFilters(
                  value: value,
                  onChanged: (next) {
                    Navigator.pop(context);
                    onChanged(next);
                  },
                ),
              ),
              icon: const Icon(Icons.tune_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopTaskFilter extends StatelessWidget {
  const _DesktopTaskFilter({
    required this.value,
    required this.counters,
    required this.onChanged,
  });

  final String value;
  final Map<String, dynamic> counters;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          for (final entry in const [
            ('open', 'Открытые'),
            ('overdue', 'Просроченные'),
            ('closed', 'Закрытые'),
            ('all', 'Все'),
          ])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(entry.$2),
                selected: value == entry.$1,
                onSelected: (_) => onChanged(entry.$1),
              ),
            ),
          const Spacer(),
          Text(
            'Открыто: ${counters['open'] ?? 0}',
            style: const TextStyle(color: AppColor.text2),
          ),
        ],
      ),
    );
  }
}

class _AdvancedFilters extends StatelessWidget {
  const _AdvancedFilters({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('shared-task-advanced-filter-scroll'),
        padding: AppSpace.sheetBody,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Фильтры', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpace.md),
            for (final entry in const [
              ('open', 'Открытые'),
              ('overdue', 'Просроченные'),
              ('closed', 'Закрытые'),
              ('all', 'Все задачи'),
            ])
              ListTile(
                title: Text(entry.$2),
                trailing: value == entry.$1
                    ? const Icon(Icons.check_rounded, color: AppColor.gold)
                    : null,
                onTap: () => onChanged(entry.$1),
              ),
          ],
        ),
      ),
    );
  }
}

class _SharedTaskCard extends StatelessWidget {
  const _SharedTaskCard({
    required this.task,
    required this.closing,
    required this.closeError,
    required this.onClose,
    required this.onEdit,
  });

  final Map<String, dynamic> task;
  final bool closing;
  final Object? closeError;
  final VoidCallback onClose;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final closed = task['state'] == 'closed';
    final startsAt = DateTime.tryParse(task['startAt']?.toString() ?? '');
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    task['title']?.toString() ?? 'Задача',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (!closed)
                  IconButton(
                    onPressed: closing ? null : onEdit,
                    tooltip: 'Изменить',
                    icon: const Icon(Icons.edit_outlined, size: 20),
                  ),
              ],
            ),
            if (task['body']?.toString().trim().isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(task['body'].toString()),
              ),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _MetaChip(
                  icon: task['allDay'] == true
                      ? Icons.event_outlined
                      : Icons.schedule_outlined,
                  label: startsAt == null
                      ? 'Без даты'
                      : DateFormat(
                          'dd.MM.yyyy HH:mm',
                        ).format(startsAt.toLocal()),
                ),
                _MetaChip(
                  icon: closed
                      ? Icons.check_circle_outline
                      : Icons.groups_outlined,
                  label: closed ? 'Закрыта' : 'Общая',
                ),
                if (task['hasReminder'] == true)
                  const _MetaChip(
                    key: Key('shared-task-reminder-badge'),
                    icon: Icons.notifications_none,
                    label: 'Напоминание',
                  ),
              ],
            ),
            if (!closed) ...[
              const SizedBox(height: AppSpace.md),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: Key('close-shared-task-${task['id']}'),
                  onPressed: closing ? null : onClose,
                  icon: closing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.task_alt_rounded),
                  label: Text(
                    closeError == null
                        ? 'Закрыть задачу'
                        : 'Повторить закрытие',
                  ),
                ),
              ),
              if (closeError != null)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Не удалось закрыть. Задача осталась открытой.',
                    style: TextStyle(color: AppColor.danger),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColor.goldSoft,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColor.gold),
          const SizedBox(width: 5),
          Text(label),
        ],
      ),
    );
  }
}

class SharedTaskEditor extends StatefulWidget {
  const SharedTaskEditor({super.key, required this.audienceOptions, this.task});

  final List<SharedTaskAudienceOption> audienceOptions;
  final Map<String, dynamic>? task;

  @override
  State<SharedTaskEditor> createState() => _SharedTaskEditorState();
}

class _SharedTaskEditorState extends State<SharedTaskEditor> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late bool _allDay;
  late DateTime _start;
  DateTime? _end;
  String _audienceType = 'allBranches';
  String? _targetId;
  final List<Map<String, dynamic>> _audiences = [];
  List<Map<String, dynamic>> _existingReminders = const [];
  bool _reminder = false;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _title = TextEditingController(text: task?['title']?.toString() ?? '');
    _body = TextEditingController(text: task?['body']?.toString() ?? '');
    _allDay = task?['allDay'] != false;
    _start =
        DateTime.tryParse(task?['startAt']?.toString() ?? '')?.toLocal() ??
        DateTime.now().add(const Duration(days: 1));
    _end = DateTime.tryParse(task?['endAt']?.toString() ?? '')?.toLocal();
    final existing = task?['audiences'];
    if (existing is List) {
      _audiences.addAll(existing.whereType<Map<String, dynamic>>());
    }
    if (_audiences.isEmpty) {
      _audiences.add({'type': 'allBranches'});
    }
    _reminder = task?['hasReminder'] == true;
    final existingReminders = task?['reminders'];
    if (existingReminders is List) {
      _existingReminders = existingReminders
          .whereType<Map<String, dynamic>>()
          .map((item) => {'dueAt': item['dueAt'], 'channel': item['channel']})
          .toList();
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.audienceOptions
        .where((option) => option.type == _audienceType)
        .toList();
    return AlertDialog(
      title: Text(
        widget.task == null ? 'Новая общая задача' : 'Изменить задачу',
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('shared-task-title'),
                controller: _title,
                decoration: const InputDecoration(labelText: 'Название'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _body,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Описание'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('На весь день'),
                value: _allDay,
                onChanged: (value) => setState(() {
                  _allDay = value;
                  _end = value
                      ? null
                      : (_end ?? _start.add(const Duration(hours: 1)));
                }),
              ),
              _DateTimeButton(
                label: 'Начало',
                value: _start,
                dateOnly: _allDay,
                onChanged: (value) => setState(() => _start = value),
              ),
              if (!_allDay)
                _DateTimeButton(
                  label: 'Окончание',
                  value: _end ?? _start.add(const Duration(hours: 1)),
                  onChanged: (value) => setState(() => _end = value),
                ),
              const Divider(height: 28),
              Text('Кому', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'user', label: Text('Сотрудники')),
                  ButtonSegment(value: 'branch', label: Text('Филиал')),
                  ButtonSegment(
                    value: 'allBranches',
                    label: Text('Все филиалы'),
                  ),
                ],
                selected: {_audienceType},
                onSelectionChanged: (selection) => setState(() {
                  _audienceType = selection.first;
                  _targetId = null;
                }),
              ),
              if (_audienceType != 'allBranches') ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _targetId,
                  decoration: InputDecoration(
                    labelText: _audienceType == 'user' ? 'Сотрудник' : 'Филиал',
                  ),
                  items: options
                      .map(
                        (option) => DropdownMenuItem(
                          value: option.id,
                          child: Text(option.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _targetId = value),
                ),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _canAddAudience ? _addAudience : null,
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('Добавить получателей'),
              ),
              Wrap(
                spacing: 6,
                children: _audiences
                    .map(
                      (audience) => InputChip(
                        label: Text(_audienceLabel(audience)),
                        onDeleted: _audiences.length == 1
                            ? null
                            : () => setState(() => _audiences.remove(audience)),
                      ),
                    )
                    .toList(),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Напомнить в приложении'),
                subtitle: const Text('Не блокирует текущую работу'),
                value: _reminder,
                onChanged: (value) => setState(() {
                  _reminder = value;
                  if (!value) _existingReminders = const [];
                }),
              ),
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
          onPressed: _title.text.trim().isEmpty ? null : _submit,
          child: Text(widget.task == null ? 'Создать' : 'Сохранить'),
        ),
      ],
    );
  }

  bool get _canAddAudience =>
      _audienceType == 'allBranches' || _targetId != null;

  void _addAudience() {
    final audience = {
      'type': _audienceType,
      if (_audienceType != 'allBranches') 'targetId': _targetId,
    };
    final key = '${audience['type']}:${audience['targetId'] ?? ''}';
    if (_audiences.any(
      (item) => '${item['type']}:${item['targetId'] ?? ''}' == key,
    )) {
      return;
    }
    setState(() => _audiences.add(audience));
  }

  String _audienceLabel(Map<String, dynamic> audience) {
    if (audience['type'] == 'allBranches') return 'Все филиалы';
    final id = audience['targetId']?.toString();
    for (final option in widget.audienceOptions) {
      if (option.id == id) return option.label;
    }
    return audience['type'] == 'user' ? 'Сотрудник' : 'Филиал';
  }

  void _submit() {
    final end = _allDay ? null : (_end ?? _start.add(const Duration(hours: 1)));
    Navigator.pop(context, {
      'title': _title.text.trim(),
      if (_body.text.trim().isNotEmpty) 'body': _body.text.trim(),
      'allDay': _allDay,
      'startAt': _start.toUtc().toIso8601String(),
      if (end != null) 'endAt': end.toUtc().toIso8601String(),
      'audiences': _audiences,
      if (_reminder)
        'reminders': _existingReminders.isNotEmpty
            ? _existingReminders
            : [
                {
                  'dueAt': _start
                      .subtract(const Duration(hours: 1))
                      .toUtc()
                      .toIso8601String(),
                  'channel': 'in_app',
                },
              ],
      if (widget.task != null) 'expectedVersion': widget.task!['version'],
    });
  }
}

class _DateTimeButton extends StatelessWidget {
  const _DateTimeButton({
    required this.label,
    required this.value,
    required this.onChanged,
    this.dateOnly = false,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final bool dateOnly;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(
        DateFormat(dateOnly ? 'dd.MM.yyyy' : 'dd.MM.yyyy HH:mm').format(value),
      ),
      trailing: const Icon(Icons.calendar_month_outlined),
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now().add(const Duration(days: 3650)),
        );
        if (date == null || !context.mounted) return;
        if (dateOnly) {
          onChanged(DateTime(date.year, date.month, date.day));
          return;
        }
        final time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(value),
        );
        if (time == null) return;
        onChanged(
          DateTime(date.year, date.month, date.day, time.hour, time.minute),
        );
      },
    );
  }
}

String _profileLabel(Map<String, dynamic> profile) {
  final first = profile['first_name']?.toString().trim() ?? '';
  final last = profile['last_name']?.toString().trim() ?? '';
  final name = '$first $last'.trim();
  return name.isEmpty ? 'Сотрудник' : name;
}
